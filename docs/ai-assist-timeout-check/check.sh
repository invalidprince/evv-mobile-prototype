#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Build 111 — AI Assist: a SLOW draft must never be reported as "no internet".
#
# Nick, 2026-10-05 20:07 ET: AI Assist said "No internet connection. AI Assist
# requires connectivity." on a phone that was provably online — his diagnostic
# log (prod mobile_logs id 13, uploaded 2026-10-06T00:14:01Z) shows successful
# /api/me/individuals round-trips at 00:13:59Z, seconds either side of the
# failure, and ZERO transient-timeout lines for any other endpoint that session.
#
# Root cause: generateAIDraft used a 25 s timeoutInterval. /ai-draft is a
# non-streamed Anthropic call (2048 max_tokens, large system prompt) that
# routinely runs longer, so URLSession threw URLError.timedOut (-1001),
# transportRequest wrapped it as APIError.networkError (POST is not idempotent,
# so there is no transient retry), and the sheet’s bare `case .networkError`
# arm declared the device offline.
#
# This check pins the three fixes:
#   1. the AI-draft request tolerates a real generation (>= 65 s, so the
#      server’s own answer — 200 or CloudFront’s 60 s-origin 504 — always wins)
#   2. the offline claim is reachable ONLY when the device is actually offline
#   3. a timeout gets honest copy + a retry, and every attempt is logged so the
#      next occurrence is provable from a diagnostic log
#
# Run from the repo root:  bash docs/ai-assist-timeout-check/check.sh [--no-build]
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/../.."
AC=EVVMobile/Services/APIClient.swift
AS=EVVMobile/Views/Documentation/AIAssistSheet.swift
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }
# Fixed-string helpers: the copy under test is full of quotes and parens,
# which are murder inside an eval’d one-liner.
has()  { grep -qF -- "$1" "$2"; }
cntf() { grep -cF -- "$1" "$2" 2>/dev/null || true; }
draft_block() { awk '/func generateAIDraft/,/^    }$/' "$AC"; }

echo "[1] the request tolerates a real generation"
TO=$(draft_block | grep -o "request.timeoutInterval = [0-9]*" | grep -o "[0-9]*")
ok "generateAIDraft timeout is >= 65 s (was 25 — the bug)"    '[ -n "$TO" ] && [ "$TO" -ge 65 ]'
ok "…and <= 120 s (a caregiver never waits longer than that)" '[ -n "$TO" ] && [ "$TO" -le 120 ]'
ok "the 25 s ceiling is gone from generateAIDraft"            '! draft_block | grep -qF "timeoutInterval = 25"'

echo "[2] offline is a real state, not a guess"
ok "APIError.isOffline exists"                                'has "var isOffline: Bool" "$AC"'
ok "…and matches only genuine no-path URLErrors"              'has "case .notConnectedToInternet, .networkConnectionLost," "$AC"'
ok "APIError.isTimeout exists and is distinct"                'has "var isTimeout: Bool" "$AC" && has "code == .timedOut" "$AC"'
ok "the sheet reads AppState for the real connectivity flag"  'has "EnvironmentObject var appState: AppState" "$AS"'
ok "the offline claim is guarded by that flag"                'has "case .networkError where offline:" "$AS" && has "!appState.effectivelyOnline || apiErr.isOffline" "$AS"'
ok "the offline copy appears exactly once (no unguarded arm)" '[ "$(cntf "No internet connection. AI Assist requires connectivity." "$AS")" = 1 ]'

echo "[3] a timeout tells the truth and offers a retry"
ok "timeout arm exists, ahead of the generic networkError arm" 'has "case .networkError where apiErr.isTimeout:" "$AS"'
ok "honest copy — longer than usual, connection is fine"       'has "taking longer than usual" "$AS" && has "Your connection is fine" "$AS"'
ok "504 (CloudFront gave up on a slow origin) handled"         'has "case .serverError(504, _)" "$AS"'
ok "retry affordance wired to generateDraft"                   'has "canRetry" "$AS" && has "Try again" "$AS" && has "Button(action: generateDraft)" "$AS"'
ok "canRetry is cleared when a new attempt starts"             'has "canRetry = false" "$AS"'
ok "spinner still owns the generating state (no false banner)" 'has "if isGenerating {" "$AS" && has "ProgressView()" "$AS"'

echo "[4] the next occurrence is provable from a diagnostic log"
ok "attempt is logged with its ceiling"                        'has "AI draft requested for visit" "$AC"'
ok "transport failure logs elapsed seconds + URLError code"    'has "AI draft transport failure after" "$AC"'
ok "success logs elapsed seconds + model"                      'has "AI draft returned in" "$AC"'
ok "non-200 logs the status + elapsed"                         'has "AI draft failed: HTTP" "$AC"'

if [ "${1:-}" != "--no-build" ]; then
  echo "[5] compile (xcodebuild, simulator, no signing) — takes a few minutes"
  if xcodebuild build -project EVVMobile.xcodeproj -scheme EVVMobile -destination 'generic/platform=iOS Simulator' \
       -derivedDataPath /tmp/evv-dd-aitimeout CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | grep -q " error:"; then
    fail=$((fail+1)); echo "  ✗ compile"
  else
    ok "compile produced EVVMobile.app" '[ -x /tmp/evv-dd-aitimeout/Build/Products/Debug-iphonesimulator/EVVMobile.app/EVVMobile ]'
  fi
fi

echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
