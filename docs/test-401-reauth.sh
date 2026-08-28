#!/bin/bash
# test-401-reauth.sh — regression guards for build 46's central 401 handling.
#
# The defect class (Todoist 6hP7jRHPQgXff3Rq): nothing in the app reacted to a
# 401 — per-screen catches rendered the RAW server string ("Unknown staff id")
# on a permanent red card whose Try Again replayed the same dead token forever.
# The fix is CENTRAL (APIClient.performRequest → refresh → retry → session-end
# notification → AppState sign-out), so these greps assert the wiring that a
# future refactor could silently detach.
#
# ⚠️ Comment-stripping: line comments only (the v0.4.331 lesson — a naive
# /*…*/ stripper eats code through string literals). Swift here uses // only.
set -u
cd "$(dirname "$0")/.."
API="EVVMobile/Services/APIClient.swift"
STATE="EVVMobile/State/AppState.swift"
PASS=0; FAIL=0

strip() { sed 's|//.*$||' "$1"; }

ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ❌ $1"; }

check() { # check <file-content-cmd> <pattern> <desc>
  if eval "$1" | grep -qE "$2"; then ok "$3"; else bad "$3"; fi
}
check_absent() {
  if eval "$1" | grep -qE "$2"; then bad "$3"; else ok "$3"; fi
}

echo "== APIClient: central 401 handling =="
# performRequest wraps transportRequest and branches on 401
check "strip $API" 'transportRequest\(request\)' "performRequest funnels through transportRequest"
check "strip $API" 'refreshAfter401\(failedToken:' "401 path attempts a token refresh (single-flight)"
# the retry carries the NEW token
check "strip $API" 'retry\.setValue\("Bearer \\\(newToken\)"' "retry is signed with the refreshed token"
# refresh endpoint is exempt (no recursion)
check "strip $API" 'hasSuffix\("/token/refresh"\)' "refresh call itself is exempt from 401 handling"
# unauthenticated (login) calls exempt: guard requires an Authorization header
check "strip $API" 'request\.value\(forHTTPHeaderField: "Authorization"\)' "requests without an auth header (login) are exempt"
# session end is ANNOUNCED, not swallowed
check "strip $API" 'NotificationCenter\.default\.post\(name: \.evvSessionExpired' "session end posts .evvSessionExpired"
# refreshAfter401 returns true only when the token actually CHANGED
check "strip $API" 'return token != nil && token != before' "a refresh that fails/401s reports false (no dead-token replay)"

echo "== APIClient: no raw server strings on 401 =="
# checkAuth must throw the human copy, never the decoded body
check "strip $API" 'throw APIError\.unauthorized\("Your session ended' "checkAuth throws the human copy"
check_absent "strip $API | grep -A6 'private func checkAuth'" 'unauthorized\(errBody\)' "checkAuth no longer passes the raw server string to the UI"

echo "== AppState: central observer + clean sign-out =="
check "strip $STATE" 'forName: \.evvSessionExpired' "AppState observes .evvSessionExpired"
check "strip $STATE | grep -A8 'func handleSessionExpired'" 'signOut\(\)' "handleSessionExpired performs the clean sign-out"
check "strip $STATE | grep -A8 'func handleSessionExpired'" 'Your session ended' "user sees the plain explanation"
# punch preservation across the forced sign-out (build 45 invariant, relied on here)
check "strip $STATE" 'offlineQueue\.filter \{ \$0\.isPunch \}' "signOut still preserves queued punches to disk"
check "strip $STATE" 'restoreOfflineQueue' "queue restores on the next sign-in"

echo "== AppState: 401 mid-sync never drops queued work =="
check "strip $STATE" 'var sessionDead = false' "replay tracks a dead session"
check "strip $STATE | grep -B2 -A10 'case \.unauthorized = error'" 'sessionDead = true' "unauthorized replay error stops the replay"
# the unauthorized branch must NOT burn a retry (no retryCount += 1 within it)
check_absent "strip $STATE | grep -A10 'case \.unauthorized = error' | head -12" 'retryCount \+= 1' "unauthorized never burns a queue retry"
# and the post-sign-out queue write is guarded (nil-staff-id clobber)
check "strip $STATE" 'if sessionDead \|\| !isLoggedIn \{ return \}' "replay never re-persists the queue after sign-out (envelope clobber guard)"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
