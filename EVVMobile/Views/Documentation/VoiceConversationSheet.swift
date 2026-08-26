import SwiftUI
import AVFoundation

/// A conversational voice-based documentation assistant.
/// The AI asks questions aloud (TTS), staff answers by voice (STT),
/// and when all outcomes are covered the AI generates structured note data.
///
/// Improvements over v1:
/// - TTS is interruptible: tapping mic or Skip stops speech immediately.
/// - Hands-free flow: after AI speaks, auto-listens; silence detection auto-sends.
/// - Structured outcome output: fills per-outcome form fields, not just comments.
struct VoiceConversationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let serverVisitId: String
    let outcomes: [ConversationOutcome]
    let individualName: String
    let service: String
    /// Called when conversation completes with structured result
    let onStructuredResult: (DocConversationResponse) -> Void

    // MARK: - State

    @StateObject private var speech = SpeechRecognizer()
    @State private var conversationHistory: [ConversationTurn] = []
    @State private var currentAIMessage: String = ""
    @State private var currentUserDraft: String = ""
    @State private var phase: ConversationPhase = .starting
    @State private var errorMessage: String?
    @State private var showPermissionAlert = false

    private let synthesizer = AVSpeechSynthesizer()
    @State private var ttsDelegate: TTSDelegate?

    // Silence detection for hands-free mode
    @State private var silenceTimer: Timer?
    /// How long the user must be silent (no transcript change) before auto-sending
    private let silenceThreshold: TimeInterval = 2.2
    /// Maximum time to wait for any speech before falling back to tap-to-talk
    private let emptyListenTimeout: TimeInterval = 10.0
    @State private var recordingStartTime: Date = Date()
    /// When true, hands-free auto-listen is disabled (user must tap mic)
    @State private var manualMode = false

    // Store the last structured response for the done callback
    @State private var lastResponse: DocConversationResponse?

    // MARK: - Types

    enum ConversationPhase {
        case starting       // Initial load — fetching first AI question
        case aiSpeaking     // AI question is being read aloud
        case waitingForUser // Waiting for staff to tap mic (manual mode or fallback)
        case listening      // Hands-free: auto-listening after AI spoke
        case recording      // Staff is speaking (manual tap-to-talk mode)
        case sending        // Sending user answer to backend
        case done           // Conversation complete — note generated
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Conversation transcript (scrollable)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(conversationHistory.enumerated()), id: \.offset) { index, turn in
                                ConversationBubble(turn: turn)
                                    .id(index)
                            }

                            // Current AI message (not yet in history during first display)
                            if !currentAIMessage.isEmpty && phase != .done {
                                ConversationBubble(turn: ConversationTurn(role: .assistant, content: currentAIMessage))
                                    .id("current-ai")
                            }

                            // Live transcription preview
                            if (phase == .recording || phase == .listening) && !currentUserDraft.isEmpty {
                                ConversationBubble(turn: ConversationTurn(role: .user, content: currentUserDraft))
                                    .opacity(0.6)
                                    .id("live-draft")
                            }

                            // Spacer to keep content above controls
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(16)
                    }
                    .onChange(of: conversationHistory.count) { _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: currentUserDraft) { _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }

                Divider()

                // Error message
                if let error = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Theme.danger)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(Theme.danger)
                        Spacer()
                        Button("Retry") {
                            errorMessage = nil
                            if conversationHistory.isEmpty {
                                Task { await startConversation() }
                            } else {
                                Task { await sendTurn(userText: currentUserDraft) }
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.danger.opacity(0.08))
                }

                // Controls area
                controlsBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
            }
            .background(Theme.screenBackground.ignoresSafeArea())
            .navigationTitle("🎙️ Voice Documentation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        stopEverything()
                        dismiss()
                    }
                }
            }
            .onAppear {
                setupTTSDelegate()
                Task { await startConversation() }
            }
            .onDisappear {
                stopEverything()
            }
            .onChange(of: speech.transcript) { newValue in
                if phase == .recording || phase == .listening {
                    currentUserDraft = newValue
                }
            }
            .onChange(of: speech.isRecording) { recording in
                // When speech recognizer stops on its own (e.g. final result or error),
                // auto-send if we have content (manual recording mode only).
                if !recording && phase == .recording && !currentUserDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    stopSilenceTimer()
                    phase = .sending
                    let text = currentUserDraft
                    Task { await sendTurn(userText: text) }
                }
                // Same for hands-free listening mode
                if !recording && phase == .listening && !currentUserDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    stopSilenceTimer()
                    phase = .sending
                    let text = currentUserDraft
                    Task { await sendTurn(userText: text) }
                }
            }
            .onChange(of: speech.permissionDenied) { denied in
                if denied { showPermissionAlert = true }
            }
            .alert(isPresented: $showPermissionAlert) {
                Alert(
                    title: Text("Microphone & Speech Access Required"),
                    message: Text("Enable Microphone and Speech Recognition in Settings to use voice documentation."),
                    primaryButton: .default(Text("Open Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    // MARK: - Controls Bar

    @ViewBuilder
    private var controlsBar: some View {
        switch phase {
        case .starting:
            HStack(spacing: 12) {
                ProgressView()
                Text("Starting conversation…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

        case .aiSpeaking:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(Theme.primary)
                        .font(.title3)
                    Text("AI is speaking…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 20) {
                    // Skip: stop TTS and go to listening
                    Button("Skip") {
                        interruptTTSAndListen()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    // Mic button: interrupt TTS and start answering immediately
                    Button(action: { interruptTTSAndListen() }) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(Theme.primary)
                    }
                    .accessibilityLabel("Interrupt AI and start speaking")
                }
            }
            .frame(maxWidth: .infinity)

        case .waitingForUser:
            VStack(spacing: 10) {
                Text("Tap the mic to answer")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 20) {
                    // Finish early button
                    Button(action: { Task { await finishEarly() } }) {
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                            Text("I'm Done")
                                .font(.caption2)
                        }
                        .foregroundColor(Theme.success)
                    }

                    // Big mic button
                    Button(action: { startRecording() }) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(Theme.primary)
                    }
                    .accessibilityLabel("Start recording your answer")

                    // Placeholder to balance layout
                    Color.clear.frame(width: 44, height: 44)
                }
            }

        case .listening:
            // Hands-free: auto-listening after AI finished speaking
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.success)
                        .frame(width: 8, height: 8)
                    Text(currentUserDraft.isEmpty ? "Listening…" : "Listening — will auto-send after pause")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 20) {
                    // "I'm Done" button
                    Button(action: {
                        stopSilenceTimer()
                        speech.stopRecording()
                        Task { await finishEarly() }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                            Text("I'm Done")
                                .font(.caption2)
                        }
                        .foregroundColor(Theme.success)
                    }

                    // Mic button: tap to stop and send immediately
                    Button(action: { stopListeningAndSend() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(Theme.primary)
                    }
                    .accessibilityLabel("Stop listening and send now")

                    // Placeholder to balance layout
                    Color.clear.frame(width: 44, height: 44)
                }
            }

        case .recording:
            VStack(spacing: 10) {
                Text(currentUserDraft.isEmpty ? "Listening…" : "Listening — tap stop when done")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 20) {
                    // Cancel this recording
                    Button(action: { cancelRecording() }) {
                        VStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                            Text("Cancel")
                                .font(.caption2)
                        }
                        .foregroundColor(Theme.danger)
                    }

                    // Stop/send button
                    Button(action: { stopAndSend() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(Theme.danger)
                    }
                    .accessibilityLabel("Stop recording and send")

                    // Re-record (stop without sending)
                    Button(action: { cancelRecording() }) {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.title2)
                            Text("Redo")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }

        case .sending:
            HStack(spacing: 12) {
                ProgressView()
                Text("Processing your response…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

        case .done:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(Theme.success)
                Text("Documentation complete!")
                    .font(.headline)
                Button("Use This Note") {
                    if let response = lastResponse {
                        onStructuredResult(response)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Conversation Logic

    private func startConversation() async {
        phase = .starting
        errorMessage = nil
        await callConversationEndpoint(history: [], finish: false)
    }

    private func sendTurn(userText: String) async {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Nothing to send — go back to waiting
            if manualMode {
                phase = .waitingForUser
            } else {
                autoListen()
            }
            return
        }

        // Add user turn to history
        let userTurn = ConversationTurn(role: .user, content: trimmed)
        conversationHistory.append(userTurn)

        // Add the current AI message to history if it isn't already there
        if !currentAIMessage.isEmpty {
            // Insert AI message before the user's response
            let aiTurn = ConversationTurn(role: .assistant, content: currentAIMessage)
            conversationHistory.insert(aiTurn, at: conversationHistory.count - 1)
        }

        currentUserDraft = ""
        currentAIMessage = ""

        // Build API history
        let apiHistory = conversationHistory.map { turn in
            ["role": turn.role == .assistant ? "assistant" : "user", "content": turn.content]
        }

        await callConversationEndpoint(history: apiHistory, finish: false)
    }

    private func finishEarly() async {
        phase = .sending
        stopSilenceTimer()

        // Add the current AI message to history if present
        if !currentAIMessage.isEmpty {
            conversationHistory.append(ConversationTurn(role: .assistant, content: currentAIMessage))
            currentAIMessage = ""
        }

        let apiHistory = conversationHistory.map { turn in
            ["role": turn.role == .assistant ? "assistant" : "user", "content": turn.content]
        }

        await callConversationEndpoint(history: apiHistory, finish: true)
    }

    private func callConversationEndpoint(history: [[String: String]], finish: Bool) async {
        do {
            let response = try await APIClient.shared.docConversation(
                visitId: serverVisitId,
                outcomes: outcomes,
                individualName: individualName,
                service: service,
                history: history,
                finish: finish
            )

            await MainActor.run {
                if response.done {
                    // Store structured response for callback
                    lastResponse = response
                    // Add summary message to conversation history for display
                    let displayMessage: String
                    if let outcomes = response.outcomes, !outcomes.isEmpty {
                        let filledCount = outcomes.filter { !($0.narrative ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
                        displayMessage = "Documentation complete — \(filledCount) outcome\(filledCount == 1 ? "" : "s") filled."
                        if let comments = response.additionalComments, !comments.isEmpty {
                            // Show a preview
                        }
                    } else {
                        // Fallback: plain text note
                        displayMessage = response.message
                    }
                    conversationHistory.append(ConversationTurn(role: .assistant, content: displayMessage))
                    currentAIMessage = ""
                    phase = .done
                } else {
                    // Next question — display and speak it
                    currentAIMessage = response.message
                    speakText(response.message)
                    phase = .aiSpeaking
                }
            }
        } catch is CancellationError {
            // Task was cancelled (view dismissed, etc.) — silently ignore.
        } catch {
            let apiErr = error as? APIError ?? APIError.networkError(error)
            // Silently ignore cancellation — don't show error banner.
            if apiErr.isCancellation { return }

            await MainActor.run {
                switch apiErr {
                case .serverError(429, _):
                    errorMessage = "Too many requests — please wait a moment."
                case .serverError(503, _), .serverError(502, _):
                    errorMessage = "AI is temporarily unavailable. Try again shortly."
                case .networkError:
                    errorMessage = "No internet connection."
                default:
                    errorMessage = apiErr.localizedDescription
                }
                phase = conversationHistory.isEmpty ? .starting : .waitingForUser
            }
        }
    }

    // MARK: - Speech (TTS) — Interruptible

    private func setupTTSDelegate() {
        let delegate = TTSDelegate { [self] in
            // Called when TTS finishes speaking (or is cancelled)
            Task { @MainActor in
                if phase == .aiSpeaking {
                    // TTS finished naturally — start auto-listening (hands-free)
                    if !manualMode {
                        autoListen()
                    } else {
                        phase = .waitingForUser
                    }
                }
            }
        }
        ttsDelegate = delegate
        synthesizer.delegate = delegate
    }

    private func speakText(_ text: String) {
        // Configure audio session for playback before speaking
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .default, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05 // Slightly faster than default
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }

    /// Immediately stop TTS and begin listening (used by mic tap during AI speech and Skip button)
    private func interruptTTSAndListen() {
        synthesizer.stopSpeaking(at: .immediate)
        // The TTSDelegate.didCancel will fire, but we take over here
        // to avoid race conditions — go straight to listening.
        if !manualMode {
            autoListen()
        } else {
            startRecording()
        }
    }

    // MARK: - Speech (STT) — Hands-Free & Manual

    /// Start auto-listening (hands-free mode). After AI finishes speaking,
    /// this is called automatically. Uses silence detection to auto-send.
    private func autoListen() {
        currentUserDraft = ""
        phase = .listening
        recordingStartTime = Date()
        Task { await speech.startRecording() }
        startSilenceTimer()
    }

    /// Manual recording mode (tap mic to start)
    private func startRecording() {
        currentUserDraft = ""
        phase = .recording
        Task { await speech.startRecording() }
    }

    /// Stop listening (hands-free) and send whatever was captured
    private func stopListeningAndSend() {
        stopSilenceTimer()
        speech.stopRecording()
        let text = currentUserDraft
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            phase = .sending
            Task { await sendTurn(userText: text) }
        } else {
            // Nothing captured — go to manual mode
            phase = .waitingForUser
        }
    }

    private func stopAndSend() {
        speech.stopRecording()
        let text = currentUserDraft
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            phase = .sending
            Task { await sendTurn(userText: text) }
        } else {
            phase = .waitingForUser
        }
    }

    private func cancelRecording() {
        stopSilenceTimer()
        speech.stopRecording()
        currentUserDraft = ""
        phase = .waitingForUser
    }

    private func stopEverything() {
        stopSilenceTimer()
        speech.stopRecording()
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Silence Detection Timer

    /// Starts a repeating timer that checks for silence (no transcript change)
    /// and auto-sends when the user pauses for `silenceThreshold` seconds.
    private func startSilenceTimer() {
        stopSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [self] _ in
            Task { @MainActor in
                guard phase == .listening else {
                    stopSilenceTimer()
                    return
                }

                let now = Date()
                let draft = currentUserDraft.trimmingCharacters(in: .whitespacesAndNewlines)

                if !draft.isEmpty {
                    // User has said something — check if they've been silent long enough
                    let silenceDuration = now.timeIntervalSince(speech.lastTranscriptChangeTime)
                    if silenceDuration >= silenceThreshold {
                        // Auto-send!
                        stopSilenceTimer()
                        speech.stopRecording()
                        let text = currentUserDraft
                        phase = .sending
                        Task { await sendTurn(userText: text) }
                    }
                } else {
                    // User hasn't said anything yet — check empty-listen timeout
                    let waitDuration = now.timeIntervalSince(recordingStartTime)
                    if waitDuration >= emptyListenTimeout {
                        // Fall back to manual tap-to-talk
                        stopSilenceTimer()
                        speech.stopRecording()
                        manualMode = true
                        phase = .waitingForUser
                    }
                }
            }
        }
    }

    private func stopSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
}

// MARK: - Supporting Types

struct ConversationTurn {
    enum Role { case assistant, user }
    let role: Role
    let content: String
}

struct ConversationOutcome {
    let title: String
    let goal: String?
}

// MARK: - Conversation Bubble

struct ConversationBubble: View {
    let turn: ConversationTurn

    var body: some View {
        HStack {
            if turn.role == .user { Spacer(minLength: 48) }

            VStack(alignment: turn.role == .assistant ? .leading : .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    if turn.role == .assistant {
                        Image(systemName: "brain.head.profile")
                            .font(.caption2)
                            .foregroundColor(Theme.primary)
                        Text("AI")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(Theme.primary)
                    } else {
                        Text("You")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text(turn.content)
                    .font(.subheadline)
                    .padding(12)
                    .background(turn.role == .assistant ? Theme.primary.opacity(0.08) : Color(UIColor.tertiarySystemFill))
                    .cornerRadius(16)
            }

            if turn.role == .assistant { Spacer(minLength: 48) }
        }
    }
}

// MARK: - TTS Delegate

/// Bridges AVSpeechSynthesizerDelegate to a closure for SwiftUI.
final class TTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish()
    }
}

// MARK: - API Response

struct DocConversationResponse: Decodable {
    let done: Bool
    let message: String
    /// Structured per-outcome entries (only present when done=true)
    let outcomes: [DocConversationOutcome]?
    /// Additional comments not tied to a specific outcome (only present when done=true)
    let additionalComments: String?
    /// Transport review question answer (only present when done=true)
    let transportReviewedGoals: Bool?
    /// Where the service happened (build 28 / server v0.4.267). The server
    /// only returns a code it validated against this visit's allowed set.
    let serviceLocation: String?
}

struct DocConversationOutcome: Decodable {
    let title: String?
    // v0.4.152 shape
    let prompts: Int?
    let successes: Int?
    let opportunities: Int?
    let na: Bool?
    // Legacy shape — kept so an older server response still decodes.
    let promptLevel: String?
    let frequency: Int?
    let narrative: String?
}
