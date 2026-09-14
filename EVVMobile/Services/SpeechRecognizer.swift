import Foundation
import AVFoundation
import Speech

/// A much-shorter partial arriving after this much silence is a fresh
/// utterance, not a revision of the previous one (build 69).
let speechRestartGap: TimeInterval = 0.7

// MARK: - TranscriptAccumulator (pure, platform-independent, testable)
// BEGIN TranscriptAccumulator
/// Folds SFSpeechRecognizer results into one running transcript that can
/// only grow or revise the utterance currently being spoken — never lose
/// earlier words. Pure value type with no Speech/AVFoundation dependency so
/// `docs/voice-check/accumulator_test.swift` can exercise the REAL code.
///
/// Build 69 — WORDS NO LONGER VANISH ON A PAUSE (Nick 2026-09-14: "it takes
/// a lot of my words… if I talk too long or pause it REMOVES what I had
/// already said"). Build 68 only banked text on `isFinal`. But on-device
/// recognition (iOS 17+) ends an UTTERANCE on a pause WITHOUT `isFinal`: it
/// emits a result carrying `speechRecognitionMetadata` and the next partial's
/// `formattedString` contains ONLY the new speech. Nothing banked the finished
/// utterance, so the fresh partial REPLACED the accumulated text. The same
/// loss happened when a task died with an error (no `isFinal`) — its last
/// partial was dropped before the next segment started.
/// Now the current utterance's partial (`liveText`) is tracked separately and
/// BANKED into `committedText` on every boundary iOS can produce:
///   (a) a result with `speechRecognitionMetadata` (utterance complete),
///   (b) a partial that is clearly a RESTART rather than a revision,
///   (c) a task error,
///   (d) `isFinal` / a new segment / stop.
/// Anything a later result repeats from text already banked in this segment
/// is stripped (older iOS keeps reporting the whole segment), so nothing is
/// printed twice.
struct TranscriptAccumulator {
    /// Everything banked so far during THIS recording: finished segments AND
    /// finished utterances of the current segment. Only ever grows.
    private(set) var committedText = ""
    /// Partial text of the utterance currently being spoken (not yet banked).
    private(set) var liveText = ""
    /// Text banked within the CURRENT segment (utterance boundaries). Used to
    /// strip duplication when the recognizer keeps reporting the whole segment.
    private(set) var segmentBanked = ""
    /// Utterances banked during this recording (debug).
    private(set) var banks = 0

    /// The text to publish: committed + live partial.
    var transcript: String { Self.join(committedText, liveText) }

    mutating func reset() {
        committedText = ""; liveText = ""; segmentBanked = ""; banks = 0
    }

    /// A new recognition task started on the same recording.
    mutating func beginSegment() {
        bankLive()
        segmentBanked = ""
        liveText = ""
    }

    /// Folds one recognizer result in.
    /// - `reported` is the recognizer's `formattedString` for this result.
    /// - `bank` is true when this result closes an utterance/segment
    ///   (`speechRecognitionMetadata != nil` or `isFinal`), so its text must
    ///   be committed rather than left as a revisable partial.
    /// - `gap` is the time since the previous result from this task.
    mutating func absorb(_ reported: String, bank: Bool, gap: TimeInterval) {
        var text = reported.trimmingCharacters(in: .whitespacesAndNewlines)
        // Older iOS keeps reporting the WHOLE segment after an utterance
        // boundary. Strip what this segment already banked so it is never
        // printed twice. (iOS 17+ starts the next partial fresh, so this is
        // a no-op there.)
        if !segmentBanked.isEmpty, let rest = Self.remainder(after: segmentBanked, in: text) {
            text = rest
        }
        if text.isEmpty {
            // Nothing new — a boundary result may legitimately repeat only
            // banked text. Still honour the boundary for whatever is live.
            if bank { bankLive() }
            return
        }
        // A partial that does not revise the current utterance but starts
        // over is a RESTART: the recognizer finished the previous utterance
        // silently. Keep the previous words — that is the whole bug.
        if !liveText.isEmpty && Self.isRestart(previous: liveText, next: text, gap: gap) {
            bankLive()
        }
        liveText = text
        if bank { bankLive() }
    }

    /// Commits the current utterance partial and clears it.
    mutating func bankLive() {
        let live = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !live.isEmpty else { return }
        committedText = Self.join(committedText, live)
        segmentBanked = Self.join(segmentBanked, live)
        banks += 1
        liveText = ""
    }

    /// Joins a committed prefix and a live segment with a single space.
    static func join(_ committed: String, _ live: String) -> String {
        let a = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = live.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }

    /// Lower-cased alphanumeric word tokens — punctuation and casing differ
    /// between a partial and its finalised form, so comparisons use these.
    static func tokens(_ s: String) -> [String] {
        s.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// If `text` starts with the words of `banked`, returns the words of `text`
    /// that follow (joined by single spaces, may be empty). Otherwise nil.
    static func remainder(after banked: String, in text: String) -> String? {
        let b = tokens(banked)
        guard !b.isEmpty else { return text }
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let t = words.map { tokens($0).joined() }.filter { !$0.isEmpty }
        // t[i] is the token form of words[i] only when every word yields one
        // token; fall back to a flat token comparison when it does not.
        if t.count == words.count {
            guard t.count >= b.count, Array(t[0..<b.count]) == b else { return nil }
            return words[b.count...].joined(separator: " ")
        }
        let flat = tokens(text)
        guard flat.count >= b.count, Array(flat[0..<b.count]) == b else { return nil }
        return flat[b.count...].joined(separator: " ")
    }

    /// True when `next` is not a revision of `previous` but a fresh start.
    /// Partials revise earlier words, but never throw away most of a long
    /// utterance mid-speech. So a MUCH shorter partial is a restart when it
    /// arrives after a pause (`gap`), or when it does not even keep the
    /// opening word. Bias: keeping words the staff said beats the rare
    /// duplicated fragment, so ties go to "restart".
    static func isRestart(previous: String, next: String, gap: TimeInterval) -> Bool {
        let p = tokens(previous)
        let n = tokens(next)
        guard p.count >= 4, !n.isEmpty else { return false }
        guard n.count * 2 < p.count else { return false }
        if gap >= speechRestartGap { return true }
        // Same opening word within continuous speech: a trim-back revision
        // ("I took him to the" → "I") — let the recognizer regrow it.
        return p[0] != n[0]
    }
}
// END TranscriptAccumulator

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
///
/// Build 69 — the accumulation itself moved into `TranscriptAccumulator`
/// (above) and banks text on utterance boundaries and task errors too, so a
/// pause no longer wipes what was already said. The published `transcript`
/// can only grow or revise the utterance currently being spoken.
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

    /// The running transcript state (pure, tested offline).
    private var acc = TranscriptAccumulator()
    /// Which segment is live — a stale task callback (from a cancelled/finished
    /// segment) must never overwrite the next segment's text.
    private var segmentId = 0
    /// Segments restarted by the chaining logic during this recording (debug).
    private(set) var segmentRestarts = 0
    /// Utterances banked during this recording (debug).
    var utteranceBanks: Int { acc.banks }
    /// Safety valve: a recognizer that keeps failing instantly must not spin.
    private var consecutiveInstantFailures = 0
    private var segmentStartedAt = Date()
    /// When the recognizer last reported ANY result (changed or not). Partials
    /// arrive every few hundred ms during speech; a gap means a pause.
    private var lastResultAt = Date()

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
        acc.reset()
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
        lastResultAt = Date()
        acc.beginSegment()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true  // offline capable; audio never leaves the phone
        request.taskHint = .dictation                // long-form speech, not a short search query
        recognitionRequest = request

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self, mySegment == self.segmentId, self.isRecording else { return }
                if let result = result {
                    let reported = result.bestTranscription.formattedString
                    // Utterance complete (pause) — iOS 17+ on-device reports
                    // this WITHOUT isFinal and starts the next partial fresh.
                    let utteranceDone = result.speechRecognitionMetadata != nil
                    let gap = Date().timeIntervalSince(self.lastResultAt)
                    self.lastResultAt = Date()
                    self.absorb(reported, bank: utteranceDone || result.isFinal, gap: gap)
                    if result.isFinal {
                        // Segment finalised (≈1-minute limit or a long pause) —
                        // its text is banked; keep listening on a fresh request.
                        self.consecutiveInstantFailures = 0
                        self.restartSegment()
                        return
                    }
                }
                if error != nil {
                    // The segment died (recognizer error / cancelled by the
                    // system) with no final result. Bank whatever it had said
                    // — build 68 dropped it here — and chain a new segment,
                    // unless it is failing instantly over and over, in which
                    // case the recognizer is genuinely unavailable: stop.
                    self.bankLive()
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

    // MARK: - Transcript accumulation (delegates to TranscriptAccumulator)

    private func absorb(_ reported: String, bank: Bool, gap: TimeInterval) {
        acc.absorb(reported, bank: bank, gap: gap)
        publish()
    }

    private func bankLive() {
        acc.bankLive()
    }

    private func publish() {
        let merged = acc.transcript
        if merged != transcript {
            lastTranscriptChangeTime = Date()
            transcript = merged
        }
    }

    private func restartSegment() {
        guard isRecording else { return }
        bankLive()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        segmentRestarts += 1
        startSegment()
    }

    /// Kept for callers/tests that used the build-68 helper name.
    nonisolated static func join(_ committed: String, _ live: String) -> String {
        TranscriptAccumulator.join(committed, live)
    }

    func stopRecording() {
        guard isRecording else { return }
        bankLive()                   // keep the last utterance's partial
        publish()
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
