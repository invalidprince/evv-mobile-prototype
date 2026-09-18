import SwiftUI

// MARK: - Missed DAY (📅) in History (server v0.4.569, build 76)
//
// Todoist 6hWwwJ8Jr64937GH. Nick, #evv 2026-09-17 20:22, with a History-tab
// screenshot: "Spec and add a card in development to show missed visits in iOS
// history with same action items as the dashboard (request form be created or
// just create if it's a manual service like lifesharing)". Then 20:41: a
// missed lifesharing day (Ray Varner) must ACTIVELY request a reason or the
// visit's creation — not sit passively on the Missed tab.
//
// 🔑 THE SERVER DECIDES THE ACTIONS. This file contains NO service-type list
//    and no knowledge of what "lifesharing" is. It renders what the payload's
//    `canCreateVisit` / `createMode` / `canRecordReason` flags say, which come
//    from the SAME builder the dashboard row uses
//    (evv-poc/daily-visit-resolve.actionsFor). That is the spec's explicit
//    requirement and the reason the two surfaces cannot drift.
//
// 🔑 A DAY, NOT A SHIFT. The row is keyed individual × service × date and
//    often has no shift at all — the obligation belongs to the AUTHORIZATION.
//    So this is deliberately NOT a `Visit` and not a `MissedShiftItem`; it
//    cannot be, since that type's `shiftId` is non-optional.
//
// ONLINE-ONLY, like MissedShiftCard: both paths need the server's state
// checks (a visit may have synced since the last refresh), so offline it is a
// passive notice and nothing is ever queued.

struct MissedDailyRow: View {
    let item: MissedDailyItem
    var isOffline: Bool = false
    let onResolve: () -> Void

    private var accent: Color { Theme.danger }

    static func whenText(_ item: MissedDailyItem) -> String {
        guard let d = MissedShiftPrefill.parse(date: item.date, time: nil) else { return item.date }
        if Calendar.current.isDateInYesterday(d) { return "yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: d)
    }

    /// What the row asks for, in the staff member's words. Driven entirely by
    /// the server's flags — never by the service code.
    private var askText: String {
        if item.offersCreate {
            return "No visit was entered for this day. Create it if the day was worked, or record why there was none."
        }
        if item.isDirectCreate {
            // Manual service, but create is withheld (outside the entry window).
            return item.createBlockedReason ?? "No visit was entered for this day. Record why there was none."
        }
        return "No visit was entered for this day. This service needs a manager-approved request, or record why there was none."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundColor(accent)
                Text("No visit — \(item.clientName ?? item.clientId), \(Self.whenText(item))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            if let svc = item.serviceName, !svc.isEmpty {
                Text(svc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(askText)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onResolve) {
                Label(item.offersCreate ? "Create visit / record reason" : "Record reason",
                      systemImage: "checkmark.circle")
            }
            .buttonStyle(PrimaryButtonStyle(color: isOffline ? .gray : accent))
            .disabled(isOffline || !(item.offersReason || item.offersCreate))
            if isOffline {
                Label("Connect to the internet to resolve", systemImage: "wifi.slash")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(accent.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accent.opacity(0.5), lineWidth: 1)
        )
        .cornerRadius(14)
        .accessibilityIdentifier("missedDailyRow-\(item.key)")
    }
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
    @State private var path: Path = .choose
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

        Section {
            Button(action: saveReason) {
                if isSubmitting {
                    HStack { ProgressView(); Text("Saving…") }.frame(maxWidth: .infinity)
                } else {
                    Label("Save reason", systemImage: "checkmark.circle").frame(maxWidth: .infinity)
                }
            }
            .disabled(!canSaveReason)
            Button("Back") {
                submitError = nil
                withAnimation { path = .choose }
            }
            .disabled(isSubmitting)
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

        Section {
            Button(action: createVisit) {
                if isSubmitting {
                    HStack { ProgressView(); Text("Creating…") }.frame(maxWidth: .infinity)
                } else {
                    Label("Create visit", systemImage: "plus.circle").frame(maxWidth: .infinity)
                }
            }
            .disabled(!canCreate)
            Button("Back") {
                submitError = nil
                withAnimation { path = .choose }
            }
            .disabled(isSubmitting)
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
