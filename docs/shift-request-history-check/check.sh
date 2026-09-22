#!/bin/bash
# build 90 / server v0.4.625 — SHIFT REQUESTS AS HISTORY ROWS (Todoist
# 6hXrQ7VjHH3C7q8q). Nick 2026-09-21: "Shift requests shouldnt show like this.
# It should show in the history and just show the shift details and
# approved/denied. It should only show for 2 weeks after the approval/denial."
#
# Offline pins on the shipped files (never copies) + a decode/policy test that
# lifts the REAL ServerException / ShiftRequestSummary / ShiftRequestHistoryPolicy
# out of the source and compiles them with swiftc against the server's real
# payload shapes + optional simulator compile.
#   bash docs/shift-request-history-check/check.sh            # pins + decode + xcodebuild
#   bash docs/shift-request-history-check/check.sh --no-build # pins + decode only
set -u
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok() { local label=$1; shift; if eval "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $label"; else fail=$((fail+1)); echo "  ✗ $label"; fi; }
API=EVVMobile/Services/APIClient.swift
AS=EVVMobile/State/AppState.swift
HV=EVVMobile/Views/History/HistoryView.swift
MD=EVVMobile/Models/Models.swift

echo "[1] payload contract — additive optional keys (older servers omit them)"
ok "ServerHistoryVisit decodes wasShiftRequest: Bool?"      "grep -q 'let wasShiftRequest: Bool?' $API"
ok "ServerHistoryVisit decodes approvalDecidedAt: String?"  "grep -q 'let approvalDecidedAt: String?' $API"
ok "ServerException decodes decidedAt: String? (never fatal)" "grep -q 'decidedAt = (try? c.decodeIfPresent(String.self, forKey: .decidedAt)) ?? nil' $API"
ok "ServerException decodes shiftRequest: ShiftRequestSummary? (never fatal)" "grep -q 'shiftRequest = (try? c.decodeIfPresent(ShiftRequestSummary.self, forKey: .shiftRequest)) ?? nil' $API"
ok "ShiftRequestSummary: every field optional"  "awk '/^struct ShiftRequestSummary/,/^}/' $API | grep 'let ' | grep -vq -E '[^?]\$'"
ok "v0.4.392 resolution string|object decoding untouched" "grep -q 'resolution = ServerException.outcome(fromReason: obj.reason)' $API"
ok "Visit carries wasShiftRequest + approvalDecidedAt"  "grep -q 'var wasShiftRequest: Bool = false' $MD && grep -q 'var approvalDecidedAt: Date?' $MD"
ok "mapHistoryVisit maps both"  "grep -q 'visit.wasShiftRequest = sv.wasShiftRequest ?? false' $AS && grep -q 'visit.approvalDecidedAt = ShiftRequestHistoryPolicy.parseISO(sv.approvalDecidedAt)' $AS"

echo "[2] History — the separate block is GONE, requests are rows under the shift's day"
ok "no 'Shift requests' header in HistoryView"      "! grep -q 'Text(\"Shift requests\")' $HV"
ok "build-56 ShiftRequestRow struct removed"        "! grep -q 'struct ShiftRequestRow' $HV && ! grep -rq 'ShiftRequestRow(request' EVVMobile"
ok "HistoryEntry gains .request(ServerException)"   "grep -q 'case request(ServerException)' $HV"
ok "stand-ins ONLY when no visit in the list covers the request (no approved double-up)" "grep -A8 'private var shiftRequestStandIns' $HV | grep -q 'visitIds.contains(vid)' && grep -A8 'private var shiftRequestStandIns' $HV | grep -q 'ShiftRequestHistoryPolicy.isVisible(req)'"
ok "stand-ins grouped under the SHIFT day via shiftDay()" "grep -q 'ShiftRequestHistoryPolicy.shiftDay(r)' $HV && grep -B2 'groups\[day, default: \[\]\].append(.request(r))' $HV | grep -q 'localDay(ymd'"
ok "sortKey handles .request by the request's clockIn" "grep -A6 'case .request(let r):' $HV | grep -q 'r.shiftRequest?.clockIn'"
ok "ForEach renders ShiftRequestHistoryRow for .request" "grep -A1 'case .request(let r):' $HV | grep -q 'ShiftRequestHistoryRow(request: r)'"
ok "empty-state accounts for stand-ins"  "grep -q 'missedEntries.isEmpty && shiftRequestStandIns.isEmpty' $HV"
ok "pull-to-refresh + onAppear still refresh history (requests ride with refreshHistory)" "grep -c 'await appState.refreshHistory()' $HV | grep -qE '^[3-9]$|^[1-9][0-9]+$'"

echo "[3] chips on the VISIT row — pending yellow, approved green for 14 days"
ok "PENDING APPROVAL chip on visit.isPendingApproval"  "grep -A2 'if visit.isPendingApproval {' $HV | grep -q 'PENDING APPROVAL'"
ok "SHIFT APPROVED chip on visit.showsShiftApprovedChip" "grep -A2 'else if visit.showsShiftApprovedChip {' $HV | grep -q 'SHIFT APPROVED'"
ok "showsShiftApprovedChip = wasShiftRequest && !pending && within window" "awk '/var showsShiftApprovedChip/,/^    }/' $MD | grep -q 'guard wasShiftRequest, !isPendingApproval, let at = approvalDecidedAt' && awk '/var showsShiftApprovedChip/,/^    }/' $MD | grep -q 'ShiftRequestHistoryPolicy.isWithinWindow(decidedAt: at)'"
ok "pending visit row KEEPS its action buttons (Add Note etc. — the request-then-document handoff)" "! grep -q 'isPendingApproval' <(awk '/\/\/ Action buttons/,/\.cardStyle\(\)/' $HV)"

echo "[4] the stand-in row — details + chip + reason, NO buttons"
ok "ShiftRequestHistoryRow exists"             "grep -q 'struct ShiftRequestHistoryRow: View' $HV"
ok "avatar + name + service + time range (same layout as a visit row)" "awk '/^struct ShiftRequestHistoryRow/,/^}/' $HV | grep -q 'AvatarView(name: name, size: 40)' && awk '/^struct ShiftRequestHistoryRow/,/^}/' $HV | grep -q 'Text(serviceLabel)' && awk '/^struct ShiftRequestHistoryRow/,/^}/' $HV | grep -q 'timeText'"
ok "SHIFT DENIED red / SHIFT APPROVED green / PENDING yellow" "awk '/^struct ShiftRequestHistoryRow/,/^}/' $HV | grep -q '(\"SHIFT DENIED\", Theme.danger)' && awk '/^struct ShiftRequestHistoryRow/,/^}/' $HV | grep -q '(\"SHIFT APPROVED\", Theme.success)' && awk '/^struct ShiftRequestHistoryRow/,/^}/' $HV | grep -q 'PENDING APPROVAL\", Theme.warning'"
ok "denial reason from shiftRequest.denialReason, detail trailer as fallback" "awk '/^struct ShiftRequestHistoryRow/,/^}/' $HV | grep -q 'summary?.denialReason' && awk '/^struct ShiftRequestHistoryRow/,/^}/' $HV | grep -q 'DENIED by '"
ok "no Button in the stand-in row"            "! awk '/^struct ShiftRequestHistoryRow/,/^}/' $HV | grep -q 'Button'"
ok "no new .swift file → no hand-edited pbxproj" "! grep -q 'ShiftRequestHistoryRow.swift\|ShiftRequestHistoryPolicy.swift' EVVMobile.xcodeproj/project.pbxproj"

echo "[5] the 14-day policy — one rule, compiled and executed"
TMP=$(mktemp -d)
{
  echo 'import Foundation'
  echo 'struct Theme { static let warning = 0; static let success = 1; static let danger = 2 }'
  awk '/^struct ServerException: Decodable/,/^}/' $API
  awk '/^struct ShiftRequestSummary: Decodable/,/^}/' $API
  awk '/^enum ShiftRequestHistoryPolicy/,/^}/' $HV
  cat <<'SWIFT'
var pass = 0, fail = 0
func check(_ name: String, _ cond: Bool) { if cond { pass += 1; print("  ✓ \(name)") } else { fail += 1; print("  ✗ \(name)") } }
let dec = JSONDecoder()
let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
let now = Date()
let d3 = iso.string(from: now.addingTimeInterval(-3 * 86400))
let d20 = iso.string(from: now.addingTimeInterval(-20 * 86400))

// Real v0.4.625 row: DENIED, visit soft-deleted, joined details present
let denied = """
{"id":"EX-601","type":"Shift request","visitId":"V-2099","date":"2026-09-20","status":"resolved",
 "detail":"Staff-requested shift 2026-09-20 9:00 AM–11:00 AM for Alex Rivera, service W7060. Reason: \\"forgot\\". — DENIED by Brian Klunk: \\"not on the schedule\\". The visit and its documentation were removed.",
 "resolution":"denied","resolutionDetail":{"at":"\(d3)","by":"Brian Klunk","reason":"Shift request denied: not on the schedule","comment":""},
 "decidedAt":"\(d3)",
 "shiftRequest":{"visitId":"V-2099","date":"2026-09-20","clientId":"C140925","clientName":"Alex Rivera","service":"W7060","serviceName":"In-Home & Community Support (Lvl 2)","clockIn":"9:00 AM","clockOut":"11:00 AM","outcome":"denied","requestReason":"forgot","denialReason":"not on the schedule","decidedBy":"Brian Klunk","decidedAt":"\(d3)"}}
"""
// exceptions.id is TEXT ("EX-601") — exactly what the app decodes as String.
let deniedFixed = denied
if let r = try? dec.decode(ServerException.self, from: Data(deniedFixed.utf8)) {
    check("denied row decodes with shiftRequest", r.shiftRequest != nil)
    check("outcome denied", ShiftRequestHistoryPolicy.outcome(r) == "denied")
    check("decidedAt parsed (fractional ISO)", ShiftRequestHistoryPolicy.decidedAt(r) != nil)
    check("visible 3 days after denial", ShiftRequestHistoryPolicy.isVisible(r))
    check("shiftDay = the SHIFT date", ShiftRequestHistoryPolicy.shiftDay(r) == "2026-09-20")
    check("details carried", r.shiftRequest?.clientName == "Alex Rivera" && r.shiftRequest?.clockIn == "9:00 AM" && r.shiftRequest?.denialReason == "not on the schedule")
} else { check("denied row decodes", false) }

// Same row decided 20 days ago → hidden
let old = deniedFixed.replacingOccurrences(of: d3, with: d20)
if let r = try? dec.decode(ServerException.self, from: Data(old.utf8)) {
    check("hidden 20 days after denial", !ShiftRequestHistoryPolicy.isVisible(r))
} else { check("old denied row decodes", false) }

// Pending: never expires, no decidedAt
let pending = """
{"id":"602","type":"Shift request","visitId":"V-2100","date":"2026-09-21","status":"in progress","detail":"…","resolution":null,"resolutionDetail":null,"decidedAt":null,
 "shiftRequest":{"visitId":"V-2100","date":"2026-09-21","clientId":"C1","clientName":"Erik Hoover","service":"W7061","serviceName":"CPS","clockIn":"1:00 PM","clockOut":"3:00 PM","outcome":"pending","requestReason":"x","denialReason":null,"decidedBy":null,"decidedAt":null}}
"""
if let r = try? dec.decode(ServerException.self, from: Data(pending.utf8)) {
    check("pending decodes", r.shiftRequest?.outcome == "pending")
    check("pending always visible", ShiftRequestHistoryPolicy.isVisible(r))
    check("pending decidedAt nil", ShiftRequestHistoryPolicy.decidedAt(r) == nil)
} else { check("pending row decodes", false) }

// OLD SERVER (≤ v0.4.621): no decidedAt / shiftRequest keys, resolution string only
let legacyDenied = """
{"id":"603","type":"Shift request","visitId":"V-2050","date":"2026-09-01","status":"resolved","detail":"Staff-requested shift … — DENIED by Nick: \\"dup\\". The visit and its documentation were removed.","resolution":"denied","resolutionDetail":{"at":"2026-09-02T14:00:00.000Z","by":"Nick","reason":"Shift request denied: dup","comment":""}}
"""
if let r = try? dec.decode(ServerException.self, from: Data(legacyDenied.utf8)) {
    check("legacy row decodes (no new keys)", r.shiftRequest == nil && r.decidedAt == nil)
    check("legacy outcome from resolution string", ShiftRequestHistoryPolicy.outcome(r) == "denied")
    check("legacy decided row with unknown timestamp is HIDDEN, not shown forever", !ShiftRequestHistoryPolicy.isVisible(r))
    check("legacy shiftDay from exception date", ShiftRequestHistoryPolicy.shiftDay(r) == "2026-09-01")
} else { check("legacy row decodes", false) }
let legacyPending = legacyDenied.replacingOccurrences(of: "\"status\":\"resolved\"", with: "\"status\":\"new\"").replacingOccurrences(of: "\"resolution\":\"denied\"", with: "\"resolution\":null")
if let r = try? dec.decode(ServerException.self, from: Data(legacyPending.utf8)) {
    check("legacy pending visible", ShiftRequestHistoryPolicy.outcome(r) == "pending" && ShiftRequestHistoryPolicy.isVisible(r))
} else { check("legacy pending decodes", false) }

// Garbage shiftRequest object must not kill the row
let garbage = deniedFixed.replacingOccurrences(of: "\"clientName\":\"Alex Rivera\"", with: "\"clientName\":42")
if let r = try? dec.decode(ServerException.self, from: Data(garbage.utf8)) {
    check("malformed shiftRequest → nil, row survives", r.shiftRequest == nil && r.id == "EX-601")
} else { check("garbage row decodes", false) }

// Window arithmetic
check("13d 23h inside window", ShiftRequestHistoryPolicy.isWithinWindow(decidedAt: now.addingTimeInterval(-(13 * 86400 + 23 * 3600)), now: now))
check("14d + 1h outside window", !ShiftRequestHistoryPolicy.isWithinWindow(decidedAt: now.addingTimeInterval(-(14 * 86400 + 3600)), now: now))
check("parseISO handles no-fraction ISO", ShiftRequestHistoryPolicy.parseISO("2026-09-22T10:00:00Z") != nil)
check("parseISO nil on garbage", ShiftRequestHistoryPolicy.parseISO("never") == nil && ShiftRequestHistoryPolicy.parseISO(nil) == nil)

print("\(pass) passed, \(fail) failed")
exit(fail == 0 ? 0 : 1)
SWIFT
} > "$TMP/t.swift"
if swiftc -o "$TMP/t" "$TMP/t.swift" 2>"$TMP/err"; then
  if "$TMP/t"; then pass=$((pass+1)); echo "  ✓ decode/policy test binary green"; else fail=$((fail+1)); echo "  ✗ decode/policy test binary red"; fi
else
  fail=$((fail+1)); echo "  ✗ decode/policy test did not compile"; head -20 "$TMP/err"
fi
rm -rf "$TMP"

if [ "${1:-}" != "--no-build" ]; then
  echo "[6] simulator compile"
  if xcodebuild -project EVVMobile.xcodeproj -scheme EVVMobile -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/dd-shift-request-history CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -q 'BUILD SUCCEEDED'; then
    pass=$((pass+1)); echo "  ✓ BUILD SUCCEEDED"
  else
    fail=$((fail+1)); echo "  ✗ BUILD FAILED"
  fi
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
