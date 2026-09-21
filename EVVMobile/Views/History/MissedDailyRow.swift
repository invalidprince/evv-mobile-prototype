import SwiftUI

// MARK: - Missed visits INLINE in History (build 77, Todoist 6hWwwJ8Jr64937GH)
//
// Build 76 rendered missed DAYS (📅) in their own "Missed" section bolted
// above the visit list. Nick, #evv 2026-09-21: "I want the missing visits to
// literally show in the history on iOS like it does web. Same format, just
// shows missed. in iOS it shows at the top in a different section, not with
// the same day headers, etc."
//
// So this file is now the HISTORY ROW for a missed item — the SAME layout as
// `ServerHistoryRow` (avatar · name · service | duration · times, a chips row,
// a text-button actions row, `.cardStyle()`), plus a 🚫/📅 MISSED chip. The
// row is interleaved into the day-grouped list by HistoryView, under the
// day's own header, exactly as the web's All Visits table co-sorts its
// `missed_shift` / `missed_daily` pseudo-rows with real visits (v0.4.546).
//
// Two kinds, mirroring the web table:
//   🚫 missed SHIFT — a scheduled shift of mine never started
//      (MissedShiftItem; actions: "I worked this shift" → request form,
//      "It was missed" → reason).
//   📅 missed DAY   — a "require daily visit" day with no visit of any kind
//      (MissedDailyItem; actions: "Create visit" (manual service, inside the
//      window) / "Record reason").
//
// 🔑 THE SERVER DECIDES THE ACTIONS. There is NO service-type list here and
//    no knowledge of what "lifesharing" is. `canRequest`, `canCreateVisit`,
//    `createMode`, `canRecordReason` come from the SAME builders the
//    dashboard rows use, so the two surfaces cannot drift.
//
// ONLINE-ONLY, like MissedShiftCard: both paths need the server's state
// checks, so offline the buttons are disabled and nothing is ever queued.

/// One missed item to render in History — either kind, one row format.
enum MissedHistoryEntry: Identifiable {
    case shift(MissedShiftItem)
    case daily(MissedDailyItem)

    var id: String {
        switch self {
        case .shift(let s): return "missed-shift-\(s.key)"
        case .daily(let d): return "missed-daily-\(d.key)"
        }
    }

    /// YYYY-MM-DD agency day the row belongs under.
    var date: String {
        switch self {
        case .shift(let s): return s.date
        case .daily(let d): return d.date
        }
    }

    var start: String? {
        switch self {
        case .shift(let s): return s.start
        case .daily(let d): return d.start
        }
    }

    var end: String? {
        switch self {
        case .shift(let s): return s.end
        case .daily(let d): return d.end
        }
    }

    var clientName: String {
        switch self {
        case .shift(let s): return s.clientName ?? s.clientId ?? "No individual"
        case .daily(let d): return d.clientName ?? d.clientId
        }
    }

    var serviceLabel: String {
        switch self {
        case .shift(let s): return s.serviceName ?? s.service ?? ""
        case .daily(let d): return d.serviceName ?? d.service ?? ""
        }
    }

    /// Same wording as the web chips: "🚫 Missed" (shift) / "📅 Missed" (day).
    var chipText: String {
        switch self {
        case .shift: return "🚫 MISSED"
        case .daily: return "📅 MISSED"
        }
    }
}

/// A missed item drawn in the History row format. Actions are text buttons
/// on the last line, like Add Note / Time Fix / Delete on a real visit.
struct MissedHistoryRow: View {
    let entry: MissedHistoryEntry
    var isOffline: Bool = false
    /// 🚫 shift → "I worked this shift" (the pre-filled request form).
    var onRequestShift: () -> Void = {}
    /// 🚫 shift → "It was missed" (reason).
    var onShiftReason: () -> Void = {}
    /// 📅 day → "Create visit" (manual-time service, inside the window).
    var onCreateVisit: () -> Void = {}
    /// 📅 day → "Record reason".
    var onDailyReason: () -> Void = {}

    private var accent: Color { Theme.danger }

    /// Scheduled span when a shift exists, else the web's "not scheduled".
    private var timeText: String {
        if let st = entry.start, let en = entry.end { return "\(st) – \(en)" }
        if let st = entry.start { return st }
        return "Not scheduled"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 12) {
                    AvatarView(name: entry.clientName, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.clientName).font(.headline)
                        if !entry.serviceLabel.isEmpty {
                            Text(entry.serviceLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    // No visit → no hours. The web prints "—" in Units.
                    Text("—")
                        .font(.headline)
                        .foregroundColor(accent)
                    Text(timeText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Status chips row — same slot the real rows use.
            HStack(spacing: 6) {
                StatusBadge(text: entry.chipText, color: accent)
                StatusBadge(text: "No visit recorded", color: .secondary)
                if case .daily(let d) = entry, !d.offersCreate, d.isDirectCreate,
                   let blocked = d.createBlockedReason, !blocked.isEmpty {
                    // Manual service whose entry window has closed — the
                    // server's words, shown as-is.
                    StatusBadge(text: blocked, color: Theme.warning)
                }
                Spacer()
            }

            // Action buttons — the dashboard's, driven by the server's flags.
            HStack(spacing: 16) {
                switch entry {
                case .shift(let s):
                    if s.offersRequest && MissedShiftPrefill(item: s) != nil {
                        Button(action: onRequestShift) {
                            Label("I worked this shift", systemImage: "square.and.pencil")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(isOffline ? .secondary : Theme.primary)
                        }
                        .disabled(isOffline)
                    }
                    Button(action: onShiftReason) {
                        Label("It was missed", systemImage: "xmark.circle")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(isOffline ? .secondary : accent)
                    }
                    .disabled(isOffline)
                case .daily(let d):
                    if d.offersCreate {
                        Button(action: onCreateVisit) {
                            Label("Create visit", systemImage: "plus.circle")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(isOffline ? .secondary : Theme.primary)
                        }
                        .disabled(isOffline)
                    }
                    if d.offersReason {
                        Button(action: onDailyReason) {
                            Label("Record reason", systemImage: "xmark.circle")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(isOffline ? .secondary : accent)
                        }
                        .disabled(isOffline)
                    }
                }
                Spacer()
            }

            if isOffline {
                Label("Connect to the internet to resolve", systemImage: "wifi.slash")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .cardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accent.opacity(0.45), lineWidth: 1)
        )
        .accessibilityIdentifier("missedHistoryRow-\(entry.id)")
    }
}

/// Build 76 helper kept for the resolve sheet's header. "yesterday" or
/// "EEE, MMM d" in the agency's calendar.
enum MissedDailyRow {
    static func whenText(_ item: MissedDailyItem) -> String {
        guard let d = MissedShiftPrefill.parse(date: item.date, time: nil) else { return item.date }
        if Calendar.current.isDateInYesterday(d) { return "yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: d)
    }
}

/// Which path the missed-DAY sheet opens on. Build 77: the History row has
/// one button per action, so each lands straight on its path; `.choose` is
/// the build-76 chooser and remains the default.
enum MissedDailyStart {
    case choose, reason, create
}

// MARK: - Resolve sheet (the two paths)

/// The whole missed-DAY flow in one sheet, so History (and any future caller)
/// presents it identically: choose a path → either the reason picker (inline,
/// the SAME vocabulary the missed-shift sheet uses) or a confirmation with the
/// day's times → create → History refreshes and the row clears itself because
/// a visit now exists.
struct MissedDailyResolveSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let item: MissedDailyItem
    /// Called after a successful create/reason so the parent can refresh.
    var onChanged: () -> Void = {}

    private enum Path { case choose, reason, create }
    @State private var path: Path
    @State private var selectedReason: String = ""
    @State private var comment: String = ""
    // Lifesharing days are entered as a full 12:00 AM → 12:00 AM span (Nick
    // 2026-08-18: an end at or before the start crosses midnight). Prefilled
    // with exactly that, and editable.
    @State private var startTime: String = "12:00 AM"
    @State private var endTime: String = "12:00 AM"
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var savedReason = false
    @State private var createdVisit: Visit?
    @State private var docVisit: Visit?

    init(item: MissedDailyItem, start: MissedDailyStart = .choose, onChanged: @escaping () -> Void = {}) {
        self.item = item
        self.onChanged = onChanged
        // Only land on a path the server actually offers; otherwise fall back
        // to the chooser, which explains why.
        let initial: Path
        switch start {
        case .create: initial = item.offersCreate ? .create : .choose
        case .reason: initial = item.offersReason ? .reason : .choose
        case .choose: initial = .choose
        }
        _path = State(initialValue: initial)
    }

    private var online: Bool { appState.effectivelyOnline }

    private var reasons: [String] {
        appState.missedShiftReasons.isEmpty
            ? ["Staff no-show", "Staff called off / sick", "Shift cancelled late", "Individual unavailable / declined", "Other"]
            : appState.missedShiftReasons
    }

    /// Mirrors db.resolveDailyVisitReason: "Other" requires a comment.
    private var isOther: Bool { selectedReason.lowercased() == "other" }
    private var trimmedComment: String { comment.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSaveReason: Bool {
        online && !isSubmitting && !selectedReason.isEmpty && (!isOther || !trimmedComment.isEmpty)
    }
    private var canCreate: Bool {
        online && !isSubmitting
            && !startTime.trimmingCharacters(in: .whitespaces).isEmpty
            && !endTime.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.clientName ?? item.clientId)
                            .font(.headline)
                        if let svc = item.serviceName, !svc.isEmpty {
                            Text(svc).font(.subheadline).foregroundColor(.secondary)
                        }
                        Text(MissedDailyRow.whenText(item))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                if !online {
                    Section {
                        Label("You're offline. Resolving a missed day needs a connection — nothing here is queued.", systemImage: "wifi.slash")
                            .font(.subheadline)
                            .foregroundColor(Theme.danger)
                    }
                }

                if savedReason {
                    Section {
                        Label("Reason recorded. This day stays on the Missed visits list for your manager to acknowledge.", systemImage: "checkmark.circle.fill")
                            .foregroundColor(Theme.success)
                    }
                } else {
                    switch path {
                    case .choose: chooseSection
                    case .reason: reasonSection
                    case .create: createSection
                    }
                }

                if let err = submitError {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundColor(Theme.danger)
                    }
                }
            }
            .navigationTitle("Missed Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(savedReason ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
        // Build 75's app-wide keyboard dismissal: this sheet has a comment
        // field and two time fields.
        .keyboardDismissable()
        .sheet(item: $docVisit, onDismiss: {
            // The visit exists either way (documented or abandoned mid-way),
            // so the day is no longer missing one. Close the whole flow.
            onChanged()
            dismiss()
        }) { visit in
            NavigationView {
                DocumentationView(visit: visit)
            }
        }
    }

    // MARK: Path picker

    @ViewBuilder
    private var chooseSection: some View {
        Section(header: Text("What happened?"),
                footer: Text(footerText)) {
            if item.offersCreate {
                Button {
                    submitError = nil
                    withAnimation { path = .create }
                } label: {
                    Label("Create the visit", systemImage: "square.and.pencil")
                }
                .disabled(!online)
            }
            if item.offersReason {
                Button {
                    submitError = nil
                    withAnimation { path = .reason }
                } label: {
                    Label("There was no visit", systemImage: "xmark.circle")
                }
                .disabled(!online)
            }
        }
    }

    private var footerText: String {
        if item.offersCreate {
            return "Creating the visit records your time for that day immediately, then opens its documentation."
        }
        if let blocked = item.createBlockedReason { return blocked }
        if !item.isDirectCreate {
            return "This service can't be hand-entered for a past day — it needs a manager-approved request. Record a reason here, then ask your manager to create the visit."
        }
        return "Recording a reason does not create a visit."
    }

    // MARK: Reason path

    @ViewBuilder
    private var reasonSection: some View {
        Section(header: Text("Why was there no visit? (required)"),
                footer: isOther && trimmedComment.isEmpty
                    ? Text("A comment is required for Other.").foregroundColor(Theme.danger)
                    : Text("The same reasons your manager sees on the Missed visits tab.")) {
            Picker("Reason", selection: $selectedReason) {
                Text("Select a reason").tag("")
                ForEach(reasons, id: \.self) { r in
                    Text(r).tag(r)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            TextField(isOther ? "Comment (required)" : "Comment (optional)", text: $comment)
                .accessibilityIdentifier("missedDailyComment")
        }

        // Bottom actions: one centered full-width primary row over one
        // centered secondary row, the same shape TimeFixSheet /
        // RequestShiftSheet use for their Form-sheet actions. Both rows
        // share the same centre line, and the inset row separator (which
        // rendered as a stray hairline beside the checkmark) is hidden.
        // Nick, #evv 2026-09-21: "UI for save reason looks funny (not
        // aligned with back)."
        Section {
            Button(action: saveReason) {
                Group {
                    if isSubmitting {
                        HStack { ProgressView(); Text("Saving…") }
                    } else {
                        Label("Save reason", systemImage: "checkmark.circle")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .disabled(!canSaveReason)
            .listRowSeparator(.hidden)
            Button {
                submitError = nil
                withAnimation { path = .choose }
            } label: {
                Text("Back").frame(maxWidth: .infinity)
            }
            .disabled(isSubmitting)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: Create path

    @ViewBuilder
    private var createSection: some View {
        Section(header: Text("Times worked on \(MissedDailyRow.whenText(item))"),
                footer: Text("This service does not clock in or out, so enter the times by hand. An end time at or before the start crosses midnight — 12:00 AM to 12:00 AM is a full day.")) {
            TextField("Start time", text: $startTime)
                .accessibilityIdentifier("missedDailyStart")
            TextField("End time", text: $endTime)
                .accessibilityIdentifier("missedDailyEnd")
        }

        // Same centered primary-over-secondary action rows as reasonSection.
        Section {
            Button(action: createVisit) {
                Group {
                    if isSubmitting {
                        HStack { ProgressView(); Text("Creating…") }
                    } else {
                        Label("Create visit", systemImage: "plus.circle")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .disabled(!canCreate)
            .listRowSeparator(.hidden)
            Button {
                submitError = nil
                withAnimation { path = .choose }
            } label: {
                Text("Back").frame(maxWidth: .infinity)
            }
            .disabled(isSubmitting)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: Actions

    private func saveReason() {
        guard canSaveReason, let service = item.service else { return }
        isSubmitting = true
        submitError = nil
        Task {
            do {
                _ = try await APIClient.shared.resolveMissedDaily(
                    clientId: item.clientId, service: service, date: item.date,
                    reason: selectedReason,
                    comment: trimmedComment.isEmpty ? nil : trimmedComment
                )
                await MainActor.run {
                    isSubmitting = false
                    savedReason = true
                    // Drop it locally so the row is gone the moment the sheet
                    // closes; the next refresh is the server's word.
                    appState.missedDaily.removeAll { $0.key == item.key }
                }
                await appState.refreshMissedShifts()
                await MainActor.run { onChanged() }
            } catch {
                await MainActor.run { handle(error, fallback: "Could not record the reason.") }
            }
        }
    }

    private func createVisit() {
        guard canCreate, let service = item.service else { return }
        isSubmitting = true
        submitError = nil
        Task {
            do {
                // The EXISTING manual-time unscheduled path — same op the
                // Today tab uses. The server re-validates manual-time-only,
                // individual visibility and the backdate window.
                let resp = try await APIClient.shared.createUnscheduledVisit(
                    clientIds: [item.clientId], service: service,
                    startTime: startTime.trimmingCharacters(in: .whitespaces),
                    endTime: endTime.trimmingCharacters(in: .whitespaces),
                    date: item.date
                )
                await MainActor.run {
                    isSubmitting = false
                    appState.missedDaily.removeAll { $0.key == item.key }
                }
                await appState.refreshHistory()
                await appState.refreshMissedShifts()
                // Hand straight into documentation when the server gave us a
                // visit to document — the RequestShiftSheet handoff pattern.
                await MainActor.run {
                    if let v = appState.historyVisits.first(where: { $0.serverVisitId == resp.visit.id }) {
                        docVisit = v
                    } else {
                        onChanged()
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run { handle(error, fallback: "Could not create the visit.") }
            }
        }
    }

    private func handle(_ error: Error, fallback: String) {
        isSubmitting = false
        let apiErr = error as? APIError ?? .networkError(error)
        submitError = apiErr.errorDescription ?? fallback
        // 409 = the day's state changed under us (a visit synced, or the
        // reason was already recorded). The list is stale — refresh.
        if case .conflict = apiErr {
            Task { await appState.refreshMissedShifts() }
        }
    }
}
