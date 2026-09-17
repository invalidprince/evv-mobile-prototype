#!/usr/bin/env bash
# Build 72 — eMAR corrections on iOS (Todoist 6hWcVX84mgjMCvMH, server v0.4.533).
#   [0] REAL structs decode a v0.4.533 payload + an OLD-server payload
#   [1..3] wiring greps: APIClient, AppState, Today card + sheet
#   [4] build number   [5] simulator compile (skip with --no-build)
set -u
cd "$(dirname "$0")/../.."
API=EVVMobile/Services/APIClient.swift
AS=EVVMobile/State/AppState.swift
TV=EVVMobile/Views/Today/TodayView.swift
MC=EVVMobile/Views/Today/MedicationsDueCard.swift
CS=EVVMobile/Views/Today/CorrectAdministrationSheet.swift
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }
swift_struct() { awk "/^struct $2[ :]/,/^}/" "$1"; }
echo "[0] decoder — REAL structs"
mkdir -p /tmp/evv-emarc
{ echo "import Foundation"; swift_struct $API DueMedication; swift_struct $API PrnMedication; swift_struct $API MedicationsResponse; swift_struct $API CorrectAdministrationBody; swift_struct $API CorrectAdministrationResponse; grep -v "^import Foundation" docs/emar-correction-check/decode_test.swift; } > /tmp/evv-emarc/main.swift
if swiftc -O -o /tmp/evv-emarc/run /tmp/evv-emarc/main.swift 2>/tmp/evv-emarc/compile.log && /tmp/evv-emarc/run docs/emar-correction-check/sample.json > /tmp/evv-emarc/out.log; then
  pass=$((pass+1)); echo "  ✓ decode_test.swift: $(tail -1 /tmp/evv-emarc/out.log)"
else fail=$((fail+1)); echo "  ✗ decode_test.swift"; cat /tmp/evv-emarc/compile.log /tmp/evv-emarc/out.log | tail -20; fi
echo "[1] APIClient"
ok "POST /emar/administrations/:id/correct; 409 → .conflict, 403 → .forbidden, unreadable 200 → responseUnreadable" 'awk "/func correctMedAdministration/,/^    }/" $API | grep -q "emar/administrations/\\\\(id)/correct" && awk "/func correctMedAdministration/,/^    }/" $API | grep -q "statusCode == 409" && awk "/func correctMedAdministration/,/^    }/" $API | grep -q "statusCode == 403" && awk "/func correctMedAdministration/,/^    }/" $API | grep -q "responseUnreadable"'
ok "given_at is ISO-8601 with offset (agency tz)" 'awk "/func correctMedAdministration/,/^    }/" $API | grep -q "withInternetDateTime" && awk "/func correctMedAdministration/,/^    }/" $API | grep -q "America/New_York"'
ok "offersCorrection = server canCorrect && !recordable (never a role guess)" 'grep -q "var offersCorrection: Bool { (canCorrect ?? false) && !recordable }" $API'
ok "no offline queue for corrections" '! grep -qi "correct" EVVMobile/Models/Models.swift'
echo "[2] AppState"
ok "correctableMedications + window hours published, memory-only, cleared on sign-out" 'grep -q "@Published var correctableMedications: \[DueMedication\]" $AS && ! grep -q "correctableMedications" EVVMobile/Services/LocalCache.swift && awk "/func signOut/,/LocalCache.shared.clearAll/" $AS | grep -q "correctableMedications = \[\]"'
ok "refreshDueMedications stores correctable + correctionWindowHours" 'awk "/func refreshDueMedications/,/^    }/" $AS | grep -q "correctableMedications = response.correctable ?? \[\]" && awk "/func refreshDueMedications/,/^    }/" $AS | grep -q "medCorrectionWindowHours = response.correctionWindowHours"'
echo "[3] Today card + sheet"
ok "CorrectAdministrationSheet.swift registered in the Xcode project (4 entries)" '[ "$(grep -c "CorrectAdministrationSheet.swift" EVVMobile.xcodeproj/project.pbxproj)" -ge 4 ]'
ok "card shows when only earlier correctable doses exist" 'grep -q "!appState.correctableMedications.isEmpty" $TV'
ok "Correct button keyed on offersCorrection; disabled offline" 'grep -q "} else if med.offersCorrection {" $MC && awk "/} else if med.offersCorrection {/,/} else if let initials/" $MC | grep -q ".disabled(!online)"'
ok "Earlier doses section + hours explanation" 'grep -q "\"Earlier doses\"" $MC && grep -q "Your role can correct a dose up to" $MC'
ok "correction marker C only — no reason anywhere in the card" 'grep -q "med.isCorrection == true" $MC && ! grep -qi "notes" $MC | grep -qi correct'
ok "sheet: four outcomes incl. missed; time picker only for given; capped at now" 'grep -q "(\"missed\", \"Missed\"" $CS && grep -q "if needsTime { timeSection }" $CS && grep -q "in: ...Date()" $CS'
ok "sheet: reason required + labelled internal" 'grep -q "Correction reason (required)" $CS && grep -q "Internal use only — written to the audit log, never shown on the MAR" $CS'
ok "sheet: agency-timezone picker; default = scheduled time" 'grep -q "environment(\\\\.timeZone, Self.agencyZone)" $CS && grep -q "med.scheduledInstant" $CS'
ok "sheet: 409 → refresh (never retry); 403 → forbidden prose + refresh; unreadable 200 = committed" 'grep -q "case .conflict(let why)? = apiErr" $CS && grep -q "case .forbidden(let why)? = apiErr" $CS && grep -q "case .responseUnreadable? = apiErr" $CS'
ok "sheet: online-only guard" 'grep -q "Corrections are never queued" $CS && grep -q "guard online else" $CS'
echo "[4] build number"
ok "CFBundleVersion is 72" 'grep -A1 CFBundleVersion EVVMobile/Info.plist | grep -q "<string>72</string>"'
if [ "${1:-}" != "--no-build" ]; then
  echo "[5] simulator compile"
  if xcodebuild -project EVVMobile.xcodeproj -scheme EVVMobile -destination "platform=iOS Simulator,name=iPhone 17 Pro" -configuration Debug build CODE_SIGNING_ALLOWED=NO > /tmp/evv-emarc/build.log 2>&1; then
    pass=$((pass+1)); echo "  ✓ BUILD SUCCEEDED ($(grep -c 'warning:' /tmp/evv-emarc/build.log) warnings total)"
    w=$(grep "warning:" /tmp/evv-emarc/build.log | grep -E "MedicationsDueCard|CorrectAdministrationSheet" | wc -l | tr -d " ")
    ok "no warnings in the touched eMAR files" '[ "$w" = "0" ]'
  else fail=$((fail+1)); echo "  ✗ build failed"; grep -E "error:" /tmp/evv-emarc/build.log | head; fi
fi
echo; echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
