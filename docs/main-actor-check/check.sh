#!/bin/bash
# Build 94 verification — open-shift pickup OK crash (builds 88-93).
#
# ROOT CAUSE (proven, not inferred): build 87 inserted the "2:1 second-staff"
# section between `@MainActor` and `func refreshMissedShifts()`, stranding the
# annotation on the section MARK. From build 87 to 93 refreshMissedShifts ran
# NONISOLATED and wrote five @Published arrays from the global executor.
# Every refreshServerShifts() fires it as a fire-and-forget Task alongside the
# @MainActor refreshDueMedications(); when the two publish concurrently,
# Combine's ObservableObjectPublisher os_unfair_lock deadlocks: `sample` on
# the frozen simulator app showed the MAIN thread parked in
#   dueMedications.setter → ObservableObjectPublisher.Inner.send()
#   → _os_unfair_lock_lock_slow → __ulock_wait2
# while a BACKGROUND thread held the lock in missedShifts.setter
# (refreshMissedShifts, AppState.swift:1877). Frozen UI → iOS watchdog kill.
# That is Nick's "pick up an open shift, tap OK, app crashes": the claim
# alert's OK lands exactly when the post-claim refreshServerShifts() spawns
# both tasks. XCUITest independently reported "process main thread busy for
# 30.0s" driving the same flow against a local stub of S013's real payloads.
#
# THE FIX: @MainActor restored on refreshMissedShifts and added to the other
# async funcs that write @Published state off-main (claimOpenShift,
# submitServerNote, submitServerNonBillable, submitServerTimeFix,
# submitServerDeleteRequest). scan_main_actor.py pins the invariant for the
# whole file, with adjacency rules that catch exactly the build-87 stranding.
set -u
cd "$(dirname "$0")/../.."
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
check(){ if [ "$1" = "0" ]; then ok "$2"; else bad "$2"; fi }

APP=EVVMobile/State/AppState.swift

echo "— invariant scanner on the shipped file —"
python3 docs/main-actor-check/scan_main_actor.py "$APP" >/tmp/mac_scan_now.txt 2>&1
check $? "no async func writes @Published without an ADJACENT @MainActor ($(cat /tmp/mac_scan_now.txt | wc -l | tr -d ' ') violations)"

echo "— NON-VACUOUS CONTROL: the scanner MUST flag build 93 —"
if git show 344a4e4:EVVMobile/State/AppState.swift >/tmp/mac_appstate93.swift 2>/dev/null; then
  python3 docs/main-actor-check/scan_main_actor.py /tmp/mac_appstate93.swift >/tmp/mac_scan93.txt 2>&1
  [ $? -eq 1 ] && ok "scanner exits 1 on build 93" || bad "scanner did NOT flag build 93 — the check is vacuous"
  grep -q "refreshMissedShifts" /tmp/mac_scan93.txt && ok "build-93 report names refreshMissedShifts (the shipped bug)" || bad "refreshMissedShifts missing from build-93 report"
  grep -q "claimOpenShift" /tmp/mac_scan93.txt && ok "build-93 report names claimOpenShift" || bad "claimOpenShift missing from build-93 report"
else
  bad "cannot materialise build-93 AppState (shallow clone?) — control skipped"
fi

echo "— source pins —"
grep -B1 "func refreshMissedShifts() async" "$APP" | grep -q "@MainActor" && ok "@MainActor directly on refreshMissedShifts" || bad "@MainActor not directly on refreshMissedShifts"
grep -B1 "func claimOpenShift(shiftId: Int) async" "$APP" | grep -q "@MainActor" && ok "@MainActor directly on claimOpenShift" || bad "@MainActor not directly on claimOpenShift"
grep -B1 "private func applyTwoToOne" "$APP" | grep -q "@MainActor" && ok "@MainActor directly on applyTwoToOne (no stranded annotation left behind)" || bad "applyTwoToOne lost its @MainActor"
awk '/@MainActor$/{a=NR} /\/\/ MARK:/{if (a==NR-1) {print "stranded @MainActor above MARK at line " a; exit 1}}' "$APP" && ok "no @MainActor stranded directly above a // MARK line" || bad "a stranded @MainActor sits above a // MARK line (the build-87 shape)"
grep -A1 CFBundleVersion EVVMobile/Info.plist | grep -q "<string>94</string>" && ok "CFBundleVersion is 94" || bad "CFBundleVersion is not 94"

echo "— simulator build —"
SIM=$(xcrun simctl list devices available | grep -E "iPhone (1[5-9]|2[0-9])" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
if [ -n "$SIM" ]; then
  xcodebuild -project EVVMobile.xcodeproj -scheme EVVMobile \
    -destination "platform=iOS Simulator,id=$SIM" \
    -derivedDataPath /tmp/mac_dd build >/tmp/mac_build.log 2>&1
  if grep -q "BUILD SUCCEEDED" /tmp/mac_build.log; then ok "simulator BUILD SUCCEEDED"; else bad "simulator build failed — see /tmp/mac_build.log"; fi
else
  bad "no available iPhone simulator found"
fi

echo
echo "main-actor-check: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
