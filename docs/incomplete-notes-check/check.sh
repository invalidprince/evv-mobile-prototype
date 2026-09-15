#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Build 70 — Today's incomplete-documentation card reads PREVIOUS dates from
# historyVisits (Todoist 6hVvh2hr9qM9r2cH).
#
# Nick, 2026-09-15: "it's now not showing on the iOS. It showed initially but
# after sync, it removed an incomplete note from yesterday, 9/14."
#
# ROOT CAUSE: `incompleteNoteVisits` read `pastVisits`, which is populated ONLY
# from GET /api/me/shifts — a today-forward payload (visit-core.myShiftsPayload:
# `if (s.date < today ...) return false`). So `pastVisits = newPast` in
# refreshServerShifts() always assigned an EMPTY array in server mode, and no
# past-dated incomplete note could ever render. The card he saw "initially" was
# MockData.pastVisits()'s `docComplete: false` demo row, which the first sync
# replaced with the empty real list.
#
# Section [0] EXECUTES the real selector (spliced out of AppState.swift between
# the BEGIN/END markers), so this is a behaviour test, not a grep of intent.
# It also includes a NEGATIVE CONTROL: the old pastVisits-based property is
# reconstructed and must FAIL the bug test, proving the suite is non-vacuous.
#
# Run from the repo root:  bash docs/incomplete-notes-check/check.sh [--no-build]
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/../.."
AS=EVVMobile/State/AppState.swift
TV=EVVMobile/Views/Today/TodayView.swift
VC=visit-core.js
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }

WORK=/tmp/evv-incnotes
mkdir -p "$WORK"

splice() {
  # $1 = selector source file, $2 = output main.swift
  awk '/^    \/\/ BEGIN incomplete-notes-source/,/^    \/\/ END incomplete-notes-source/' "$AS" > "$WORK/selector.swift"
  python3 - "$1" "$WORK/selector.swift" "$2" <<'PY'
import sys
harness = open(sys.argv[1]).read()
selector = open(sys.argv[2]).read()
open(sys.argv[3], 'w').write(harness.replace('INCOMPLETE_NOTES_SOURCE_PLACEHOLDER', selector))
PY
}

echo "[0] THE REAL incompleteNoteVisits selector, extracted and EXECUTED"
if ! awk '/^    \/\/ BEGIN incomplete-notes-source/,/^    \/\/ END incomplete-notes-source/' "$AS" | grep -q "incompleteNoteVisits"; then
  fail=$((fail+1)); echo "  ✗ BEGIN/END incomplete-notes-source markers missing or empty in $AS"
else
  splice docs/incomplete-notes-check/selector_test.swift "$WORK/main.swift"
  if swiftc -O -o "$WORK/run" "$WORK/main.swift" 2>"$WORK/compile.log" && "$WORK/run" > "$WORK/out.log"; then
    pass=$((pass+1)); echo "  ✓ selector_test.swift: $(tail -1 "$WORK/out.log")"
  else
    fail=$((fail+1)); echo "  ✗ selector_test.swift"
    cat "$WORK/compile.log" "$WORK/out.log" 2>/dev/null | tail -30
  fi
fi

echo "[0b] NEGATIVE CONTROL — the OLD pastVisits-only selector must FAIL section [A]"
# Rebuild the pre-build-70 property verbatim and run the same suite against it.
# If this PASSES, the suite is not actually testing the fix.
cat > "$WORK/old_selector.swift" <<'OLD'
    var incompleteNoteVisits: [Visit] {
        let today = todayVisits.filter { $0.status == .completed && !$0.docComplete }
        let past = pastVisits.filter { $0.status == .completed && !$0.docComplete }
        return (today + past).sorted { $0.scheduledStart > $1.scheduledStart }
    }
OLD
python3 - docs/incomplete-notes-check/selector_test.swift "$WORK/old_selector.swift" "$WORK/old_main.swift" <<'PY'
import sys
harness = open(sys.argv[1]).read()
selector = open(sys.argv[2]).read()
open(sys.argv[3], 'w').write(harness.replace('INCOMPLETE_NOTES_SOURCE_PLACEHOLDER', selector))
PY
if swiftc -O -o "$WORK/old_run" "$WORK/old_main.swift" 2>"$WORK/old_compile.log"; then
  if "$WORK/old_run" > "$WORK/old_out.log" 2>&1; then
    fail=$((fail+1)); echo "  ✗ the OLD selector PASSED the suite — the tests do not detect the bug"
  else
    pass=$((pass+1)); echo "  ✓ the OLD selector fails it: $(tail -1 "$WORK/old_out.log")"
  fi
else
  # The old property does not read historyVisits at all, so a compile failure
  # here would mean the shim changed shape — treat as a real failure.
  fail=$((fail+1)); echo "  ✗ could not compile the old selector control"; tail -10 "$WORK/old_compile.log"
fi

echo "[1] AppState — the selector reads HISTORY for previous dates in server mode"
ok "server mode sources past rows from historyVisits" 'awk "/BEGIN incomplete-notes-source/,/END incomplete-notes-source/" $AS | grep -q "pastSource = historyVisits.filter"'
ok "mock mode still sources pastVisits"               'awk "/BEGIN incomplete-notes-source/,/END incomplete-notes-source/" $AS | grep -q "pastSource = pastVisits.filter"'
ok "serverDocStatus == complete is excluded"          'awk "/BEGIN incomplete-notes-source/,/END incomplete-notes-source/" $AS | grep -q "docStatus == \\\"complete\\\""'
ok "denied/deleted ghost rows are excluded"           'awk "/BEGIN incomplete-notes-source/,/END incomplete-notes-source/" $AS | grep -q "approval == \\\"denied\\\""'
ok "history contributes only dates before today"      'awk "/BEGIN incomplete-notes-source/,/END incomplete-notes-source/" $AS | grep -q "visit.scheduledStart < startOfToday"'
ok "dedupe keys on the SERVER identity, not the local UUID" 'awk "/BEGIN incomplete-notes-source/,/END incomplete-notes-source/" $AS | grep -q "seenVisitIds" && awk "/BEGIN incomplete-notes-source/,/END incomplete-notes-source/" $AS | grep -q "seenShiftIds"'
ok "the root cause is recorded in the source"         'awk "/BEGIN incomplete-notes-source/,/END incomplete-notes-source/" $AS | grep -q "today-forward\|today + the"'

echo "[2] History is actually FETCHED on the paths that render the card"
ok "login (password) refreshes history"        'awk "/func loginWithServer/,/LocationManager.shared.requestPermission/" $AS | grep -q "await refreshHistory()"'
ok "login (Google) refreshes history"         'awk "/func loginWithGoogle/,/LocationManager.shared.requestPermission/" $AS | grep -q "await refreshHistory()"'
ok "Today pull-to-refresh refreshes history"  'awk "/.refreshable \{/,/^            \}/" $TV | grep -q "refreshHistory()"'
ok "Today onAppear warms history (debounced)" 'awk "/.onAppear \{/,/^            \}/" $TV | grep -q "refreshHistoryIfStale"'
ok "onAppear only in server mode"             'awk "/.onAppear \{/,/^            \}/" $TV | grep -q "appState.mode == .server"'
ok "foreground sync already covers history (syncNow)" 'awk "/func syncNow/,/^    \}/" $AS | grep -q "refreshHistory()"'
ok "submitting a note clears the card in historyVisits" 'awk "/func markServerDocComplete/,/^    \}/" $AS | grep -q "historyVisits\[i\].docComplete = true"'

echo "[3] The server payload boundary this bug came from is UNCHANGED"
SRV=../focus-nexus/evv-poc
if [ -f "$SRV/$VC" ]; then
  ok "/api/me/shifts is still today-forward (nothing was widened)" 'grep -q "if (s.date < today || s.date > endDate) return false;" '"$SRV/$VC"
  ok "/api/me/visits still looks BACK (the source of the past rows)" 'grep -q "const startDate = dateOffsetET(-(days - 1));" '"$SRV/$VC"
  ok "no server change was needed for this card" '[ -z "$(git -C '"$SRV"' diff --name-only -- visit-core.js api.js)" ]'
else
  echo "  … evv-poc not checked out beside this repo; skipping payload assertions"
fi

echo "[4] Nothing else changed behaviour"
ok "MockData still seeds its demo incomplete row" 'grep -q "docComplete: false)" EVVMobile/Models/MockData.swift'
ok "IncompleteNoteCard already renders past dates" 'awk "/struct IncompleteNoteCard/,/^}/" $TV | grep -q "isDateInYesterday"'
ok "IncompleteNoteCard escalates to LATE" 'awk "/struct IncompleteNoteCard/,/^}/" $TV | grep -q "LATE"'
ok "Info.plist CFBundleVersion = 70" 'grep -A1 CFBundleVersion EVVMobile/Info.plist | grep -q "<string>70</string>"'

if [ "${1:-}" != "--no-build" ]; then
  echo "[5] The project still COMPILES for the simulator"
  # Pick a simulator by its UDID, never by a name fragment: an earlier version
  # of this script matched "iPhone 16e" with `name:iPhone [0-9]*` and truncated
  # it to the non-existent "iPhone 16", so the compile step failed on a harness
  # bug while the code was fine.
  DEST_ID=$(xcodebuild -project EVVMobile.xcodeproj -scheme EVVMobile -showdestinations 2>/dev/null \
    | grep 'platform:iOS Simulator' | grep 'name:iPhone' | grep -v placeholder \
    | head -1 | sed -n 's/.*id:\([0-9A-Fa-f-]*\).*/\1/p')
  if [ -z "$DEST_ID" ]; then
    fail=$((fail+1)); echo "  ✗ no iPhone simulator destination found"
  elif xcodebuild -project EVVMobile.xcodeproj -scheme EVVMobile \
       -destination "platform=iOS Simulator,id=$DEST_ID" -configuration Debug build \
       > "$WORK/build.log" 2>&1; then
    pass=$((pass+1)); echo "  ✓ xcodebuild BUILD SUCCEEDED (sim $DEST_ID)"
  else
    fail=$((fail+1)); echo "  ✗ xcodebuild failed"; grep -E "error:" "$WORK/build.log" | head -20
  fi
fi

echo ""
echo "incomplete-notes-check: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
