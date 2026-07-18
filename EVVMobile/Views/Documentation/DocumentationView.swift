import SwiftUI

struct DocumentationView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let visit: Visit

    @State private var expanded: Set<String> = ["Activities"]
    @State private var activities = ""
    @State private var clientResponse = ""
    @State private var communityIntegration = ""
    @State private var healthSafety = ""
    @State private var narrative = ""
    @State private var showSubmitted = false

    private var clientOutcomes: [Outcome] {
        MockData.outcomes.filter { $0.clientId == visit.client.id }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header

                DocSection(title: "Activities", icon: "list.bullet.clipboard", expanded: $expanded) {
                    DocTextEditor(text: $activities, placeholder: "What activities were completed during this visit?")
                }
                DocSection(title: "Client Response", icon: "person.wave.2", expanded: $expanded) {
                    DocTextEditor(text: $clientResponse, placeholder: "How did the client respond and engage?")
                }
                DocSection(title: "Community Integration", icon: "building.2", expanded: $expanded) {
                    DocTextEditor(text: $communityIntegration, placeholder: "Community locations visited, interactions with others…")
                }
                DocSection(title: "Health / Safety", icon: "cross.case", expanded: $expanded) {
                    DocTextEditor(text: $healthSafety, placeholder: "Any health or safety concerns, medications, incidents…")
                }

                if !clientOutcomes.isEmpty {
                    DocSection(title: "Outcomes & Goals", icon: "target", expanded: $expanded) {
                        VStack(spacing: 16) {
                            ForEach(clientOutcomes) { outcome in
                                OutcomeEntryView(outcome: outcome)
                            }
                        }
                    }
                }

                DocSection(title: "Narrative", icon: "text.alignleft", expanded: $expanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        DocTextEditor(text: $narrative, placeholder: "Free-text visit narrative…", minHeight: 120)
                        Button(action: {}) {
                            Label("Dictate Note", systemImage: "mic.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }

                Button(action: {}) {
                    Label("Attach Photo", systemImage: "camera.fill")
                }
                .buttonStyle(SecondaryButtonStyle())

                HStack(spacing: 12) {
                    Button("Save Draft") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Submit") {
                        appState.markDocComplete(visitId: visit.id)
                        showSubmitted = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.bottom, 16)
            }
            .padding(16)
        }
        .background(Theme.screenBackground.ignoresSafeArea())
        .navigationTitle("Visit Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .alert("Documentation submitted", isPresented: $showSubmitted) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your visit note has been saved and queued to sync.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AvatarView(name: visit.client.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.clients.map { $0.name }.joined(separator: " & "))
                    .font(.headline)
                Text(visit.service.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .cardStyle()
    }
}

struct DocSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var expanded: Set<String>
    @ViewBuilder let content: Content

    private var isExpanded: Bool { expanded.contains(title) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded { expanded.remove(title) } else { expanded.insert(title) }
                }
            }) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.vertical, 4)
            }
            if isExpanded {
                content
                    .padding(.top, 10)
            }
        }
        .cardStyle()
    }
}

struct DocTextEditor: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 90

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.top, 8)
                    .padding(.leading, 5)
            }
            TextEditor(text: $text)
                .font(.subheadline)
                .frame(minHeight: minHeight)
                .opacity(text.isEmpty ? 0.6 : 1)
        }
        .background(Theme.screenBackground)
        .cornerRadius(10)
    }
}
