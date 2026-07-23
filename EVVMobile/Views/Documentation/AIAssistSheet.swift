import SwiftUI

/// Sheet for AI-assisted documentation drafting.
/// Staff describe the visit in their own words (typed or dictated via native keyboard mic).
/// The server calls the AI model to map the description into the structured form.
struct AIAssistSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Callback: delivers the parsed draft to DocumentationView.
    let serverVisitId: String
    let onDraftReceived: (AIDraftResponse) -> Void

    @State private var inputText: String = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?

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
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Theme.danger)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(Theme.danger)
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
    }

    private func generateDraft() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isGenerating = true
        errorMessage = nil

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
            } catch {
                await MainActor.run {
                    isGenerating = false
                    if let apiErr = error as? APIError {
                        switch apiErr {
                        case .serverError(429, _):
                            errorMessage = "Too many requests — please wait a few minutes and try again."
                        case .serverError(503, _), .serverError(502, _):
                            errorMessage = "AI Assist is temporarily unavailable. Write your note manually for now."
                        case .networkError:
                            errorMessage = "No internet connection. AI Assist requires connectivity."
                        default:
                            errorMessage = apiErr.localizedDescription
                        }
                    } else {
                        errorMessage = "Something went wrong. Try again or write your note manually."
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
    let promptLevel: String?
    let frequency: Int?
    let goalOpportunity: Bool?
    let behaviorObserved: Bool?
    let narrative: String?
}

struct AIDraftPayload: Decodable {
    let outcomes: [AIDraftOutcome]?
    let additionalComments: String?
    let unaddressed: [Int]?
}

struct AIDraftResponse: Decodable {
    let draft: AIDraftPayload
    let model: String?
}
