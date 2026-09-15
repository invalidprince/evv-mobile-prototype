#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Build 71 — Missed shift reason + resolution on iOS (Todoist 6hWM5wChpj4rxVPH,
# server v0.4.505/v0.4.508). Nick 2026-09-15: "required 'Missed Shift Reason'
# … request the shift to be created … or put in a reason … should show up on
# todo list … dashboard AND iOS."
#   [0] the REAL model structs decode the REAL server payload (gen_sample.js
#       runs evv-poc's own builders) + MissedShiftPrefill agency-tz parsing
#   [1..4] wiring greps: API, AppState, Today card, Work tab, RequestShiftSheet
#   [5] build number   [6] simulator compile
# Run from the repo root:  bash docs/missed-shift-check/check.sh [--no-build]
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/../.."
API=EVVMobile/Services/APIClient.swift
AS=EVVMobile/State/AppState.swift
TV=EVVMobile/Views/Today/TodayView.swift
MC=EVVMobile/Views/Today/MissedShiftCard.swift
WV=EVVMobile/Views/Work/WorkView.swift
RS=EVVMobile/Views/Work/RequestShiftSheet.swift
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }
swift_struct() { awk "/^struct $2[ :]/,/^}/" "$1"; }

echo "[0] decoder + prefill — REAL structs, REAL server payload"
mkdir -p /tmp/evv-missed
node docs/missed-shift-check/gen_sample.js > /tmp/evv-missed/sample.json 2>/tmp/evv-missed/gen.log; cat /tmp/evv-missed/gen.log
{
  echo "import Foundation"
  swift_struct $API MissedShiftItem
  swift_struct $API MissedShiftsResponse
  swift_struct $API MissedShiftResolveBody
  swift_struct $API MissedShiftResolveResponse
  swift_struct $API ShiftRequestBody
  swift_struct $API WorkItem
  swift_struct $RS MissedShiftPrefill
  grep -v "^import Foundation" docs/missed-shift-check/decode_test.swift
} > /tmp/evv-missed/main.swift
if swiftc -O -o /tmp/evv-missed/run /tmp/evv-missed/main.swift 2>/tmp/evv-missed/compile.log && /tmp/evv-missed/run /tmp/evv-missed/sample.json > /tmp/evv-missed/out.log; then
  pass=$((pass+1)); echo "  ✓ decode_test.swift: $(tail -1 /tmp/evv-missed/out.log)"
else
  fail=$((fail+1)); echo "  ✗ decode_test.swift"; cat /tmp/evv-missed/compile.log /tmp/evv-missed/out.log | tail -30
fi

echo "[1] APIClient"
ok "GET /me/missed-shifts; 403 → .forbidden (card hidden, not empty)" 'awk "/func fetchMissedShifts/,/^    }/" $API | grep -q "me/missed-shifts" && awk "/func fetchMissedShifts/,/^    }/" $API | grep -q "statusCode == 403" && awk "/func fetchMissedShifts/,/^    }/" $API | grep -q "APIError.forbidden"'
ok "POST /me/missed-shifts/:shiftId/resolve; 409 → .conflict, 403 → .forbidden" 'awk "/func resolveMissedShift/,/^    }/" $API | grep -q "me/missed-shifts/\\\\(shiftId)/resolve" && awk "/func resolveMissedShift/,/^    }/" $API | grep -q "statusCode == 409" && awk "/func resolveMissedShift/,/^    }/" $API | grep -q "APIError.conflict"'
ok "resolve: 200 with unreadable body = COMMITTED (responseUnreadable), never a failed write" 'awk "/func resolveMissedShift/,/^    }/" $API | grep -q "APIError.responseUnreadable"'
ok "requestShift takes shiftId (default nil) and encodes it" 'grep -q "shiftId: Int? = nil) async throws -> ShiftRequestResponse" $API && awk "/func requestShift\\(/,/^    }/" $API | grep -q "shiftId: shiftId"'
ok "no offline queue for either path (grep: no QueuedAction for missed)" '! grep -q "missedShift" EVVMobile/Models/Models.swift'

echo "[2] AppState"
ok "missedShifts published, memory-only (never in LocalCache)" 'grep -q "@Published var missedShifts: \[MissedShiftItem\]" $AS && ! grep -q "missedShifts" EVVMobile/Services/LocalCache.swift'
ok "refreshMissedShifts: server mode + online guard; 403 empties the list" 'awk "/func refreshMissedShifts/,/^    }/" $AS | grep -q "guard mode == .server, effectivelyOnline" && awk "/func refreshMissedShifts/,/^    }/" $AS | grep -q "case .forbidden" && awk "/func refreshMissedShifts/,/^    }/" $AS | grep -q "missedShifts = \[\]"'
ok "refreshed alongside every shifts refresh (fire-and-forget)" 'grep -q "Task { await self.refreshMissedShifts() }" $AS'
ok "cleared on sign-out" 'awk "/func signOut/,/LocalCache.shared.clearAll/" $AS | grep -q "missedShifts = \[\]"'

echo "[3] Today card + sheet"
ok "MissedShiftCard.swift registered in the Xcode project (4 entries)" '[ "$(grep -c "MissedShiftCard.swift" EVVMobile.xcodeproj/project.pbxproj)" -ge 4 ]'
ok "Today renders one card per missed shift (server mode), above incomplete notes" 'awk "/ForEach\\(appState.missedShifts\\)/,/ForEach\\(appState.incompleteNoteVisits\\)/" $TV | grep -q "MissedShiftCard(item: item, isOffline: !appState.effectivelyOnline)"'
ok "empty-state hides while a missed shift is pending" 'grep -q "appState.incompleteNoteVisits.isEmpty && appState.missedShifts.isEmpty" $TV'
ok "pull-to-refresh re-reads missed shifts" 'awk "/.refreshable/,/^            }/" $TV | grep -q "refreshMissedShifts()"'
ok "sheet(item: missedTarget) → MissedShiftResolveSheet; onDismiss refreshes list + history" 'awk "/sheet\\(item: \\\$missedTarget/,/MissedShiftResolveSheet/" $TV | grep -q "refreshMissedShifts" && awk "/sheet\\(item: \\\$missedTarget/,/MissedShiftResolveSheet/" $TV | grep -q "refreshHistory"'
ok "card: offline → button disabled + passive notice (never queued)" 'grep -q ".disabled(isOffline)" $MC && grep -q "Connect to the internet to resolve" $MC'
ok "sheet: two paths — I worked this shift / It was missed" 'grep -q "\"I worked this shift\"" $MC && grep -q "\"It was missed\"" $MC'
ok "request path only when server says canRequest AND a prefill exists" 'grep -q "private var canRequest: Bool { item.offersRequest && prefill != nil }" $MC && awk "/private var chooseSection/,/^    }/" $MC | grep -q "if canRequest {"'
ok "outside the window → explains why only a reason is offered" 'grep -q "outside your role.s request window" $MC'
ok "reason picker uses the SERVER vocabulary (appState.missedShiftReasons)" 'grep -q "appState.missedShiftReasons" $MC && grep -q "ForEach(reasons, id: \\\\.self)" $MC'
ok "Other requires a comment (mirrors db.resolveMissedShiftReason)" 'grep -q "private var isOther: Bool { selectedReason.lowercased() == \"other\" }" $MC && grep -q "(!isOther || !trimmedComment.isEmpty)" $MC'
ok "save → APIClient.resolveMissedShift(shiftId:reason:comment:)" 'awk "/private func save/,/^    }/" $MC | grep -q "APIClient.shared.resolveMissedShift(" && awk "/private func save/,/^    }/" $MC | grep -q "shiftId: item.shiftId"'
ok "409 refreshes the list (state changed under us)" 'awk "/private func save/,/^    }/" $MC | grep -q "case .conflict = apiErr"'
ok "request path: RequestShiftSheet(prefill:) → handoff → DocumentationView, then closes the flow" 'grep -q "RequestShiftSheet(prefill: prefill)" $MC && grep -q "requestedDocVisit = visit" $MC && grep -q "sheet(item: \$docVisit" $MC && grep -q "DocumentationView(visit: visit)" $MC'
ok "sheet is ONLINE-ONLY (buttons disabled offline)" 'grep -c ".disabled(!online)" $MC | grep -qE "^[2-9]"'

echo "[4] Work tab + RequestShiftSheet"
ok "WorkItem decodes shiftId" 'awk "/^struct WorkItem/,/^}/" $API | grep -q "let shiftId: Int?"'
ok "native == missedshift opens the same sheet; unresolved falls through to webPath" 'grep -q "item.native == \"missedshift\"" $WV && grep -q "let missed = resolveMissedShift(item.shiftId)" $WV && grep -q "MissedShiftResolveSheet(item: item)" $WV'
ok "cold start on Work loads missed shifts when a row needs them" 'grep -q "\$0.native == \"missedshift\" && resolveMissedShift(\$0.shiftId) == nil" $WV'
ok "category missed has an icon" 'grep -q "case \"missed\": return \"calendar.badge.exclamationmark\"" $WV'
ok "RequestShiftSheet: prefill fixes individual/service/date; times editable; POST carries shiftId + verbatim date" 'grep -q "var prefill: MissedShiftPrefill? = nil" $RS && grep -q "shiftId: prefill?.shiftId" $RS && grep -q "date: prefill?.date ?? serverDateLabel(visitDate)" $RS && awk "/if let p = prefill \\{/,/^                }/" $RS | grep -q "DatePicker(\"Start\""'
ok "prefilled: roster/service/when pickers hidden (if !isPrefilled)" 'grep -q "if !isPrefilled {" $RS && grep -q "} // !isPrefilled" $RS'
ok "prefill applied once on appear (never clobbers edited times)" 'awk "/private func applyPrefill/,/^    }/" $RS | grep -q "guard let p = prefill, selectedIndividualId == nil else { return }"'
ok "reason still required on the prefilled path (canSubmit unchanged)" 'grep -q "&& !selectedServiceName.isEmpty && timesValid && !trimmedReason.isEmpty" $RS'
ok "History's plain Request-a-shift call still compiles unchanged (no prefill arg)" 'grep -q "RequestShiftSheet { visit in" EVVMobile/Views/History/HistoryView.swift'

echo "[5] build number"
ok "Info.plist CFBundleVersion = 71" 'grep -A1 CFBundleVersion EVVMobile/Info.plist | grep -q "<string>71</string>"'

if [ "${1:-}" != "--no-build" ]; then
  echo "[6] compile (xcodebuild, simulator, no signing) — takes a few minutes"
  rm -rf /tmp/evv-dd-missed
  if xcodebuild build -project EVVMobile.xcodeproj -scheme EVVMobile -destination 'generic/platform=iOS Simulator' \
       -derivedDataPath /tmp/evv-dd-missed CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | grep -q " error:"; then
    fail=$((fail+1)); echo "  ✗ compile"
  else
    ok "compile produced EVVMobile.app" '[ -x /tmp/evv-dd-missed/Build/Products/Debug-iphonesimulator/EVVMobile.app/EVVMobile ]'
  fi
fi
echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
