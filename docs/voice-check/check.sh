#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Build 68 — Voice AI fixes (Todoist 6hVRghJrxVHC5CmH, server v0.4.472).
#   1. Long recordings no longer cut off: SpeechRecognizer chains recognition
#      segments on one running audio engine instead of stopping on isFinal.
#   2. The interview's visit-question answers are applied to the form.
# Build 69 — words no longer vanish on a PAUSE (Nick 2026-09-14): the
#   accumulation moved into the pure TranscriptAccumulator, which banks text
#   on utterance boundaries (speechRecognitionMetadata), silent restarts, task
#   errors and isFinal, and strips duplicated segment text. Its REAL code is
#   extracted and executed by accumulator_test.swift (section [0]).
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

echo "[0] TranscriptAccumulator — the REAL struct, extracted and executed (build 69)"
mkdir -p /tmp/evv-acc
{ grep "^let speechRestartGap" $SR; echo "import Foundation"; awk '/^\/\/ BEGIN TranscriptAccumulator/,/^\/\/ END TranscriptAccumulator/' $SR; grep -v "^import Foundation" docs/voice-check/accumulator_test.swift; } > /tmp/evv-acc/main.swift
if swiftc -O -o /tmp/evv-acc/run /tmp/evv-acc/main.swift 2>/tmp/evv-acc/compile.log && /tmp/evv-acc/run > /tmp/evv-acc/out.log; then
  pass=$((pass+1)); echo "  ✓ accumulator_test.swift: $(tail -1 /tmp/evv-acc/out.log)"
else
  fail=$((fail+1)); echo "  ✗ accumulator_test.swift"; cat /tmp/evv-acc/compile.log /tmp/evv-acc/out.log | tail -20
fi

echo "[1] SpeechRecognizer — segment chaining + build 69 banking"
ok "isFinal no longer stops recording (old: stopRecording on isFinal)" '! grep -q "error != nil || (result?.isFinal == true)" $SR'
ok "isFinal banks (absorb bank:true) and restarts a segment" 'grep -q "if result.isFinal" $SR && grep -q "self.absorb(reported, bank: utteranceDone || result.isFinal, gap: gap)" $SR && grep -q "self.restartSegment()" $SR'
ok "utterance boundary = speechRecognitionMetadata != nil"   'grep -q "let utteranceDone = result.speechRecognitionMetadata != nil" $SR'
ok "error path banks the live partial before chaining"        'awk "/if error != nil/,/restartSegment/" $SR | grep -q "self.bankLive()"'
ok "stopRecording banks the last partial"                     'awk "/func stopRecording/,/^    }/" $SR | grep -q "bankLive()"'
ok "published transcript comes from the accumulator"          'grep -q "let merged = acc.transcript" $SR'
ok "gap since last result is measured and passed"             'grep -q "let gap = Date().timeIntervalSince(self.lastResultAt)" $SR'
ok "restartSegment starts a NEW request without touching the audio engine" 'awk "/private func restartSegment/,/^    }/" $SR | grep -q "startSegment()" && ! awk "/private func restartSegment/,/^    }/" $SR | grep -q "audioEngine"'
ok "stale segment callbacks are ignored (segmentId guard)"  'grep -q "mySegment == self.segmentId" $SR'
ok "errors chain a new segment; only repeated instant failures stop" 'grep -q "consecutiveInstantFailures >= 3" $SR'
ok "stopRecording flips isRecording BEFORE tearing down the task and invalidates the segment" 'awk "/func stopRecording/,/^    }/" $SR | grep -n "isRecording = false\|audioEngine.stop()" | head -2 | tr "\n" " " | grep -q "isRecording = false.*audioEngine.stop()" && awk "/func stopRecording/,/^    }/" $SR | grep -q "segmentId += 1"'
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
ok "Info.plist CFBundleVersion = 69"                        'grep -A1 CFBundleVersion EVVMobile/Info.plist | grep -q "<string>69</string>"'

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
