#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Build 75 — keyboard dismissal, app-wide (Todoist 6hWwwmxrqchxrf7H).
# Nick, #evv 2026-09-17: "Spec this too for iOS to have a way to bring down
# the keyboard (hide it)" — filed against the Visit Note form.
#
#   [0] the REAL isTextInputOrUIControl vs a stripped control (logic_test.swift)
#   [1] coverage: EVERY file with a text input applies .keyboardDismissable()
#   [2] the three affordances exist and are spelled correctly
#   [3] iOS 15 safety: no unguarded iOS 16 API
#   [4] regression guards: AI Review / focus / submitted-payload untouched
#   [5] project registration + build number
#   [6] simulator compile
#
# Run from the repo root:  bash docs/keyboard-dismiss-check/check.sh [--no-build]
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/../.."
KD=EVVMobile/Theme/KeyboardDismiss.swift
DV=EVVMobile/Views/Documentation/DocumentationView.swift
PBX=EVVMobile.xcodeproj/project.pbxproj
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }

echo "[0] tap-decline logic — REAL function vs stripped control"
mkdir -p /tmp/evv-kbd
# Extract ONLY the UIKit half of KeyboardDismiss.swift — the resign helper and
# the coordinator whose tap-decline logic is what this test decides. The
# SwiftUI ViewModifier is a layout concern proven by the simulator build in
# [6], not here; splicing it in would need a full SwiftUI host. Extracted by
# real line ranges from the shipped file (never a copy), so the test cannot
# drift from what the app compiles.
{
  echo "import Foundation"
  echo "import UIKit"
  awk '/^enum KeyboardDismisser \{/,/^\}$/' "$KD"
  awk '/^final class KeyboardTapDismissCoordinator/,/^\}$/' "$KD"
  grep -v "^import Foundation" docs/keyboard-dismiss-check/logic_test.swift | grep -v "^import UIKit"
} > /tmp/evv-kbd/main.swift
# Guard the extraction: if either awk range came back empty the test would
# "pass" by compiling nothing real.
ok "extracted the REAL resign helper (not a copy)" \
   'grep -q "static func dismiss()" /tmp/evv-kbd/main.swift'
ok "extracted the REAL coordinator (not a copy)" \
   'grep -q "func gestureRecognizer" /tmp/evv-kbd/main.swift && grep -q "isTextInputOrUIControl" /tmp/evv-kbd/main.swift'
# Build for the HOST arch so the assertions can actually EXECUTE inside a
# booted simulator — UIKit view trees need a real UIKit, and a test that only
# compiles proves the types line up, not that the logic is right.
ARCH=$(uname -m)
if xcrun -sdk iphonesimulator swiftc -O -target "${ARCH}-apple-ios15.0-simulator" \
      -o /tmp/evv-kbd/run /tmp/evv-kbd/main.swift 2>/tmp/evv-kbd/compile.log; then
  pass=$((pass+1)); echo "  ✓ compiled against the real coordinator"
  SIMID=$(xcrun simctl list devices booted -j 2>/dev/null \
            | python3 -c "import sys,json;d=json.load(sys.stdin)['devices'];print(next((x['udid'] for v in d.values() for x in v if x.get('state')=='Booted'),''))" 2>/dev/null)
  if [ -z "$SIMID" ]; then
    SIMID=$(xcrun simctl list devices available -j \
            | python3 -c "import sys,json;d=json.load(sys.stdin)['devices'];print(next((x['udid'] for v in d.values() for x in v if 'iPhone' in x['name']),''))")
    [ -n "$SIMID" ] && xcrun simctl boot "$SIMID" 2>/dev/null; sleep 5
  fi
  if [ -n "$SIMID" ] && xcrun simctl spawn "$SIMID" /tmp/evv-kbd/run > /tmp/evv-kbd/run.log 2>&1; then
    sed "s/^/  /" /tmp/evv-kbd/run.log
    pass=$((pass+1)); echo "  ✓ EXECUTED in simulator: $(tail -1 /tmp/evv-kbd/run.log)"
  else
    fail=$((fail+1)); echo "  ✗ logic assertions FAILED in simulator"; tail -25 /tmp/evv-kbd/run.log
  fi
else
  fail=$((fail+1)); echo "  ✗ logic_test.swift failed to compile"; tail -20 /tmp/evv-kbd/compile.log
fi

echo "[1] coverage — every text-input screen applies the modifier"
INPUT_FILES=$(grep -rl "TextField(\|TextEditor(\|SecureField(\|DocTextEditor(\|MultilineTextBox(" EVVMobile/Views/ | sort)
missing=""
for f in $INPUT_FILES; do
  # OutcomeEntryView is a child component of DocumentationView's ScrollView and
  # inherits the screen-root modifier — that IS the container-level design the
  # spec asked for ("one modifier applied at the container/root level per
  # screen", not per-field copy-paste).
  case "$f" in *OutcomeEntryView.swift) continue;; esac
  grep -q "keyboardDismissable" "$f" || missing="$missing $f"
done
ok "no text-input screen left uncovered (missing:${missing:-none})" '[ -z "$missing" ]'
ok "OutcomeEntryView deliberately inherits from DocumentationView (single call site app-wide)" \
   '[ "$(grep -rho "OutcomeEntryView(" EVVMobile/Views/ | wc -l | tr -d " ")" = "1" ]'
ok "the Visit Note form — the screen Nick filed this against — is covered" \
   'grep -q "keyboardDismissable" '"$DV"
ok "at least 15 screen roots covered" \
   '[ $(grep -rh "^\s*\.keyboardDismissable" EVVMobile/Views/ | wc -l) -ge 15 ]'

echo "[2] the three affordances"
ok "1. Done bar via ToolbarItemGroup(placement: .keyboard)" \
   'grep -q "ToolbarItemGroup(placement: .keyboard)" '"$KD"
ok "   Done button resigns focus" \
   'grep -A2 "Button(\"Done\")" '"$KD"' | grep -q "KeyboardDismisser.dismiss()"'
ok "   Done button carries an accessibility identifier for UI tests" \
   'grep -q "accessibilityIdentifier(\"keyboard-done\")" '"$KD"
ok "2. drag via scrollDismissesKeyboard(.interactively)" \
   'grep -q "scrollDismissesKeyboard(.interactively)" '"$KD"
ok "   iOS 15 fallback uses the UIScrollView appearance proxy" \
   'grep -q "UIScrollView.appearance().keyboardDismissMode = .interactive" '"$KD"
ok "3. tap-outside via a window UITapGestureRecognizer" \
   'grep -q "UITapGestureRecognizer(target: self" '"$KD"
ok "   recognizer does NOT consume touches (buttons still fire)" \
   'grep -q "tap.cancelsTouchesInView = false" '"$KD"
ok "   recognizer does not delay touches" \
   'grep -q "tap.delaysTouchesBegan = false" '"$KD"' && grep -q "tap.delaysTouchesEnded = false" '"$KD"
ok "   recognizes simultaneously with SwiftUI's own gestures" \
   'grep -q "shouldRecognizeSimultaneouslyWith" '"$KD"
ok "   inert when no keyboard is up (keyboardVisible gate)" \
   'grep -q "guard keyboardVisible else { return }" '"$KD"
ok "   install is idempotent per window (NSHashTable weakObjects)" \
   'grep -q "NSHashTable<UIWindow>.weakObjects()" '"$KD"' && grep -q "!attached.contains(window)" '"$KD"
ok "   resign path is the UIKit sendAction (works for TextField AND TextEditor)" \
   'grep -q "#selector(UIResponder.resignFirstResponder)" '"$KD"

echo "[3] iOS 15 safety — deployment target is 15.0"
ok "deployment target still 15.0 (unchanged by this card)" \
   '[ $(grep -c "IPHONEOS_DEPLOYMENT_TARGET = 15.0" '"$PBX"') -ge 2 ]'
ok "scrollDismissesKeyboard is guarded by #available(iOS 16.0, *)" \
   'grep -B3 "scrollDismissesKeyboard" '"$KD"' | grep -q "#available(iOS 16.0, \*)"'
ok "no unguarded two-argument onChange (the iOS 17 form) added" \
   '! grep -q "onChange(of: .*) { _, _ in" '"$KD"

echo "[4] regression guards — pure input-UX task, nothing submitted changes"
ok "AI Review button untouched in this card's diff" \
   'git diff --unified=0 -- '"$DV"' | grep "^[-+]" | grep -v "^[-+][-+]" | grep -qv "AIReview" || true; ! git diff -- '"$DV"' | grep "^-" | grep -q "AIReviewButton"'
ok "no TextField/TextEditor binding was rewritten" \
   '! git diff -- EVVMobile/Views/ | grep "^-" | grep -qE "TextField\(|TextEditor\(|SecureField\("'
ok "the one existing @FocusState (CountRow) is untouched" \
   '! git diff -- EVVMobile/Views/Documentation/OutcomeEntryView.swift | grep -q "FocusState"'
# Build 92: narrowed from all of EVVMobile/Services/ to the files this guard
# actually protects. The original wildcard asserted "this commit touched no
# service at all", which is a property of the build-75 commit, not a durable
# invariant — it trips on ANY later commit that touches an unrelated service
# (build 92's DiagnosticLogger disk persistence was the first). The submit /
# encode path is APIClient + LocalCache; those are still guarded strictly.
ok "no submit/encode path modified" \
   '! git diff -- EVVMobile/Services/APIClient.swift EVVMobile/Services/LocalCache.swift | grep -q "^[-+][^-+]"'
ok "signature pad opts out of interactive drag (it owns a drag gesture)" \
   'grep -q "keyboardDismissable(interactiveDrag: false)" EVVMobile/Views/Punch/SignaturePadView.swift'

echo "[5] project registration + build number"
ok "KeyboardDismiss.swift has a PBXFileReference" \
   'grep -q "KeyboardDismiss.swift \*/ = {isa = PBXFileReference" '"$PBX"
ok "KeyboardDismiss.swift has a PBXBuildFile" \
   'grep -q "KeyboardDismiss.swift in Sources \*/ = {isa = PBXBuildFile" '"$PBX"
ok "KeyboardDismiss.swift is in the Theme group" \
   'awk "/\/\* Theme \*\/ = \{/,/path = Theme;/" '"$PBX"' | grep -q KeyboardDismiss.swift'
ok "KeyboardDismiss.swift is in the Sources build phase" \
   'awk "/isa = PBXSourcesBuildPhase/,/^\t\t\};/" '"$PBX"' | grep -q "KeyboardDismiss.swift in Sources"'
ok "build number bumped to 75 (CFBundleVersion in Info.plist — where this app keeps it)" \
   'grep -A1 "<key>CFBundleVersion</key>" EVVMobile/Info.plist | grep -q "<string>75</string>"'

if [ "${1:-}" != "--no-build" ]; then
  echo "[6] simulator compile"
  SIM=$(xcrun simctl list devices available | grep -oE "iPhone 1[5-7][^(]*" | head -1 | sed 's/ *$//')
  DEST="platform=iOS Simulator,name=${SIM:-iPhone 16}"
  if xcodebuild -project EVVMobile.xcodeproj -scheme EVVMobile \
       -destination "$DEST" -derivedDataPath build/dd-kbd \
       build > /tmp/evv-kbd/build.log 2>&1; then
    pass=$((pass+1)); echo "  ✓ xcodebuild succeeded ($DEST)"
    # 🩸 A GREEN BUILD DOES NOT PROVE THE FILE IS IN THE TARGET. A .swift that
    # was never added to the Sources build phase compiles nothing and the build
    # still succeeds — then every .keyboardDismissable() call site would be a
    # hard error, but a stale/partial pbxproj edit is exactly the failure mode
    # this app has hit before (PunchReminderCenter was registered by hand).
    # So assert the object file was produced AND linked, and that the real
    # symbols are in the shipped code.
    ok "KeyboardDismiss.o was produced" \
       'find build/dd-kbd -name "KeyboardDismiss.o" | grep -q .'
    ok "KeyboardDismiss.o is in the link file list (actually linked, not orphaned)" \
       'grep -rq "KeyboardDismiss.o" build/dd-kbd/Build/Intermediates.noindex/EVVMobile.build/*/EVVMobile.build/Objects-normal/*/EVVMobile.LinkFileList'
    # NB: EVVMobile.app/EVVMobile is only the debug-dylib launcher stub and is
    # fully stripped (0 app symbols for ANY type, DocumentationView included) —
    # the app code lives in EVVMobile.debug.dylib. Looking in the wrong file
    # here would "prove" the feature was missing.
    DY=$(find build/dd-kbd/Build/Products -name "EVVMobile.debug.dylib" | head -1)
    if [ -n "$DY" ]; then
      ok "coordinator symbols present in the shipped code" \
         '[ $(nm "'"$DY"'" | grep -c KeyboardTapDismissCoordinator) -gt 0 ]'
      ok "the KeyboardDismissable modifier is present in the shipped code" \
         '[ $(nm "'"$DY"'" | grep -c KeyboardDismissable) -gt 0 ]'
    fi
  else
    fail=$((fail+1)); echo "  ✗ xcodebuild FAILED"; grep -E "error:" /tmp/evv-kbd/build.log | head -20
  fi
else
  echo "[6] simulator compile — skipped (--no-build)"
fi

echo ""
echo "keyboard-dismiss check: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
