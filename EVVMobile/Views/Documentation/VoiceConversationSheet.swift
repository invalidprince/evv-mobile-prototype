import SwiftUI
import AVFoundation

/// A conversational voice-based documentation assistant.
/// The AI asks questions aloud (TTS), staff answers by voice (STT),
/// and when all outcomes are covered the AI generates a polished note.
struct VoiceConversationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let serverVisitId: String
    let outcomes: [ConversationOutcome]
    let individualName: String
    let service: String
    let onNoteGenerated: (String) -> Void

    // MARK: - State

    @StateObject private var speech = SpeechRecognizer()
    @State private var conversationHistory: [ConversationTurn] = []
    @State private var currentAIMessage: String = ""
    @State private var currentUserDraft: String = ""
    @State private var phase: ConversationPhase = .starting
    @State private var errorMessage: String?
    @State private var showPermissionAlert = false
    @State private var isSpeakingTTS = false

    private let synthesizer = AVSpeechSynthesizer()
    @State private var ttsDelegate: TTSDelegate?

    // MARK: - Types

    enum ConversationPhase {
        case starting       // Initial load — fetching first AI question
        case aiSpeaking     // AI question is being read aloud
        case waitingForUser // Waiting for staff to tap mic
        case recording      // Staff is speaking
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
                            if phase == .recording && !currentUserDraft.isEmpty {
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
                if phase == .recording {
                    currentUserDraft = newValue
                }
            }
            .onChange(of: speech.isRecording) { recording in
                // When speech recognizer stops on its own (silence/final result),
                // auto-send if we have content
                if !recording && phase == .recording && !currentUserDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                Button("Skip") {
                    synthesizer.stopSpeaking(at: .immediate)
                    phase = .waitingForUser
                }
                .font(.caption)
                .foregroundColor(.secondary)
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

                    // Stop/send button (pulsing)
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
                Text("Note generated!")
                    .font(.headline)
                Button("Use This Note") {
                    // The last assistant message with done=true is the note
                    if let lastAI = conversationHistory.last(where: { $0.role == .assistant }) {
                        onNoteGenerated(lastAI.content)
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
            phase = .waitingForUser
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
                    // Final note — add to history and transition to done
                    conversationHistory.append(ConversationTurn(role: .assistant, content: response.message))
                    currentAIMessage = ""
                    phase = .done
                } else {
                    // Next question — display and speak it
                    currentAIMessage = response.message
                    speakText(response.message)
                    phase = .aiSpeaking
                }
            }
        } catch {
            await MainActor.run {
                if let apiErr = error as? APIError {
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
                } else {
                    errorMessage = "Something went wrong. Tap Retry."
                }
                phase = conversationHistory.isEmpty ? .starting : .waitingForUser
            }
        }
    }

    // MARK: - Speech (TTS)

    private func setupTTSDelegate() {
        let delegate = TTSDelegate { [self] in
            // Called when TTS finishes speaking
            Task { @MainActor in
                if phase == .aiSpeaking {
                    phase = .waitingForUser
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

    // MARK: - Speech (STT)

    private func startRecording() {
        currentUserDraft = ""
        phase = .recording
        Task { await speech.startRecording() }
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
        speech.stopRecording()
        currentUserDraft = ""
        phase = .waitingForUser
    }

    private func stopEverything() {
        speech.stopRecording()
        synthesizer.stopSpeaking(at: .immediate)
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
}
