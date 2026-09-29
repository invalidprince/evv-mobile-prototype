import SwiftUI

struct DeleteRequestSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let visit: Visit

    @State private var reason = "Duplicate entry"
    @State private var comment = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    /// Build 102 — the server's own delete message, shown verbatim when the
    /// visit was deleted on the spot rather than queued for a supervisor.
    @State private var deletedMessage: String?

    /// Build 102 — a RUNNING visit is deleted immediately, not requested
    /// (Nick, 2026-09-23), so this sheet's copy has to change with it.
    /// Review nit: uses the SHARED Visit.isRunning predicate rather than a
    /// fourth local variant, so History, the Today card and this sheet can
    /// never disagree about which branch the server will take.
    private var isInProgress: Bool { visit.isRunning }

    private let reasons = [
        "Duplicate entry",
        "Wrong client selected",
        "Visit didn't happen",
        "Clocked in by mistake",
        "Wrong service type",
        "Other"
    ]

    private var dateText: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: visit.scheduledStart)
    }

    /// Build 102 — the honest version of each path.
    ///
    /// Review warn 2: the phone does NOT decide immediate-vs-request — the
    /// server does (visit-core.requestVisitDelete, on actual_out IS NULL).
    /// The phone's isRunning can be stale (clocked out on another device
    /// since the last refresh) and the server can be an older build with no
    /// immediate path at all, so the pre-submit copy promises only what is
    /// actually guaranteed and names both outcomes. The POST-submit alert is
    /// where the definite answer is shown, because by then the server has
    /// spoken.
    private var footerText: String {
        if isInProgress {
            return "If this visit is still running, it is deleted right away with no supervisor approval — a scheduled shift goes back to not started so you can clock in again, and a visit you started without a shift is cancelled. If it has already been clocked out, a delete request goes to your supervisor instead. Either way the note on it goes with the visit."
        }
        return "This sends a delete request to your supervisor for review. The visit stays on your record until it's approved."
    }

    /// Build 102 — deleting is an approval-class action, so it is ONLINE-ONLY,
    /// like every other request/approval in the app. It is deliberately NOT
    /// queued for offline replay: replaying a delete against a visit the
    /// server has already moved on from is how ghost rows get made (see the
    /// V-2044/V-2046 note in AppState.dropDeletedVisitLocally).
    private var canSubmit: Bool {
        appState.mode != .server || appState.effectivelyOnline
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Visit")) {
                    HStack {
                        AvatarView(name: visit.client.name, size: 36)
                        VStack(alignment: .leading) {
                            Text(visit.client.name).font(.headline)
                            Text("\(visit.serviceLabel) · \(dateText)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Reason for deletion")) {
                    Picker("Reason", selection: $reason) {
                        ForEach(reasons, id: \.self) { r in
                            Text(r).tag(r)
                        }
                    }
                }

                Section(header: Text("Comment")) {
                    // Build 102 — nobody reviews an in-progress delete, so
                    // don't tell the staff member to write for a supervisor.
                    TextField(isInProgress ? "Add details (kept on the record)…" : "Add details for your supervisor…",
                              text: $comment)
                }

                if let error = errorMessage {
                    Section {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Theme.danger)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(Theme.danger)
                        }
                    }
                }

                if !canSubmit {
                    Section {
                        HStack(spacing: 6) {
                            Image(systemName: "wifi.slash")
                                .foregroundColor(Theme.warning)
                            Text("Connect to the internet to delete this visit. Deletes are never queued offline.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .accessibilityIdentifier("delete.offlineNote")
                }

                Section(footer: Text(footerText)) {
                    Button(role: .destructive, action: submit) {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(isInProgress ? "Delete Visit" : "Submit Delete Request")
                                .frame(maxWidth: .infinity)
                                .font(.headline)
                        }
                    }
                    .disabled(isSubmitting || !canSubmit)
                    .accessibilityIdentifier("delete.submit")
                }
            }
            .navigationTitle(isInProgress ? "Delete Visit" : "Request Delete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(deletedMessage == nil ? "Delete request submitted" : "Visit deleted",
                   isPresented: $showSuccess) {
                Button("OK") {
                    // 🩸 REVIEW BLOCK (gate 1, round 1) — the local row is
                    // dropped HERE, not in AppState when the response lands.
                    // This sheet is presented from the CLOCKED IN card, and
                    // that card renders off activeVisit = todayVisits.first
                    // where .inProgress. Dropping the row first pulls the
                    // card out of the hierarchy, SwiftUI tears this sheet
                    // down with it, and the delete message Nick explicitly
                    // asked for is never seen. Order matters: show the
                    // message, wait for the acknowledgement, THEN clear the
                    // local state.
                    if let svid = visit.serverVisitId, deletedMessage != nil {
                        appState.dropDeletedVisitLocally(serverVisitId: svid)
                    }
                    dismiss()
                }
            } message: {
                // Build 102 — Nick's "show a delete message". When the server
                // deleted it outright, say that and say what happens to the
                // shift; only the request path mentions a supervisor.
                Text(deletedMessage ?? "Your supervisor will review and respond.")
            }
        }
        // Build 75: supervisor comment field.
        .keyboardDismissable()
    }

    private func submit() {
        if appState.mode == .server, let svid = visit.serverVisitId {
            isSubmitting = true
            errorMessage = nil

            let fullReason = comment.isEmpty ? reason : "\(reason): \(comment)"

            Task {
                let outcome = await appState.submitServerDeleteRequest(
                    visitId: visit.id,
                    serverVisitId: svid,
                    reason: fullReason
                )
                await MainActor.run {
                    isSubmitting = false
                    switch outcome {
                    case .failed(let err):
                        // Review warn 1 — AppState has already re-pulled
                        // today's shifts, so if the server did delete it and
                        // only the response was lost, Today is already
                        // correct. Say so instead of implying nothing
                        // happened.
                        errorMessage = isInProgress
                            ? err + " Check Today — the visit may already be deleted."
                            : err
                    case .deletedNow(let msg):
                        deletedMessage = msg
                        showSuccess = true
                    case .requested:
                        deletedMessage = nil
                        showSuccess = true
                    }
                }
            }
        } else {
            // Mock mode
            appState.requestDelete(visitId: visit.id)
            dismiss()
        }
    }
}
