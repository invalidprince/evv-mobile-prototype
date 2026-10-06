#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Build 112 — unlisted App Store readiness (Todoist 6hfjGWqR5JMJPwrq).
#   [1] Info.plist: Medicaid-EVV location purpose string, no unused Face ID
#       string, review-demo keys wired, build number
#   [2] both xcconfigs carry the review demo credentials
#   [3] login: demo check runs BEFORE any network call; no hard-coded version
#   [4] simulator UI run: demo login -> banner -> all 5 tabs, screenshots in
#       /tmp/review-demo (skip with --no-ui)
# Run from the repo root:  bash docs/review-demo-check/check.sh [--no-ui]
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/../.."
P=EVVMobile/Info.plist; L=EVVMobile/Views/LoginView.swift
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }
echo "[1] Info.plist"
ok "location string names Medicaid EVV" 'grep -q "as required by Medicaid EVV rules" $P'
ok "no unused Face ID string (no LocalAuthentication in code)" '! grep -q NSFaceIDUsageDescription $P && ! grep -rq LocalAuthentication EVVMobile'
ok "review demo keys wired to xcconfig" 'grep -q "\$(EVV_REVIEW_DEMO_EMAIL)" $P && grep -q "\$(EVV_REVIEW_DEMO_PASSWORD)" $P'
ok "build number >= 112" '[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" $P)" -ge 112 ]'
echo "[2] xcconfigs"
for f in Live Staging; do ok "$f has demo email+password" 'grep -q "^EVV_REVIEW_DEMO_EMAIL = ." EVVMobile/Config/$f.xcconfig && grep -q "^EVV_REVIEW_DEMO_PASSWORD = ." EVVMobile/Config/$f.xcconfig'; done
echo "[3] login"
ok "demo check precedes loginWithServer" '[ $(grep -n isReviewDemoLogin $L | head -1 | cut -d: -f1) -lt $(grep -n "loginWithServer" $L | head -1 | cut -d: -f1) ]'
ok "no hard-coded v0.3.1" '! grep -q "v0.3.1" $L'
if [ "${1:-}" != "--no-ui" ]; then
  echo "[4] simulator UI run"
  T=EVVMobileUITests/MyDocumentsShotTests.swift
  cp $T /tmp/review-demo-orig.swift && trap 'cp /tmp/review-demo-orig.swift "$T"' EXIT INT TERM
  cp docs/review-demo-check/review_demo_ui_test.swift.txt $T
  rm -rf /tmp/review-demo /tmp/review-demo.xcresult
  SIMID=$(xcrun simctl list devices available -j | python3 -c "import sys,json;d=json.load(sys.stdin)['devices'];print(next((x['udid'] for v in d.values() for x in v if 'iPhone' in x['name'] and x.get('state')=='Booted'), next((x['udid'] for v in d.values() for x in v if 'iPhone' in x['name']),'')))")
  xcrun simctl uninstall "$SIMID" net.fbhi.evvmobile >/dev/null 2>&1
  xcodebuild test -project EVVMobile.xcodeproj -scheme EVVMobile -destination "id=$SIMID" \
    -only-testing:EVVMobileUITests/MyDocumentsShotTests/testReviewDemoLogin \
    -resultBundlePath /tmp/review-demo.xcresult > /tmp/review-demo-xcodebuild.log 2>&1
  rc=$?
  cp /tmp/review-demo-orig.swift $T
  ok "UI test passed (log /tmp/review-demo-xcodebuild.log)" '[ $rc -eq 0 ]'
  ok "6 screenshots written" '[ $(ls /tmp/review-demo/*.png 2>/dev/null | wc -l) -ge 6 ]'
fi
echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
