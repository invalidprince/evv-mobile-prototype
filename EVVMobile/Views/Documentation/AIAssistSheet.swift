import SwiftUI

/// Sheet for AI-assisted documentation drafting.
/// Staff describe the visit in their own words (typed or dictated via native keyboard mic).
/// The server calls the AI model to map the description into the structured form.
struct AIAssistSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Build 111 — the ONLY source of truth for "is this phone offline".
    /// DocumentationView already gates the AI Assist button on
    /// `appState.effectivelyOnline`, so the sheet inherits the same object.
    @EnvironmentObject var appState: AppState

    /// Callback: delivers the parsed draft to DocumentationView.
    let serverVisitId: String
    let onDraftReceived: (AIDraftResponse) -> Void

    @State private var inputText: String = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    /// Set when the LAST attempt timed out — the error row then offers a
    /// one-tap retry instead of making the caregiver re-type anything.
    @State private var canRetry = false

    private let exampleHint = """
    Example: "Worked on meal prep with Jamie today. She needed two verbal prompts to start but did great once going. We also practiced budgeting — she counted change independently for the first time. Good mood overall, no health concerns."
    """

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Describe the visit in your own words", systemImage: "text.bubble")
                            .font(.headline)

                        Text("Type or use the 🎤 microphone on your keyboard to dictate. The AI will fill in the documentation form based on what you describe — you'll review and edit everything before submitting.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Text input area
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack(alignment: .topLeading) {
                            if inputText.isEmpty {
                                Text(exampleHint)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            TextEditor(text: $inputText)
                                .font(.subheadline)
                                .frame(minHeight: 180)
                                .opacity(inputText.isEmpty ? 0.6 : 1)
                        }
                        .padding(4)
                        .background(Theme.screenBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )

                        HStack {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("The AI only uses what you write here — it won't add anything you didn't say.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Error message
                    if let error = errorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(Theme.danger)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(Theme.danger)
                            }
                            if canRetry && !isGenerating {
                                Button(action: generateDraft) {
                                    Label("Try again", systemImage: "arrow.clockwise")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.danger.opacity(0.08))
                        .cornerRadius(10)
                    }

                    // Generate button
                    if isGenerating {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Generating draft…")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    } else {
                        Button(action: generateDraft) {
                            Label("Generate Draft", systemImage: "sparkles")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
            }
            .background(Theme.screenBackground.ignoresSafeArea())
            .navigationTitle("✨ AI Assist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // Build 75: AI assist free-text input.
        .keyboardDismissable()
    }

    private func generateDraft() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isGenerating = true
        errorMessage = nil
        canRetry = false

        Task {
            do {
                let draft = try await APIClient.shared.generateAIDraft(
                    visitId: serverVisitId,
                    inputText: trimmed
                )
                await MainActor.run {
                    isGenerating = false
                    onDraftReceived(draft)
                    dismiss()
                }
            } catch is CancellationError {
                await MainActor.run { isGenerating = false }
            } catch {
                let apiErr = error as? APIError ?? APIError.networkError(error)
                if apiErr.isCancellation {
                    await MainActor.run { isGenerating = false }
                    return
                }
                let offline = !appState.effectivelyOnline || apiErr.isOffline
                await MainActor.run {
                    isGenerating = false
                    canRetry = false
                    switch apiErr {
                    case .serverError(429, _):
                        errorMessage = "Too many requests — please wait a few minutes and try again."
                    case .serverError(504, _), .serverError(502, _), .serverError(503, _):
                        // 504 = the server was still thinking when CloudFront
                        // gave up; 502/503 = the AI provider refused. All three
                        // are "try again", never "you're offline".
                        errorMessage = "AI Assist is taking longer than usual and didn't finish. Try again, or write your note manually."
                        canRetry = true
                    case .networkError where apiErr.isTimeout:
                        // Build 111 — the bug Nick hit 2026-10-05: a slow draft
                        // was reported as "no internet" on a connected phone.
                        errorMessage = "This is taking longer than usual — the draft didn't come back in time. Your connection is fine; tap Try again."
                        canRetry = true
                    case .networkError where offline:
                        errorMessage = "No internet connection. AI Assist requires connectivity."
                    case .networkError:
                        // Connected, not a timeout: say what actually happened
                        // rather than inventing an offline state.
                        errorMessage = "Couldn't reach AI Assist just now. Tap Try again, or write your note manually."
                        canRetry = true
                    default:
                        errorMessage = apiErr.localizedDescription
                    }
                }
            }
        }
    }
}

// MARK: - AI Draft API Response

struct AIDraftOutcome: Decodable {
    let outcomeId: Int?
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

/// A validated visit-question answer from the AI draft (build 25 / server
/// v0.4.212). The server only returns answers it could match against the
/// question's own options; `answer` uses the same wire shape the submit
/// contract uses — plain string for radio/text, JSON-encoded array string
/// for checkbox.
struct AIDraftQuestionAnswer: Decodable {
    let questionId: Int?
    let answer: String?
}

struct AIDraftPayload: Decodable {
    let outcomes: [AIDraftOutcome]?
    let additionalComments: String?
    let unaddressed: [Int]?
    let transportReviewedGoals: Bool?
    let visitQuestions: [AIDraftQuestionAnswer]?
    /// Where the service happened (build 28 / server v0.4.267). The server
    /// only returns a code it validated against this visit's allowed set.
    let serviceLocation: String?
}

struct AIDraftResponse: Decodable {
    let draft: AIDraftPayload
    let model: String?
}
