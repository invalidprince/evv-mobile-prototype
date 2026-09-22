#!/bin/bash
# build 87 / server v0.4.615 — 2:1 SECOND-STAFF VERIFICATION on the phone.
# Offline pins on the shipped files (never copies) + decode test against the
# server's REAL payload shape + optional compile.
#   bash docs/two-to-one-verify-check/check.sh            # pins + decode + xcodebuild
#   bash docs/two-to-one-verify-check/check.sh --no-build # pins + decode only
set -u
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok() { local label=$1; shift; if eval "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $label"; else fail=$((fail+1)); echo "  ✗ $label"; fi; }
API=EVVMobile/Services/APIClient.swift
AS=EVVMobile/State/AppState.swift
TV=EVVMobile/Views/Today/TodayView.swift
AV=EVVMobile/Views/Today/ActiveVisitCard.swift
CI=EVVMobile/Views/Punch/ClockInConfirmSheet.swift
UV=EVVMobile/Views/Today/UnscheduledVisitSheet.swift
EVV_POC=${EVV_POC:-$(cd "$(dirname "$0")/../.." && ls -d ../focus-nexus*/evv-poc ../../focus-nexus/evv-poc 2>/dev/null | head -1)}
swift_struct() { awk "/^struct $2[ :]/,/^}/" "$1"; }

echo "[1] payload contract — additive optional keys (older servers omit them)"
ok "ShiftsResponse decodes twoToOneVerify: TwoToOneVerifyPayload?" "grep -q 'let twoToOneVerify: TwoToOneVerifyPayload?' $API"
ok "ServerIndividualOption decodes twoToOneServices: [String]?"    "grep -q 'let twoToOneServices: \[String\]?' $API"
ok "ClockInRequest / UnscheduledVisitRequest carry an OPTIONAL secondStaffId (absent = old payload)" "grep -c 'var secondStaffId: String? = nil' $API | grep -q '^2$'"
ok "Visit carries serverIndividualId (mapped from s.individual.id)" "grep -q 'var serverIndividualId: String?' EVVMobile/Models/Models.swift && grep -q 'visit.serverIndividualId = s.individual.id' $AS"

echo "[2] API surface — the four server routes, token identity, online-only"
ok "fetchTwoToOneCandidates → /two-to-one/candidates" "grep -q 'two-to-one/candidates' $API"
ok "requestTwoToOne → /visits/:id/two-to-one/request" "grep -q 'two-to-one/request' $API"
ok "confirmTwoToOne → /two-to-one/:id/confirm, 409 classified like a clock-in (stillClockedIn / conflict)" "grep -q 'two-to-one/\\\\(requestId)/confirm' $API && grep -A12 'func confirmTwoToOne' $API | grep -q 'clockInConflict'"
ok "declineTwoToOne → /two-to-one/:id/decline" "grep -q 'two-to-one/\\\\(requestId)/decline' $API"
ok "fetchTwoToOneStatus → /two-to-one/status (5 s poll while pending)" "grep -q 'two-to-one/status' $API && grep -q 'Task.sleep(nanoseconds: 5_000_000_000)' $AS"
ok "confirm is NEVER queued offline (refused with a message when offline)" "grep -A8 'func confirmTwoToOne' $AS | grep -q 'effectivelyOnline'"
ok "a queued clock-in DROPS the second-staff request (120 s window is online-only)" "grep -q 'dropped from the offline queue' $AS"
ok "no client-side staff id in any body other than secondStaffId (identity = token)" "! grep -q 'requesterId\|confirmerId' $API"

echo "[3] Today — the 'verify you're here' banner (countdown + Confirm + Not here)"
ok "TodayView renders TwoToOneVerifyBanner for each appState.twoToOnePending" "grep -q 'ForEach(appState.twoToOnePending)' $TV && grep -q 'TwoToOneVerifyBanner(request: req)' $TV"
ok "banner placed ABOVE the active-visit card" "[ \$(grep -n 'TwoToOneVerifyBanner(request: req)' $TV | cut -d: -f1) -lt \$(grep -n 'ActiveVisitCard()' $TV | head -1 | cut -d: -f1) ]"
ok "banner counts down every second off expiresAt (TimelineView + secondsRemaining)" "grep -q 'TimelineView(.periodic(from: .now, by: 1))' $TV && grep -q 'request.secondsRemaining(at: ctx.date)' $TV"
ok "Confirm disabled once the timer hits 0 and while another visit is running" "grep -q 'disabled(isSubmitting || left <= 0 || appState.hasActiveVisit)' $TV"
ok "banner text names the requester, the individual and the matched clock-in" "grep -q 'clocked in with' $TV && grep -q 'same clock-in time' $TV"
ok "Not here → declineTwoToOne; confirm → confirmTwoToOne (own GPS)" "grep -q 'appState.declineTwoToOne(request)' $TV && grep -q 'appState.confirmTwoToOne(request)' $TV"
ok "success only on .synced/.queued; refusal shown inline (build 57 rule)" "grep -A3 'case .synced, .queued:' $TV | grep -q 'confirmedMessage' && grep -q 'case .rejected(let msg): error = msg' $TV"
ok "banner lives in TodayView.swift (no new file → no hand-edited pbxproj)" "grep -q 'struct TwoToOneVerifyBanner' $TV && ! grep -q 'TwoToOneVerifyBanner.swift' EVVMobile.xcodeproj/project.pbxproj"

echo "[4] requester side — active-visit card state + Request again"
ok "ActiveVisitCard shows the 2:1 row only for a 2:1 visit with a server id" "grep -q 'visit.ratio == \"2:1\", visit.serverVisitId != nil' $AV"
ok "waiting state with live countdown" "grep -q 'Waiting for' $AV && grep -q 'secondsRemaining(at: ctx.date)' $AV"
ok "confirmed → 'verified — clock-in times matched'" "grep -q 'verified — clock-in times matched at' $AV"
ok "expired / declined → not clocked in + Request again → TwoToOneRequestSheet" "grep -q 'did not verify in time' $AV && grep -q 'Request again' $AV && grep -q 'TwoToOneRequestSheet(visit: visit)' $AV"
ok "no request yet on a needs-2nd-staff visit → 'Request second staff'" "grep -q 'Request second staff' $AV"

echo "[5] pickers — scheduled Clock In sheet + Unscheduled sheet (2:1 services ONLY)"
ok "ClockInConfirmSheet shows TwoToOneStaffPicker only when visit.ratio == \"2:1\"" "grep -q 'appState.mode == .server && visit.ratio == \"2:1\"' $CI && grep -q 'TwoToOneStaffPicker(clientId: visit.serverIndividualId, shiftId: visit.serverShiftId' $CI"
ok "…and sends secondStaffId only for a 2:1 shift" "grep -q 'secondStaffId: visit.ratio == \"2:1\" ? secondStaffId : nil' $CI"
ok "Unscheduled sheet: picker only for twoToOneServices on a LIVE punch, exactly one individual" "grep -q 'twoToOneServices ?? \[\]).contains(selectedServiceName)' $UV && grep -q 'selectedIndividualIds.count == 1' $UV && grep -q 'selectedServiceIsTwoToOne && !manualEntryActive' $UV"
ok "Unscheduled sheet: selection reset when service/individual changes" "grep -c 'twoToOneSecondStaffId = nil' $UV | grep -q '^2$'"
ok "Unscheduled sheet: POST carries twoToOneParam (nil unless the picker was showing)" "grep -q 'twoToOnePickerActive ? twoToOneSecondStaffId : nil' $UV && grep -q 'secondStaffId: secondStaff' $UV"
ok "picker pre-selects the scheduled partner (onShift) and offers 'Nobody yet'" "grep -q 'onShift ?? false' $TV && grep -q 'Text(\"Nobody yet\").tag(\"\")' $TV"
ok "picker copy: never clocks them in / window seconds quoted from the server" "grep -q 'seconds to confirm' $TV && grep -q 'windowSec = w' $TV"

echo "[6] decode test against the server's REAL describe() shape"
mkdir -p /tmp/evv-tto87
if [ -n "$EVV_POC" ] && [ -f "$EVV_POC/two-to-one-verify.js" ]; then
  node docs/two-to-one-verify-check/gen_sample.js "$EVV_POC" > /tmp/evv-tto87/sample.json
else
  cp docs/two-to-one-verify-check/sample.json /tmp/evv-tto87/sample.json
fi
{
  echo "import Foundation"
  for st in ServerPartner ServerVisitInfo ServerShiftVisitInfo ServerIndividual ServerShift ShiftsResponse ServerOpenRule ServerTwoToOneRequest TwoToOneVerifyPayload TwoToOneCandidate TwoToOneCandidatesResponse TwoToOneConfirmResponse UnscheduledVisitCreated ClockInRequest UnscheduledVisitRequest; do
    swift_struct $API $st
  done
  swift_struct EVVMobile/Services/PunchReminderCenter.swift PunchReminderPolicy
  grep -v "^import Foundation" docs/two-to-one-verify-check/decode_test.swift
} > /tmp/evv-tto87/main.swift
if swiftc -O -o /tmp/evv-tto87/run /tmp/evv-tto87/main.swift 2>/tmp/evv-tto87/compile.log && /tmp/evv-tto87/run /tmp/evv-tto87/sample.json > /tmp/evv-tto87/out.log; then
  pass=$((pass+1)); echo "  ✓ decode_test.swift: $(tail -1 /tmp/evv-tto87/out.log)"
else
  fail=$((fail+1)); echo "  ✗ decode_test.swift"; cat /tmp/evv-tto87/compile.log /tmp/evv-tto87/out.log | tail -30
fi

echo "[7] build number"
ok "Info.plist CFBundleVersion is 87" "grep -A1 CFBundleVersion EVVMobile/Info.plist | grep -q '<string>87</string>'"

if [ "${1:-}" != "--no-build" ]; then
  echo "[8] compile (xcodebuild, simulator, no signing) — takes a few minutes"
  if xcodebuild build -project EVVMobile.xcodeproj -scheme EVVMobile -destination 'generic/platform=iOS Simulator' \
       -derivedDataPath /tmp/evv-dd-tto87 CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | grep -q " error:"; then
    fail=$((fail+1)); echo "  ✗ compile"
  else
    ok "compile produced EVVMobile.app" '[ -x /tmp/evv-dd-tto87/Build/Products/Debug-iphonesimulator/EVVMobile.app/EVVMobile ]'
  fi
fi

echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
