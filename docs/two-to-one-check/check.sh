#!/bin/bash
# build 86 / server v0.4.614 — "2:1 — SECOND STAFF REQUIRED" badge.
# Offline pins on the shipped files (never copies) + optional compile.
#   bash docs/two-to-one-check/check.sh            # pins + xcodebuild
#   bash docs/two-to-one-check/check.sh --no-build # pins only
set -u
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok() { local label=$1; shift; if eval "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $label"; else fail=$((fail+1)); echo "  ✗ $label"; fi; }

echo "[1] payload contract — additive optional keys (older servers omit them)"
ok "ServerShift decodes needsSecondStaff: Bool?"  "grep -q 'let needsSecondStaff: Bool?' EVVMobile/Services/APIClient.swift"
ok "ServerShift decodes requiredStaff: Int?"       "grep -q 'let requiredStaff: Int?' EVVMobile/Services/APIClient.swift"
ok "Visit carries needsSecondStaff: Bool? (nil = older server)" "grep -q 'var needsSecondStaff: Bool?' EVVMobile/Models/Models.swift"
ok "AppState maps s.needsSecondStaff onto the visit" "grep -q 'visit.needsSecondStaff = s.needsSecondStaff' EVVMobile/State/AppState.swift"

echo "[2] ONE rule for the badge: server answer first, else ratio 2:1 + no partner"
ok "showsSecondStaffRequired prefers the server value" "grep -q 'if let n = needsSecondStaff { return n }' EVVMobile/Models/Models.swift"
ok "…and falls back to ratio == \"2:1\" && partners.isEmpty" "grep -q 'return ratio == \"2:1\" && partners.isEmpty && teamStaff == nil' EVVMobile/Models/Models.swift"

echo "[3] every 2:1 badge site shows the required-partner state (warning colour) and keeps the plain 2:1 badge otherwise"
for f in EVVMobile/Views/Schedule/ShiftRow.swift EVVMobile/Views/Today/UpNextCard.swift EVVMobile/Views/Today/ActiveVisitCard.swift; do
  ok "$(basename "$f"): SECOND STAFF REQUIRED badge" "grep -q '2:1 — SECOND STAFF REQUIRED' '$f'"
  ok "$(basename "$f"): warning colour" "grep -q 'StatusBadge(text: \"2:1 — SECOND STAFF REQUIRED\", color: Theme.warning)' '$f'"
  ok "$(basename "$f"): plain 2:1 badge retained for a fully staffed shift" "grep -q 'else if visit.ratio == \"2:1\"' '$f'"
done
ok "ShiftDetailView: explanatory line when no partner is assigned" "grep -q 'a second staff member is required and has not been assigned yet' EVVMobile/Views/Schedule/ShiftDetailView.swift"
ok "ShiftDetailView: header badge turns warning" "grep -q 'if visit.showsSecondStaffRequired' EVVMobile/Views/Schedule/ShiftDetailView.swift"

echo "[4] no new network calls / no local enforcement — the server is the control"
ok "no new endpoint was added to APIClient" "! grep -q 'staffing\|second-staff\|secondStaff' EVVMobile/Services/APIClient.swift | grep -v needsSecondStaff"
ok "clock-in path untouched (no client-side refusal on needsSecondStaff)" "! grep -rq 'needsSecondStaff' EVVMobile/Services/OfflineQueue.swift EVVMobile/Views/Today/ClockIn*.swift 2>/dev/null"

echo "[5] build number"
ok "Info.plist CFBundleVersion is 86" "grep -A1 CFBundleVersion EVVMobile/Info.plist | grep -q '<string>86</string>'"

if [ "${1:-}" != "--no-build" ]; then
  echo "[6] compile (xcodebuild, simulator, no signing) — takes a few minutes"
  if xcodebuild build -project EVVMobile.xcodeproj -scheme EVVMobile -destination 'generic/platform=iOS Simulator' \
       -derivedDataPath /tmp/evv-dd-twotoone CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | grep -q " error:"; then
    fail=$((fail+1)); echo "  ✗ compile"
  else
    ok "compile produced EVVMobile.app" '[ -x /tmp/evv-dd-twotoone/Build/Products/Debug-iphonesimulator/EVVMobile.app/EVVMobile ]'
  fi
fi

echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
