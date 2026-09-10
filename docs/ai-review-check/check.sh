#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Build 66 — ✨ AI Review: source-level assertions for the two Nick asks
# (Todoist 6hV9qf6JPHj5QV5H, server v0.4.458/459).
#   1. The "AI draft — tap to review" badge + its submit gate are GONE.
#   2. Every DocTextEditor call site renders ✨ AI Review instead of the 🎤 mic,
#      wired to POST /api/visits/:id/ai-review-text with Undo.
# Plus: the project still COMPILES (xcodebuild, simulator, no signing) — the
# real check, because a pbxproj/registration mistake is invisible to grep.
#
# Run from the repo root:  bash docs/ai-review-check/check.sh [--no-build]
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/../.."
DV=EVVMobile/Views/Documentation/DocumentationView.swift
OE=EVVMobile/Views/Documentation/OutcomeEntryView.swift
AC=EVVMobile/Services/APIClient.swift
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }
cnt() { grep -c -- "$1" "$2" 2>/dev/null || true; }

echo "[1] tap-to-review gate removed"
ok "no 'tap to review' copy anywhere in the target"        '[ "$(grep -rl "tap to review" EVVMobile | wc -l | tr -d " ")" = 0 ]'
ok "no sectionsViewed state (the gate's backing set)"       '[ "$(grep -c "sectionsViewed" $DV)" = 1 ]'   # only the explanatory comment
ok "noteComplete no longer requires viewing drafted sections" '! grep -q "allViewed" $DV'
ok "no 'Review all AI-drafted sections' submit hint"        '! grep -q "Review all AI-drafted sections" $DV'
ok "RED 'Not mentioned — please complete' chip KEPT"        'grep -q "Not mentioned — please complete" $DV'
ok "no per-outcome onTapGesture marking viewed"            '! grep -q "Mark section as viewed" $DV'

echo "[2] mic → AI Review"
ok "DictationButton has ZERO call sites (file kept on purpose)" '[ "$(grep -rn "DictationButton(" EVVMobile --include=*.swift | grep -v Documentation/DictationButton.swift | wc -l | tr -d " ")" = 0 ]'
ok "DictationButton.swift + SpeechRecognizer.swift still present" '[ -f EVVMobile/Views/Documentation/DictationButton.swift ] && [ -f EVVMobile/Services/SpeechRecognizer.swift ]'
ok "Info.plist mic/speech usage strings untouched"          'grep -q NSMicrophoneUsageDescription EVVMobile/Info.plist && grep -q NSSpeechRecognitionUsageDescription EVVMobile/Info.plist'
ok "DocTextEditor renders AIReviewButton behind showAIReview + context.available" 'grep -q "if showAIReview && aiReview.available" $DV'
ok "AIReviewButton posts through APIClient.aiReviewText"    'grep -q "APIClient.shared.aiReviewText(" $DV && grep -q "/ai-review-text" $AC'
ok "Undo restores the original text"                       'grep -q "text = o" $DV && grep -q "Button(\"Undo\")" $DV'
ok "empty field / offline → disabled ('Needs a connection')" 'grep -q "Needs a connection" $DV && grep -q "isEmpty" $DV'
ok "typing after a rewrite clears the Undo target"         'grep -q "if let r = rewrittenText, newValue != r" $DV'
ok "unchanged → 'Already reads well'"                      'grep -q "Already reads well" $DV'
ok "stale-field guard (field changed while waiting)"       'grep -q "guard text == input else" $DV'
ok "outcome narrative call site passes outcome_narrative + local id" 'grep -q "fieldKind: \"outcome_narrative\"" $OE && grep -q "outcomeLocalId: outcome.id" $OE'
ok "question call site passes question + id"               'grep -q "fieldKind: \"question\"" $DV && grep -q "questionId: question.id" $DV'
ok "comments editor uses the default (comment) kind"       'grep -q "DocTextEditor(text: \$note.additionalComments" $DV'
ok "template decodes noteRewriteEnabled (optional → older servers OFF)" 'grep -q "noteRewriteEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .noteRewriteEnabled)) ?? nil" $AC'
ok "context set once on the form root via environment"    'grep -q "\.environment(\\\\.aiReviewContext, aiReviewContext)" $DV'
ok "no new file → no pbxproj registration needed (AIReviewButton lives in DocumentationView.swift)" 'grep -q "struct AIReviewButton: View" $DV && ! grep -q "AIReviewButton.swift" EVVMobile.xcodeproj/project.pbxproj'
ok "build number bumped to 66"                              'grep -A1 CFBundleVersion EVVMobile/Info.plist | grep -q "<string>66</string>"'

if [ "${1:-}" != "--no-build" ]; then
  echo "[3] compile (xcodebuild, simulator, no signing) — takes a few minutes"
  if xcodebuild build -project EVVMobile.xcodeproj -scheme EVVMobile -destination 'generic/platform=iOS Simulator' \
       -derivedDataPath /tmp/evv-dd-aireview CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | grep -q " error:"; then
    fail=$((fail+1)); echo "  ✗ compile"
  else
    ok "compile produced EVVMobile.app" '[ -x /tmp/evv-dd-aireview/Build/Products/Debug-iphonesimulator/EVVMobile.app/EVVMobile ]'
  fi
fi

echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
