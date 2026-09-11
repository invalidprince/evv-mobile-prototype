import Foundation
import AVFoundation
import Speech

/// Live speech-to-text using on-device SFSpeechRecognizer + AVAudioEngine.
/// Transcribed text is surfaced via the `transcript` published property.
///
/// Build 68 — LONG RECORDINGS NO LONGER CUT OFF (Nick 2026-09-11: "if he
/// talks too long, the recording/transcription truncates"). iOS finalises a
/// single SFSpeechRecognitionTask after roughly a minute of audio (and can
/// finalise early on a long pause). The old implementation stopped recording
/// the moment the task reported `isFinal`, so a long answer ended mid-sentence
/// and the sheet auto-sent the truncated text. Now the recognizer CHAINS
/// segments: when a task finalises while recording is still wanted, its text
/// is committed to a running prefix and a NEW recognition request starts on
/// the SAME running audio engine. `transcript` is always committed + live
/// partial. Recording ends only on an explicit `stopRecording()` or when the
/// audio engine itself cannot continue.
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var permissionDenied = false

    /// Timestamp of the last transcript change (for silence detection).
    /// Updated every time the transcript text changes during recording.
    @Published var lastTranscriptChangeTime: Date = Date()

    private let recognizer: SFSpeechRecognizer? = {
        let r = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        r?.supportsOnDeviceRecognition = true
        return r
    }()
    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    /// Text from recognition segments that already finalised during THIS
    /// recording. The live segment's partial result is appended to it.
    private var committedText = ""
    /// Which segment is live — a stale task callback (from a cancelled/finished
    /// segment) must never overwrite the next segment's text.
    private var segmentId = 0
    /// Segments restarted by the chaining logic during this recording (debug).
    private(set) var segmentRestarts = 0
    /// Safety valve: a recognizer that keeps failing instantly must not spin.
    private var consecutiveInstantFailures = 0
    private var segmentStartedAt = Date()

    // MARK: - Permission check

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            permissionDenied = true
            return false
        }

        let audioStatus: Bool = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        guard audioStatus else {
            permissionDenied = true
            return false
        }

        permissionDenied = false
        return true
    }

    // MARK: - Start / Stop

    func startRecording() async {
        guard !isRecording else { return }
        guard await requestPermissions() else { return }

        // Reset
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        transcript = ""
        committedText = ""
        segmentRestarts = 0
        consecutiveInstantFailures = 0

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        // The tap forwards to WHATEVER request is current — that is what lets a
        // new segment pick up mid-stream without restarting the engine.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            return
        }

        isRecording = true
        startSegment()
    }

    /// Begin a recognition segment on the already-running audio engine.
    private func startSegment() {
        guard isRecording else { return }
        segmentId += 1
        let mySegment = segmentId
        segmentStartedAt = Date()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true  // offline capable; audio never leaves the phone
        request.taskHint = .dictation                // long-form speech, not a short search query
        recognitionRequest = request

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self, mySegment == self.segmentId, self.isRecording else { return }
                if let result = result {
                    let live = result.bestTranscription.formattedString
                    let merged = Self.join(self.committedText, live)
                    if merged != self.transcript {
                        self.lastTranscriptChangeTime = Date()
                        self.transcript = merged
                    }
                    if result.isFinal {
                        // Segment finalised (≈1-minute limit or a long pause) —
                        // bank its text and keep listening on a fresh request.
                        self.committedText = Self.join(self.committedText, live)
                        self.consecutiveInstantFailures = 0
                        self.restartSegment()
                        return
                    }
                }
                if error != nil {
                    // The segment died (recognizer error / cancelled by the
                    // system). Keep what we have and chain a new segment —
                    // unless it is failing instantly over and over, in which
                    // case the recognizer is genuinely unavailable: stop.
                    if Date().timeIntervalSince(self.segmentStartedAt) < 1.5 {
                        self.consecutiveInstantFailures += 1
                    } else {
                        self.consecutiveInstantFailures = 0
                    }
                    if self.consecutiveInstantFailures >= 3 || !self.audioEngine.isRunning {
                        self.stopRecording()
                    } else {
                        self.restartSegment()
                    }
                }
            }
        }
    }

    private func restartSegment() {
        guard isRecording else { return }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        segmentRestarts += 1
        startSegment()
    }

    /// Joins a committed prefix and a live segment with a single space.
    nonisolated static func join(_ committed: String, _ live: String) -> String {
        let a = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = live.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false          // set FIRST so a late task callback is ignored
        segmentId += 1               // invalidate any in-flight segment callback
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
