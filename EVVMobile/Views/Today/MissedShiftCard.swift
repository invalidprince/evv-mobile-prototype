import SwiftUI

// MARK: - Missed shift — reason required (server v0.4.505, build 71)
//
// Todoist 6hWM5wChpj4rxVPH. Nick 2026-09-15: "Instead of hiding missed shift
// ONLY in the missed shifts, maybe we can display it in the visits. We can
// have a required 'Missed Shift Reason'. You can either request the shift to
// be created … or you can put in a reason it was missed. It should show up on
// todo list. Don't forget this should be on dashboard AND iOS."
//
// A scheduled shift of mine that was never started (no punch, no visit) from
// REASON_REQUIRED_FROM forward owes exactly one of two things:
//   1. "I worked this shift" — the EXISTING shift request, pre-populated from
//      the schedule and linked to it (RequestShiftSheet with a prefill →
//      POST /api/me/shift-requests + shiftId). Manager approval, same window
//      (shiftRequestMaxDays), straight into documentation. Only offered when
//      the server says `canRequest` (role flag + inside the window).
//   2. "It was missed" — a reason from the server's ONE vocabulary
//      (db.NOT_WORKED_REASONS; "Other" needs a comment) →
//      POST /api/me/missed-shifts/:shiftId/resolve.
// The row is DERIVED server-side and leaves the list on its own once either
// happens (a denied request brings it back). The card is ONLINE-ONLY — both
// paths need the server's state checks, so offline it is a passive notice,
// never a queued action (the RequestShiftSheet rule).

struct MissedShiftCard: View {
    let item: MissedShiftItem
    var isOffline: Bool = false
    let onResolve: () -> Void

    private var accent: Color { Theme.danger }

    static func whenText(_ item: MissedShiftItem) -> String {
        var s = item.date
        if let d = MissedShiftPrefill.parse(date: item.date, time: nil) {
            let f = DateFormatter()
            f.dateFormat = "EEE, MMM d"
            s = Calendar.current.isDateInYesterday(d) ? "yesterday" : f.string(from: d)
        }
        if let st = item.start, let en = item.end {
            s += ", \(st)–\(en)"
        } else if let st = item.start {
            s += ", \(st)"
        }
        return s
    }

    private var titleText: String {
        "Missed shift — \(item.clientName ?? "no individual"), \(Self.whenText(item))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundColor(accent)
                Text(titleText)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            if let svc = item.serviceName, !svc.isEmpty {
                Text(svc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text("No visit was recorded for this scheduled shift. Request it if you worked it, or record why it was missed.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button(action: onResolve) {
                Label("Resolve", systemImage: "checkmark.circle")
            }
            .buttonStyle(PrimaryButtonStyle(color: isOffline ? .gray : accent))
            .disabled(isOffline)
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
        .accessibilityIdentifier("missedShiftCard-\(item.shiftId)")
    }
}

// MARK: - Resolve sheet (the two paths)

/// The whole missed-shift flow lives in this one sheet so Today and the Work
/// tab present it identically: choose a path → either the reason picker
/// (inline) or the pre-filled RequestShiftSheet (nested sheet) → and for a
/// request, straight into DocumentationView for the pending visit. The parent
/// only needs `.sheet(item:)` + a refresh in `onDismiss`.
struct MissedShiftResolveSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let item: MissedShiftItem

    private enum Path { case choose, reason }
    @State private var path: Path = .choose
    @State private var selectedReason: String = ""
    @State private var comment: String = ""
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var saved = false

    // "I worked this shift" chain — the HistoryView handoff pattern: the
    // request sheet hands back the pending visit, and DocumentationView is
    // presented only after that sheet has finished dismissing.
    @State private var showRequest = false
    @State private var requestedDocVisit: Visit?
    @State private var docVisit: Visit?

    private var online: Bool { appState.effectivelyOnline }

    private var reasons: [String] {
        appState.missedShiftReasons.isEmpty
            ? ["Staff no-show", "Staff called off / sick", "Shift cancelled late", "Individual unavailable / declined", "Other"]
            : appState.missedShiftReasons
    }

    /// Mirrors db.resolveMissedShiftReason: "Other" requires a comment.
    private var isOther: Bool { selectedReason.lowercased() == "other" }
    private var trimmedComment: String { comment.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        online && !isSubmitting && !selectedReason.isEmpty && (!isOther || !trimmedComment.isEmpty)
    }

    private var prefill: MissedShiftPrefill? { MissedShiftPrefill(item: item) }
    private var canRequest: Bool { item.offersRequest && prefill != nil }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.clientName ?? "No individual")
                            .font(.headline)
                        if let svc = item.serviceName, !svc.isEmpty {
                            Text(svc).font(.subheadline).foregroundColor(.secondary)
                        }
                        Text(MissedShiftCard.whenText(item))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                if !online {
                    Section {
                        Label("You're offline. Resolving a missed shift needs a connection — nothing here is queued.", systemImage: "wifi.slash")
                            .font(.subheadline)
                            .foregroundColor(Theme.danger)
                    }
                }

                if saved {
                    Section {
                        Label("Reason recorded. This shift stays on the Missed visits list for your manager to acknowledge.", systemImage: "checkmark.circle.fill")
                            .foregroundColor(Theme.success)
                    }
                } else {
                    switch path {
                    case .choose: chooseSection
                    case .reason: reasonSection
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
            .navigationTitle("Missed Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showRequest, onDismiss: {
            if let v = requestedDocVisit {
                requestedDocVisit = nil
                docVisit = v
            }
        }) {
            RequestShiftSheet(prefill: prefill) { visit in
                requestedDocVisit = visit
                showRequest = false
            }
        }
        .sheet(item: $docVisit, onDismiss: {
            // The request is committed and documented (or abandoned mid-way —
            // the pending visit still exists and shows in History). Either way
            // this row no longer owes a reason; close the whole flow.
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
                footer: Text(canRequest
                             ? "Requesting the shift follows the normal approval process — your manager approves it and you document it now."
                             : (item.offersRequest
                                ? "This shift can't be requested from here."
                                : "This shift is outside your role's request window\(requestWindowText), so it can only take a reason."))) {
            if canRequest {
                Button {
                    submitError = nil
                    showRequest = true
                } label: {
                    Label("I worked this shift", systemImage: "square.and.pencil")
                }
                .disabled(!online)
            }
            Button {
                submitError = nil
                withAnimation { path = .reason }
            } label: {
                Label("It was missed", systemImage: "xmark.circle")
            }
            .disabled(!online)
        }
    }

    private var requestWindowText: String {
        guard let min = item.requestMinDate,
              let d = MissedShiftPrefill.parse(date: min, time: nil) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return " (from \(f.string(from: d)))"
    }

    // MARK: Reason path

    @ViewBuilder
    private var reasonSection: some View {
        Section(header: Text("Why was it missed? (required)"),
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
                .accessibilityIdentifier("missedShiftComment")
        }

        Section {
            Button(action: save) {
                if isSubmitting {
                    HStack {
                        ProgressView()
                        Text("Saving…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("Save reason", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(!canSave)
            Button("Back") {
                submitError = nil
                withAnimation { path = .choose }
            }
            .disabled(isSubmitting)
        }
    }

    private func save() {
        guard canSave else { return }
        isSubmitting = true
        submitError = nil
        Task {
            do {
                _ = try await APIClient.shared.resolveMissedShift(
                    shiftId: item.shiftId,
                    reason: selectedReason,
                    comment: trimmedComment.isEmpty ? nil : trimmedComment
                )
                await MainActor.run {
                    isSubmitting = false
                    saved = true
                    // Drop the row locally so the card is gone the moment the
                    // sheet closes; the next refresh is the server's word.
                    appState.missedShifts.removeAll { $0.shiftId == item.shiftId }
                }
                await appState.refreshMissedShifts()
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    let apiErr = error as? APIError ?? .networkError(error)
                    submitError = apiErr.errorDescription ?? "Could not record the reason."
                    // 409 = the row's state changed under us (a punch synced,
                    // a request is pending, or it was already recorded). The
                    // list is stale — refresh so the card reflects the server.
                    if case .conflict = apiErr {
                        Task { await appState.refreshMissedShifts() }
                    }
                }
            }
        }
    }
}
