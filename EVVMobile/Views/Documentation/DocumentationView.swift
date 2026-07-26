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

    // AI Assist state
    @State private var aiAssistEnabled = false
    @State private var showAIAssistSheet = false
    @State private var aiDraftApplied = false
    @State private var aiInputText: String?
    @State private var aiModel: String?
    @State private var aiDraftedOutcomeIds: Set<UUID> = []  // Outcome IDs populated by AI
    @State private var aiUnaddressedOutcomeIds: Set<Int> = []  // Server outcome IDs not addressed
    @State private var sectionsViewed: Set<UUID> = []  // Track which AI-drafted sections staff viewed

    // Voice conversation state
    @State private var showVoiceConversation = false

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
        let baseComplete = note.isComplete(for: outcomes)
        // If AI draft was used, require staff to have viewed each drafted section
        if aiDraftApplied && !aiDraftedOutcomeIds.isEmpty {
            let allViewed = aiDraftedOutcomeIds.allSatisfy { sectionsViewed.contains($0) }
            return baseComplete && allViewed
        }
        return baseComplete
    }

    /// True when server mode and offline — blocks submission.
    private var isOfflineBlocked: Bool {
        appState.mode == .server && !appState.effectivelyOnline
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header

                // Offline banner
                if isOfflineBlocked {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(Theme.danger)
                        Text("Note submission requires an internet connection")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.danger)
                        Spacer()
                    }
                    .padding(12)
                    .background(Theme.danger.opacity(0.08))
                    .cornerRadius(10)
                }

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
                    // AI Assist buttons (server mode, online, feature flag on)
                    if appState.mode == .server && appState.effectivelyOnline && aiAssistEnabled && !aiDraftApplied {
                        // Voice Conversation button
                        Button(action: { showVoiceConversation = true }) {
                            HStack(spacing: 8) {
                                Text("🎙️")
                                Text("Voice Conversation")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("Talk through your visit")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [Theme.success.opacity(0.10), Theme.success.opacity(0.04)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.success.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        // Text-based AI Assist button
                        Button(action: { showAIAssistSheet = true }) {
                            HStack(spacing: 8) {
                                Text("✨")
                                Text("AI Assist")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("Type or dictate → auto-fill form")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [Theme.primary.opacity(0.08), Theme.primary.opacity(0.04)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.primary.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // AI draft applied banner
                    if aiDraftApplied {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(Theme.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI draft applied")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Theme.primary)
                                Text("Review each section before submitting. Edit anything that needs changing.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Theme.primary.opacity(0.06))
                        .cornerRadius(10)
                    }

                    // Read-only health & safety info about the individual
                    DocSection(title: "Health & Safety", icon: "cross.case", expanded: $expanded) {
                        HealthSafetyInfoView(client: effectiveClient)
                    }

                    if !effectiveOutcomes.isEmpty {
                        DocSection(title: "Outcomes & Goals", icon: "target", expanded: $expanded) {
                            VStack(spacing: 16) {
                                ForEach(effectiveOutcomes) { outcome in
                                    VStack(spacing: 0) {
                                        // AI draft badge or unaddressed chip
                                        if aiDraftApplied {
                                            if let so = serverOutcomes.first(where: { $0.localId == outcome.id }),
                                               aiUnaddressedOutcomeIds.contains(so.serverId) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "exclamationmark.circle.fill")
                                                        .font(.caption2)
                                                        .foregroundColor(Theme.danger)
                                                    Text("Not mentioned — please complete")
                                                        .font(.caption2.weight(.semibold))
                                                        .foregroundColor(Theme.danger)
                                                    Spacer()
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Theme.danger.opacity(0.08))
                                                .cornerRadius(8)
                                            } else if aiDraftedOutcomeIds.contains(outcome.id) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "sparkles")
                                                        .font(.caption2)
                                                        .foregroundColor(Theme.primary)
                                                    Text(sectionsViewed.contains(outcome.id) ? "AI draft — reviewed ✓" : "AI draft — tap to review")
                                                        .font(.caption2.weight(.medium))
                                                        .foregroundColor(Theme.primary)
                                                    Spacer()
                                                    if !sectionsViewed.contains(outcome.id) {
                                                        Image(systemName: "eye")
                                                            .font(.caption2)
                                                            .foregroundColor(Theme.primary)
                                                    }
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Theme.primary.opacity(0.06))
                                                .cornerRadius(8)
                                                .onTapGesture {
                                                    sectionsViewed.insert(outcome.id)
                                                }
                                            }
                                        }

                                        OutcomeEntryView(outcome: outcome, entry: entryBinding(for: outcome))
                                            .onTapGesture {
                                                // Mark section as viewed when interacted with
                                                if aiDraftApplied && aiDraftedOutcomeIds.contains(outcome.id) {
                                                    sectionsViewed.insert(outcome.id)
                                                }
                                            }
                                    }
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
                        if aiDraftApplied && !aiDraftedOutcomeIds.isEmpty {
                            let unviewed = aiDraftedOutcomeIds.subtracting(sectionsViewed)
                            if !unviewed.isEmpty {
                                Label("Review all AI-drafted sections before submitting (\(unviewed.count) remaining).", systemImage: "eye")
                                    .font(.caption)
                                    .foregroundColor(Theme.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
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
                            saveDraft()
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
                            .buttonStyle(PrimaryButtonStyle(enabled: noteComplete && !isOfflineBlocked))
                            .disabled(!noteComplete || isOfflineBlocked)
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
                    saveDraft()
                    dismiss()
                }
            }
        }
        .onAppear {
            if !loaded {
                note = loadDraft()
                loaded = true
                if appState.mode == .server {
                    Task { await loadServerTemplate() }
                }
            }
        }
        .sheet(isPresented: $showAIAssistSheet) {
            if let svid = visit.serverVisitId {
                AIAssistSheet(serverVisitId: svid) { draftResponse in
                    applyAIDraft(draftResponse)
                }
            }
        }
        .sheet(isPresented: $showVoiceConversation) {
            if let svid = visit.serverVisitId {
                VoiceConversationSheet(
                    serverVisitId: svid,
                    outcomes: serverOutcomes.map { so in
                        ConversationOutcome(title: so.title, goal: so.goal)
                    },
                    individualName: visit.client.name,
                    service: visit.service.rawValue
                ) { response in
                    applyVoiceConversationResult(response)
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
                // Map outcomes — use deterministic localIds so drafts persist
                serverOutcomes = (template.outcomes ?? []).map { so in
                    ServerDocOutcome(
                        serverId: so.id,
                        localId: ServerDocOutcome.stableLocalId(for: so.id),
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

                // Capture AI Assist feature flag
                aiAssistEnabled = template.aiAssistEnabled ?? false

                // Load existing structured note if present and draft is empty
                if let existing = template.existingNote, note.additionalComments.isEmpty && note.outcomeEntries.isEmpty {
                    loadExistingNote(existing)
                }

                isLoadingTemplate = false
            }
        } catch is CancellationError {
            // Silently ignore task cancellation
            await MainActor.run { isLoadingTemplate = false }
        } catch {
            let apiErr = error as? APIError ?? APIError.networkError(error)
            if apiErr.isCancellation {
                await MainActor.run { isLoadingTemplate = false }
                return
            }
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
                        // Try new DataPoint values first, then fall back to legacy
                        oe.dataPoint = DataPoint.allCases.first(where: { $0.rawValue == pl })
                        if oe.dataPoint == nil {
                            // Legacy prompt level — map to closest new data point
                            if let legacy = LegacyPromptLevel(rawValue: pl) {
                                switch legacy {
                                case .independent: oe.dataPoint = .successes
                                case .verbal, .gestural: oe.dataPoint = .prompts
                                case .partialPhysical, .fullPhysical: oe.dataPoint = .prompts
                                }
                            }
                        }
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

    // MARK: - AI Draft application

    private func applyAIDraft(_ response: AIDraftResponse) {
        let draft = response.draft
        aiModel = response.model

        // Store the unaddressed outcome IDs
        aiUnaddressedOutcomeIds = Set(draft.unaddressed ?? [])

        // Apply outcome entries from the draft
        var draftedIds = Set<UUID>()
        for draftOutcome in draft.outcomes ?? [] {
            guard let serverId = draftOutcome.outcomeId,
                  let match = serverOutcomes.first(where: { $0.serverId == serverId }) else { continue }

            // Skip if this outcome was unaddressed (narrative is nil/empty)
            let narrative = draftOutcome.narrative ?? ""
            if narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

            var oe = OutcomeEntry()
            if let pl = draftOutcome.promptLevel {
                oe.dataPoint = DataPoint.allCases.first(where: { $0.rawValue == pl })
                // Fall back: legacy prompt level values from AI
                if oe.dataPoint == nil {
                    if let legacy = LegacyPromptLevel(rawValue: pl) {
                        switch legacy {
                        case .independent: oe.dataPoint = .successes
                        case .verbal, .gestural, .partialPhysical, .fullPhysical: oe.dataPoint = .prompts
                        }
                    }
                }
            }
            oe.frequency = draftOutcome.frequency ?? 0
            oe.goalOpportunity = draftOutcome.goalOpportunity ?? false
            oe.behaviorObserved = draftOutcome.behaviorObserved ?? false
            oe.narrative = narrative
            note.outcomeEntries[match.localId] = oe
            draftedIds.insert(match.localId)
        }

        // Apply additional comments if present
        if let comments = draft.additionalComments, !comments.isEmpty {
            note.additionalComments = comments
        }

        aiDraftedOutcomeIds = draftedIds
        aiDraftApplied = true

        // Expand outcomes section to show the draft
        expanded.insert("Outcomes & Goals")
    }

    // MARK: - Voice Conversation structured result application

    private func applyVoiceConversationResult(_ response: DocConversationResponse) {
        // If the response has structured outcomes, fill per-outcome form fields
        var draftedIds = Set<UUID>()

        if let responseOutcomes = response.outcomes, !responseOutcomes.isEmpty {
            for voiceOutcome in responseOutcomes {
                // Match by title (case-insensitive, trimmed)
                guard let voiceTitle = voiceOutcome.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let match = serverOutcomes.first(where: {
                          $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                              .caseInsensitiveCompare(voiceTitle) == .orderedSame
                      }) else { continue }

                // Skip outcomes with empty narrative (not discussed)
                let narrative = voiceOutcome.narrative ?? ""
                if narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

                var oe = OutcomeEntry()
                if let pl = voiceOutcome.promptLevel {
                    oe.dataPoint = DataPoint.allCases.first(where: { $0.rawValue == pl })
                    // Fall back: legacy prompt level values from AI
                    if oe.dataPoint == nil {
                        if let legacy = LegacyPromptLevel(rawValue: pl) {
                            switch legacy {
                            case .independent: oe.dataPoint = .successes
                            case .verbal, .gestural, .partialPhysical, .fullPhysical: oe.dataPoint = .prompts
                            }
                        }
                    }
                }
                oe.frequency = voiceOutcome.frequency ?? 0
                oe.goalOpportunity = voiceOutcome.goalOpportunity ?? false
                oe.behaviorObserved = voiceOutcome.behaviorObserved ?? false
                oe.narrative = narrative
                note.outcomeEntries[match.localId] = oe
                draftedIds.insert(match.localId)
            }
        }

        // Apply additional comments
        if let comments = response.additionalComments, !comments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            note.additionalComments = comments
        } else if draftedIds.isEmpty {
            // Fallback: no structured outcomes — put the message in additional comments (backward compat)
            note.additionalComments = response.message
        }

        aiDraftedOutcomeIds = draftedIds
        aiDraftApplied = true
        aiInputText = "[Voice conversation]"

        // Expand outcomes section to show the result
        expanded.insert("Outcomes & Goals")
    }

    // MARK: - Draft save/load (server-mode uses serverVisitId for stability)

    /// Save the current draft. In server mode, uses serverVisitId as the key
    /// so the draft survives visit-list refreshes (which regenerate local UUIDs).
    private func saveDraft() {
        if appState.mode == .server, let svid = visit.serverVisitId {
            appState.saveServerNoteDraft(serverVisitId: svid, note: note)
        } else {
            appState.saveNoteDraft(visitId: visit.id, note: note)
        }
    }

    /// Load any existing draft. In server mode, tries serverVisitId first,
    /// then falls back to local UUID (covers the case where a draft was saved
    /// before this fix).
    private func loadDraft() -> VisitNote {
        if appState.mode == .server, let svid = visit.serverVisitId {
            let draft = appState.serverNoteDraft(for: svid)
            if !draft.outcomeEntries.isEmpty || !draft.additionalComments.isEmpty {
                return draft
            }
        }
        return appState.noteDraft(for: visit.id)
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
            if let dp = entry.dataPoint {
                // Send as promptLevel key for backward compat with server
                dict["promptLevel"] = dp.rawValue
            }
            return dict
        }

        do {
            let response = try await APIClient.shared.submitDocumentation(
                visitId: svid,
                outcomes: outcomePayload,
                additionalComments: note.additionalComments,
                aiAssisted: aiDraftApplied,
                aiInputText: aiInputText,
                aiModel: aiModel
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
        } catch is CancellationError {
            await MainActor.run { isSubmitting = false }
        } catch {
            let apiErr = error as? APIError ?? APIError.networkError(error)
            if apiErr.isCancellation {
                await MainActor.run { isSubmitting = false }
                return
            }
            await MainActor.run {
                isSubmitting = false
                if apiErr.isNetworkError {
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
    /// Deterministic UUID derived from serverId so that draft entries
    /// (keyed by localId) survive across template reloads.
    let localId: UUID
    let title: String
    let goal: String?
    let status: String?

    /// Create a stable, deterministic UUID from a server outcome ID.
    /// This ensures draft outcome entries (keyed by localId) persist
    /// correctly across template reloads within the same app session.
    static func stableLocalId(for serverId: Int) -> UUID {
        // Build a 16-byte UUID from a fixed prefix + the server ID.
        // Prefix bytes 0xEE 0x0C serve as a namespace marker.
        var bytes: [UInt8] = [0xEE, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        withUnsafeBytes(of: serverId.bigEndian) { buf in
            for (i, b) in buf.enumerated() where i < 8 {
                bytes[8 + i] = b
            }
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
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
    var showDictation: Bool = true

    var body: some View {
        VStack(spacing: 0) {
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
            if showDictation {
                HStack {
                    Spacer()
                    DictationButton(text: $text)
                }
                .padding(.trailing, 4)
                .padding(.bottom, 4)
            }
        }
        .background(Theme.screenBackground)
        .cornerRadius(10)
    }
}
