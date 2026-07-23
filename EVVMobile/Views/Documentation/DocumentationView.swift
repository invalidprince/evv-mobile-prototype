import SwiftUI

struct DocumentationView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let visit: Visit

    @State private var expanded: Set<String> = ["Health & Safety", "Outcomes & Goals"]
    @State private var note = VisitNote()
    @State private var loaded = false
    @State private var showSubmitted = false

    // Server mode state
    @State private var serverOutcomes: [ServerDocOutcome] = []
    @State private var serverHealthInfo: ServerDocHealthInfo?
    @State private var isLoadingTemplate = false
    @State private var loadError: String?
    @State private var isSubmitting = false
    @State private var submitError: String?

    // Unified outcomes: server or mock
    private var effectiveOutcomes: [Outcome] {
        if appState.mode == .server {
            return serverOutcomes.map { so in
                Outcome(
                    id: so.localId,
                    clientId: visit.client.id,
                    title: so.title,
                    goal: so.goal ?? ""
                )
            }
        } else {
            return MockData.outcomes.filter { $0.clientId == visit.client.id }
        }
    }

    // Effective health info
    private var effectiveClient: Client {
        if appState.mode == .server, let health = serverHealthInfo {
            var c = visit.client
            c.allergies = health.allergies
            c.safetyAlerts = health.safetyAlerts
            c.protocols = health.protocols
            return c
        }
        return visit.client
    }

    private var noteComplete: Bool {
        // If no outcomes, just additional comments is enough (or just submittable)
        let outcomes = effectiveOutcomes
        if outcomes.isEmpty { return true }
        return note.isComplete(for: outcomes)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header

                if isLoadingTemplate {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading documentation template…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }

                if let error = loadError {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Theme.danger)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(Theme.danger)
                        }
                        Button("Retry") {
                            Task { await loadServerTemplate() }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .cardStyle()
                }

                if !isLoadingTemplate && loadError == nil {
                    // Read-only health & safety info about the individual
                    DocSection(title: "Health & Safety", icon: "cross.case", expanded: $expanded) {
                        HealthSafetyInfoView(client: effectiveClient)
                    }

                    if !effectiveOutcomes.isEmpty {
                        DocSection(title: "Outcomes & Goals", icon: "target", expanded: $expanded) {
                            VStack(spacing: 16) {
                                ForEach(effectiveOutcomes) { outcome in
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
                        }
                    }

                    if !effectiveOutcomes.isEmpty && !noteComplete {
                        Label("To submit, each goal needs a data point and a narrative.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error = submitError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Theme.danger)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(Theme.danger)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 12) {
                        Button("Save Draft") {
                            appState.saveNoteDraft(visitId: visit.id, note: note)
                            dismiss()
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Button("Submit") {
                                if appState.mode == .server {
                                    Task { await submitServerDocumentation() }
                                } else {
                                    appState.submitNote(visitId: visit.id, note: note)
                                    showSubmitted = true
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle(enabled: noteComplete))
                            .disabled(!noteComplete)
                        }
                    }
                    .padding(.bottom, 16)
                }
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
                if appState.mode == .server {
                    Task { await loadServerTemplate() }
                }
            }
        }
        .alert("Documentation submitted", isPresented: $showSubmitted) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your visit note has been saved and queued to sync.")
        }
    }

    // MARK: - Server template loading

    private func loadServerTemplate() async {
        guard let svid = visit.serverVisitId else {
            loadError = "No server visit ID available"
            return
        }

        isLoadingTemplate = true
        loadError = nil

        do {
            let template = try await APIClient.shared.fetchDocumentation(visitId: svid)

            await MainActor.run {
                // Map outcomes
                serverOutcomes = (template.outcomes ?? []).map { so in
                    ServerDocOutcome(
                        serverId: so.id,
                        localId: UUID(),
                        title: so.title,
                        goal: so.goal,
                        status: so.status
                    )
                }

                // Map health info
                let health = template.healthInfo
                serverHealthInfo = ServerDocHealthInfo(
                    allergies: health?.allergies ?? [],
                    safetyAlerts: health?.safetyAlerts ?? [],
                    protocols: health?.protocols ?? [],
                    diagnosis: health?.diagnosis ?? [],
                    healthNotes: health?.healthNotes ?? ""
                )

                // Load existing structured note if present and draft is empty
                if let existing = template.existingNote, note.additionalComments.isEmpty && note.outcomeEntries.isEmpty {
                    loadExistingNote(existing)
                }

                isLoadingTemplate = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoadingTemplate = false
            }
        }
    }

    private func loadExistingNote(_ existing: ServerExistingNote) {
        // Load additional comments
        if let comments = existing.additionalComments, !comments.isEmpty {
            note.additionalComments = comments
        } else if let comments = existing.comments, !comments.isEmpty {
            // Legacy flat note format
            note.additionalComments = comments
        }

        // Load per-outcome entries
        if let entries = existing.outcomes {
            for entry in entries {
                // Match by server outcome ID
                if let outcomeId = entry.outcomeId,
                   let match = serverOutcomes.first(where: { $0.serverId == outcomeId }) {
                    var oe = OutcomeEntry()
                    if let pl = entry.promptLevel {
                        oe.promptLevel = PromptLevel.allCases.first(where: { $0.rawValue == pl })
                    }
                    oe.frequency = entry.frequency ?? 0
                    oe.goalOpportunity = entry.goalOpportunity ?? false
                    oe.behaviorObserved = entry.behaviorObserved ?? false
                    oe.narrative = entry.narrative ?? ""
                    note.outcomeEntries[match.localId] = oe
                }
            }
        }
    }

    // MARK: - Server documentation submission

    private func submitServerDocumentation() async {
        guard let svid = visit.serverVisitId else { return }

        isSubmitting = true
        submitError = nil

        // Build outcome entries payload
        let outcomePayload: [[String: Any]] = serverOutcomes.compactMap { so in
            guard let entry = note.outcomeEntries[so.localId] else { return nil }
            var dict: [String: Any] = [
                "outcomeId": so.serverId,
                "title": so.title,
                "frequency": entry.frequency,
                "goalOpportunity": entry.goalOpportunity,
                "behaviorObserved": entry.behaviorObserved,
                "narrative": entry.narrative
            ]
            if let pl = entry.promptLevel {
                dict["promptLevel"] = pl.rawValue
            }
            return dict
        }

        do {
            let response = try await APIClient.shared.submitDocumentation(
                visitId: svid,
                outcomes: outcomePayload,
                additionalComments: note.additionalComments
            )
            await MainActor.run {
                isSubmitting = false
                let docStatus = response.docStatus ?? "complete"
                let isComplete = docStatus.lowercased() == "complete"

                // Update visit state (B1 fix behavior)
                appState.markServerDocComplete(
                    visitId: visit.id,
                    serverVisitId: svid,
                    docStatus: docStatus
                )

                showSubmitted = true
            }
        } catch {
            await MainActor.run {
                isSubmitting = false
                if let apiErr = error as? APIError, apiErr.isNetworkError {
                    // Queue for offline - save draft and show message
                    appState.saveNoteDraft(visitId: visit.id, note: note)
                    submitError = "You're offline. Draft saved — submit when back online."
                } else {
                    submitError = error.localizedDescription
                }
            }
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

// MARK: - Server documentation data models

struct ServerDocOutcome {
    let serverId: Int
    let localId: UUID
    let title: String
    let goal: String?
    let status: String?
}

struct ServerDocHealthInfo {
    let allergies: [String]
    let safetyAlerts: [String]
    let protocols: [String]
    let diagnosis: [String]
    let healthNotes: String
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

            if client.allergies.isEmpty && client.safetyAlerts.isEmpty && client.protocols.isEmpty {
                Text("No health & safety information on file for this individual.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
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
