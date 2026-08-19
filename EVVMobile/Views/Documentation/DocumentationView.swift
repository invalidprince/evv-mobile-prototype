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
    @State private var serverQuestions: [ServerDocQuestion] = []
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
            c.communicationUnderstood = health.communicationUnderstood
            c.adaptiveEquipment = health.adaptiveEquipment
            c.supervisionLevel = health.supervisionLevel
            return c
        }
        return visit.client
    }

    /// The seeded service-scoped transport question, when present. Used to keep
    /// sending the legacy transportReviewedGoals bool alongside questionAnswers.
    private var transportQuestion: ServerDocQuestion? {
        serverQuestions.first { q in
            guard q.scope == "service" else { return false }
            var t = q.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasSuffix("?") { t = String(t.dropLast()) }
            return t.caseInsensitiveCompare("Reviewed goals, activities, and schedule during transport") == .orderedSame
        }
    }

    /// True when the question has a usable answer (text: non-empty trimmed;
    /// checkbox: at least one selection; radio: an option chosen).
    private func isAnswered(_ q: ServerDocQuestion) -> Bool {
        guard let raw = note.questionAnswers[q.id] else { return false }
        if q.type == "checkbox" {
            return !VisitQuestionCard.decodeCheckboxSelections(raw).isEmpty
        }
        return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var unansweredRequiredQuestions: [ServerDocQuestion] {
        serverQuestions.filter { $0.required && !isAnswered($0) }
    }

    private var noteComplete: Bool {
        // Every required server-configured question must be answered
        guard unansweredRequiredQuestions.isEmpty else { return false }
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

                    // Server-configured visit questions (dynamic — replaces the
                    // old hardcoded transport review question)
                    if !serverQuestions.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Visit Questions", systemImage: "checklist")
                                    .font(.headline)
                                Spacer()
                            }
                            ForEach(serverQuestions) { question in
                                VisitQuestionCard(
                                    question: question,
                                    answer: questionAnswerBinding(for: question)
                                )
                            }
                        }
                        .cardStyle()
                    }

                    DocSection(title: "Additional Comments", icon: "text.alignleft", expanded: $expanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Optional")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            DocTextEditor(text: $note.additionalComments, placeholder: "Anything else worth noting about this visit…", minHeight: 100)
                        }
                    }

                    if !unansweredRequiredQuestions.isEmpty {
                        Label("Answer the required visit question\(unansweredRequiredQuestions.count == 1 ? "" : "s") before submitting (\(unansweredRequiredQuestions.count) remaining).", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundColor(Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                // Server-configured visit questions (pre-filtered + pre-sorted)
                serverQuestions = template.questions ?? []

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
                    healthNotes: health?.healthNotes ?? "",
                    communicationUnderstood: health?.communicationUnderstood ?? "",
                    adaptiveEquipment: health?.adaptiveEquipment ?? "",
                    supervisionLevel: health?.supervisionLevel ?? ""
                )

                // Capture AI Assist feature flag
                aiAssistEnabled = template.aiAssistEnabled ?? false

                // Load existing structured note if present and draft is empty
                if let existing = template.existingNote, note.additionalComments.isEmpty && note.outcomeEntries.isEmpty {
                    loadExistingNote(existing)
                }

                // Apply server-side defaults to any question that still has no
                // answer (draft answers and previously submitted answers win).
                for q in serverQuestions where note.questionAnswers[q.id] == nil {
                    if let dv = q.defaultValue, !dv.isEmpty {
                        note.questionAnswers[q.id] = dv
                    }
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

        // Load previously submitted question answers (prefill wins over defaults)
        if let answers = existing.questionAnswers {
            for qa in answers where note.questionAnswers[qa.questionId] == nil {
                note.questionAnswers[qa.questionId] = qa.answer
            }
        }

        // Load legacy transport review answer (old records predate dynamic
        // questions) — map it onto the seeded transport question when present.
        if let transportReview = existing.transportReviewedGoals {
            note.transportReviewedGoals = transportReview
            if let tq = transportQuestion, note.questionAnswers[tq.id] == nil {
                note.questionAnswers[tq.id] = transportReview ? "Yes" : "No"
            }
        }

        // Load per-outcome entries
        if let entries = existing.outcomes {
            for entry in entries {
                // Match by server outcome ID
                if let outcomeId = entry.outcomeId,
                   let match = serverOutcomes.first(where: { $0.serverId == outcomeId }) {
                    var oe = OutcomeEntry()
                    // v0.4.152 shape first; legacy promptLevel/frequency only
                    // fills in when the new fields are absent (old notes).
                    oe.prompts = entry.prompts
                    oe.successes = entry.successes
                    oe.opportunities = entry.opportunities
                    oe.na = entry.na ?? false
                    oe.applyLegacy(promptLevel: entry.promptLevel, frequency: entry.frequency)
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
            oe.prompts = draftOutcome.prompts
            oe.successes = draftOutcome.successes
            oe.opportunities = draftOutcome.opportunities
            oe.na = draftOutcome.na ?? false
            oe.applyLegacy(promptLevel: draftOutcome.promptLevel, frequency: draftOutcome.frequency)
            oe.narrative = narrative
            note.outcomeEntries[match.localId] = oe
            draftedIds.insert(match.localId)
        }

        // Apply additional comments if present
        if let comments = draft.additionalComments, !comments.isEmpty {
            note.additionalComments = comments
        }

        // Apply transport review if present — also answer the dynamic
        // transport question so the form reflects it.
        if let transportReview = draft.transportReviewedGoals {
            note.transportReviewedGoals = transportReview
            if let tq = transportQuestion {
                note.questionAnswers[tq.id] = transportReview ? "Yes" : "No"
            }
        }

        // Visit question answers from the draft (build 25 / server v0.4.212 —
        // Nick: "I would like visit questions in BOTH EVV and the desktop to
        // reflect what is generated from AI"). The server only returns answers
        // it validated against the question's own options, and the wire shape
        // is exactly what questionAnswers already stores (checkbox = JSON-encoded
        // array string), so this is a straight assignment. Questions the AI
        // didn't answer are LEFT ALONE — never cleared.
        for qa in draft.visitQuestions ?? [] {
            guard let qid = qa.questionId, let answer = qa.answer,
                  serverQuestions.contains(where: { $0.id == qid }) else { continue }
            note.questionAnswers[qid] = answer
            // Keep the legacy transport bool in sync when the AI answered the
            // transport question directly.
            if let tq = transportQuestion, tq.id == qid {
                note.transportReviewedGoals = (answer == "Yes")
            }
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
                oe.prompts = voiceOutcome.prompts
                oe.successes = voiceOutcome.successes
                oe.opportunities = voiceOutcome.opportunities
                oe.na = voiceOutcome.na ?? false
                oe.applyLegacy(promptLevel: voiceOutcome.promptLevel, frequency: voiceOutcome.frequency)
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

        // Apply transport review if present — also answer the dynamic
        // transport question so the form reflects it.
        if let transportReview = response.transportReviewedGoals {
            note.transportReviewedGoals = transportReview
            if let tq = transportQuestion {
                note.questionAnswers[tq.id] = transportReview ? "Yes" : "No"
            }
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
            if !draft.outcomeEntries.isEmpty || !draft.additionalComments.isEmpty || !draft.questionAnswers.isEmpty {
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
                "na": entry.na,
                "narrative": entry.narrative
            ]
            // nil means "not measured" — omit the key rather than sending 0,
            // which the server reads as an explicit zero measurement.
            if let v = entry.prompts { dict["prompts"] = v }
            if let v = entry.successes { dict["successes"] = v }
            if let v = entry.opportunities { dict["opportunities"] = v }
            return dict
        }

        // Build question answers payload — wire format: answer is always a
        // String (checkbox answers are JSON-encoded array strings).
        let questionPayload: [[String: Any]] = serverQuestions.compactMap { q in
            guard let raw = note.questionAnswers[q.id],
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return ["questionId": q.id, "answer": raw]
        }

        // Legacy compat: when the seeded transport question is present and
        // answered Yes/No, also send the old transportReviewedGoals bool
        // (server maps both ways; belt-and-suspenders).
        var legacyTransport: Bool?
        if let tq = transportQuestion, let raw = note.questionAnswers[tq.id] {
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "yes": legacyTransport = true
            case "no": legacyTransport = false
            default: break
            }
        }

        do {
            let response = try await APIClient.shared.submitDocumentation(
                visitId: svid,
                outcomes: outcomePayload,
                additionalComments: note.additionalComments,
                questionAnswers: questionPayload,
                transportReviewedGoals: legacyTransport,
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

    private func questionAnswerBinding(for question: ServerDocQuestion) -> Binding<String?> {
        Binding(
            get: { note.questionAnswers[question.id] },
            set: { newValue in
                if let v = newValue {
                    note.questionAnswers[question.id] = v
                } else {
                    note.questionAnswers.removeValue(forKey: question.id)
                }
            }
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
    let communicationUnderstood: String
    let adaptiveEquipment: String
    let supervisionLevel: String
}

// MARK: - Dynamic visit question card

/// Renders one server-configured visit question.
/// - radio    → single-select option buttons
/// - checkbox → multi-select option rows (answer stored as a JSON-encoded
///              array string — the wire format)
/// - text     → free-text editor
struct VisitQuestionCard: View {
    let question: ServerDocQuestion
    /// Wire-format answer: plain string (radio/text) or JSON-array string (checkbox).
    @Binding var answer: String?

    // MARK: Checkbox wire-format codec

    static func decodeCheckboxSelections(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    static func encodeCheckboxSelections(_ selections: [String]) -> String {
        guard let data = try? JSONEncoder().encode(selections),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    private var isAnswered: Bool {
        guard let raw = answer else { return false }
        if question.type == "checkbox" {
            return !Self.decodeCheckboxSelections(raw).isEmpty
        }
        return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Short option sets render side by side (like the old Yes/No transport
    /// question); longer ones stack vertically.
    private var horizontalOptions: Bool {
        question.options.count <= 3 && question.options.allSatisfy { $0.count <= 10 }
    }

    private func optionColor(_ option: String) -> Color {
        switch option.lowercased() {
        case "yes": return Theme.success
        case "no": return Theme.danger
        default: return Theme.primary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 4) {
                Text(question.text)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if question.required {
                    Text("*")
                        .foregroundColor(Theme.danger)
                }
                Spacer(minLength: 0)
            }

            switch question.type {
            case "radio":
                radioOptions
            case "checkbox":
                checkboxOptions
            default:
                DocTextEditor(
                    text: Binding(
                        get: { answer ?? "" },
                        set: { answer = $0 }
                    ),
                    placeholder: "Your answer…",
                    minHeight: 80
                )
            }

            if question.required && !isAnswered {
                Text(requiredHint)
                    .font(.caption)
                    .foregroundColor(Theme.danger)
            }
        }
        .padding(.vertical, 4)
    }

    private var requiredHint: String {
        switch question.type {
        case "radio": return "Required — select an option"
        case "checkbox": return "Required — select at least one option"
        default: return "Required — enter an answer"
        }
    }

    // MARK: Radio (single-select)

    @ViewBuilder
    private var radioOptions: some View {
        if horizontalOptions {
            HStack(spacing: 12) {
                ForEach(question.options, id: \.self) { option in
                    radioButton(option)
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(question.options, id: \.self) { option in
                    radioButton(option)
                }
            }
        }
    }

    private func radioButton(_ option: String) -> some View {
        let selected = answer == option
        let color = optionColor(option)
        return Button(action: { answer = option }) {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? color : .secondary)
                Text(option)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(selected ? color : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !horizontalOptions { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: horizontalOptions ? nil : .infinity, alignment: .leading)
            .background(selected ? color.opacity(0.10) : Color(UIColor.tertiarySystemFill))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? color.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Checkbox (multi-select)

    private var checkboxOptions: some View {
        let selections = Set(Self.decodeCheckboxSelections(answer ?? ""))
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(question.options, id: \.self) { option in
                let selected = selections.contains(option)
                Button(action: { toggleCheckbox(option) }) {
                    HStack(spacing: 6) {
                        Image(systemName: selected ? "checkmark.square.fill" : "square")
                            .foregroundColor(selected ? Theme.primary : .secondary)
                        Text(option)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selected ? Theme.primary.opacity(0.08) : Color(UIColor.tertiarySystemFill))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selected ? Theme.primary.opacity(0.35) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleCheckbox(_ option: String) {
        var selections = Self.decodeCheckboxSelections(answer ?? "")
        if let idx = selections.firstIndex(of: option) {
            selections.remove(at: idx)
        } else {
            selections.append(option)
        }
        // Keep the wire ordering stable: match the question's option order.
        selections.sort { a, b in
            (question.options.firstIndex(of: a) ?? .max) < (question.options.firstIndex(of: b) ?? .max)
        }
        answer = Self.encodeCheckboxSelections(selections)
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

            // Supervision Level sits directly alongside allergies — both are
            // the critical at-a-glance safety facts for the visit.
            if !client.supervisionLevel.isEmpty {
                singleInfoBlock(title: "Supervision Level", icon: "eye.fill", color: Theme.warning, text: client.supervisionLevel)
            }

            infoBlock(title: "Safety Alerts", icon: "exclamationmark.triangle.fill", color: Theme.warning, items: client.safetyAlerts)
            infoBlock(title: "Protocols", icon: "list.clipboard.fill", color: Theme.primary, items: client.protocols)

            if !client.communicationUnderstood.isEmpty {
                singleInfoBlock(title: "Communication", icon: "bubble.left.and.bubble.right.fill", color: Theme.primary, text: client.communicationUnderstood)
            }
            if !client.adaptiveEquipment.isEmpty {
                singleInfoBlock(title: "Adaptive Equipment", icon: "figure.roll", color: Theme.success, text: client.adaptiveEquipment)
            }

            if client.allergies.isEmpty && client.safetyAlerts.isEmpty && client.protocols.isEmpty
                && client.communicationUnderstood.isEmpty && client.adaptiveEquipment.isEmpty && client.supervisionLevel.isEmpty {
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

    private func singleInfoBlock(title: String, icon: String, color: Color, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundColor(color)
            Text(text).font(.subheadline)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .cornerRadius(10)
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
