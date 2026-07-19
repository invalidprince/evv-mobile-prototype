import SwiftUI

struct DocumentationView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let visit: Visit

    @State private var expanded: Set<String> = ["Health & Safety", "Outcomes & Goals"]
    @State private var note = VisitNote()
    @State private var loaded = false
    @State private var showSubmitted = false

    private var clientOutcomes: [Outcome] {
        MockData.outcomes.filter { $0.clientId == visit.client.id }
    }

    private var noteComplete: Bool {
        note.isComplete(for: clientOutcomes)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header

                // Read-only health & safety info about the individual
                DocSection(title: "Health & Safety", icon: "cross.case", expanded: $expanded) {
                    HealthSafetyInfoView(client: visit.client)
                }

                if !clientOutcomes.isEmpty {
                    DocSection(title: "Outcomes & Goals", icon: "target", expanded: $expanded) {
                        VStack(spacing: 16) {
                            ForEach(clientOutcomes) { outcome in
                                OutcomeEntryView(outcome: outcome, entry: entryBinding(for: outcome))
                            }
                        }
                    }
                }

                DocSection(title: "Additional Comments", icon: "text.alignleft", expanded: $expanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Optional")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        DocTextEditor(text: $note.additionalComments, placeholder: "Anything else worth noting about this visit…", minHeight: 100)
                        Button(action: {}) {
                            Label("Dictate Note", systemImage: "mic.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }

                if !noteComplete {
                    Label("To submit, each goal needs a data point and a narrative.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Button("Save Draft") {
                        appState.saveNoteDraft(visitId: visit.id, note: note)
                        dismiss()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Submit") {
                        appState.submitNote(visitId: visit.id, note: note)
                        showSubmitted = true
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: noteComplete))
                    .disabled(!noteComplete)
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
                Button("Close") {
                    appState.saveNoteDraft(visitId: visit.id, note: note)
                    dismiss()
                }
            }
        }
        .onAppear {
            if !loaded {
                note = appState.noteDraft(for: visit.id)
                loaded = true
            }
        }
        .alert("Documentation submitted", isPresented: $showSubmitted) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your visit note has been saved and queued to sync.")
        }
    }

    private func entryBinding(for outcome: Outcome) -> Binding<OutcomeEntry> {
        Binding(
            get: { note.outcomeEntries[outcome.id] ?? OutcomeEntry() },
            set: { note.outcomeEntries[outcome.id] = $0 }
        )
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

// MARK: - Read-only health & safety information

struct HealthSafetyInfoView: View {
    let client: Client

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("For your reference — not part of the note", systemImage: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)

            infoBlock(title: "Allergies", icon: "allergens", color: Theme.danger, items: client.allergies)
            infoBlock(title: "Safety Alerts", icon: "exclamationmark.triangle.fill", color: Theme.warning, items: client.safetyAlerts)
            infoBlock(title: "Protocols", icon: "list.clipboard.fill", color: Theme.primary, items: client.protocols)
        }
    }

    @ViewBuilder
    private func infoBlock(title: String, icon: String, color: Color, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.bold))
                    .foregroundColor(color)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(.subheadline).foregroundColor(.secondary)
                        Text(item).font(.subheadline)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08))
            .cornerRadius(10)
        }
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
