#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Build 68 — Voice AI fixes (Todoist 6hVRghJrxVHC5CmH, server v0.4.472).
#   1. Long recordings no longer cut off: SpeechRecognizer chains recognition
#      segments on one running audio engine instead of stopping on isFinal.
#   2. The interview's visit-question answers are applied to the form.
# Plus: the project still COMPILES (xcodebuild, simulator, no signing).
# Run from the repo root:  bash docs/voice-check/check.sh [--no-build]
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/../.."
SR=EVVMobile/Services/SpeechRecognizer.swift
VC=EVVMobile/Views/Documentation/VoiceConversationSheet.swift
DV=EVVMobile/Views/Documentation/DocumentationView.swift
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }

echo "[1] SpeechRecognizer — segment chaining"
ok "isFinal no longer stops recording (old: stopRecording on isFinal)" '! grep -q "error != nil || (result?.isFinal == true)" $SR'
ok "isFinal banks the segment text and restarts a segment"  'grep -q "if result.isFinal" $SR && grep -q "self.committedText = Self.join(self.committedText, live)" $SR && grep -q "self.restartSegment()" $SR'
ok "transcript = committed + live partial"                  'grep -q "let merged = Self.join(self.committedText, live)" $SR'
ok "restartSegment starts a NEW request without touching the audio engine" 'awk "/private func restartSegment/,/^    }/" $SR | grep -q "startSegment()" && ! awk "/private func restartSegment/,/^    }/" $SR | grep -q "audioEngine"'
ok "stale segment callbacks are ignored (segmentId guard)"  'grep -q "mySegment == self.segmentId" $SR'
ok "errors chain a new segment; only repeated instant failures stop" 'grep -q "consecutiveInstantFailures >= 3" $SR'
ok "stopRecording flips isRecording FIRST and invalidates the segment" 'awk "/func stopRecording/,/^    }/" $SR | head -4 | grep -q "isRecording = false" && awk "/func stopRecording/,/^    }/" $SR | grep -q "segmentId += 1"'
ok "on-device recognition still required (audio never leaves the phone)" 'grep -q "request.requiresOnDeviceRecognition = true" $SR'
ok "dictation task hint set"                                'grep -q "request.taskHint = .dictation" $SR'
ok "join() trims and single-spaces"                         'grep -q "return a + \" \" + b" $SR'

echo "[2] VoiceConversationSheet"
ok "silence auto-send threshold 3.0 s"                     'grep -q "silenceThreshold: TimeInterval = 3.0" $VC'
ok "DocConversationResponse decodes visitQuestions"        'grep -q "let visitQuestions: \[DocConversationQuestionAnswer\]?" $VC'
ok "DocConversationQuestionAnswer {questionId, answer}"    'grep -q "struct DocConversationQuestionAnswer: Decodable" $VC && awk "/struct DocConversationQuestionAnswer/,/^}/" $VC | grep -q "let questionId: Int?" && awk "/struct DocConversationQuestionAnswer/,/^}/" $VC | grep -q "let answer: String?"'
ok "auto-send-on-recognizer-stop fallback kept"            'grep -q "onChange(of: speech.isRecording)" $VC'

echo "[3] DocumentationView — applies interview answers"
ok "applyVoiceConversationResult loops response.visitQuestions" 'awk "/private func applyVoiceConversationResult/,/^    }/" $DV | grep -q "for qa in response.visitQuestions ?? \[\]"'
ok "only ids present in serverQuestions are applied"       'awk "/private func applyVoiceConversationResult/,/^    }/" $DV | grep -q "serverQuestions.contains(where: { \$0.id == qid })"'
ok "legacy transport bool kept in sync"                    'awk "/private func applyVoiceConversationResult/,/^    }/" $DV | grep -q "note.transportReviewedGoals = (answer == \"Yes\")"'
ok "unanswered questions never cleared (no removeValue/nil assignment in the loop)" '! awk "/for qa in response.visitQuestions/,/^        }/" $DV | grep -q "= nil"'

echo "[4] build number"
ok "Info.plist CFBundleVersion = 68"                        'grep -A1 CFBundleVersion EVVMobile/Info.plist | grep -q "<string>68</string>"'

if [ "${1:-}" != "--no-build" ]; then
  echo "[5] compile (xcodebuild, simulator, no signing) — takes a few minutes"
  rm -rf /tmp/evv-dd-voice
  if xcodebuild build -project EVVMobile.xcodeproj -scheme EVVMobile -destination 'generic/platform=iOS Simulator' \
       -derivedDataPath /tmp/evv-dd-voice CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | grep -q " error:"; then
    fail=$((fail+1)); echo "  ✗ compile"
  else
    ok "compile produced EVVMobile.app" '[ -x /tmp/evv-dd-voice/Build/Products/Debug-iphonesimulator/EVVMobile.app/EVVMobile ]'
  fi
fi
echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
