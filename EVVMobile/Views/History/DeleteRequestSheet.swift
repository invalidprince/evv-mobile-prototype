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
    /// Build 102, review warn 3 — set when a delete failed in a way that
    /// could still have landed server-side. The re-sync runs on DISMISS, not
    /// on the failure: refreshServerShifts() republishes todayVisits, and if
    /// that drops the row the Today card unmounts and takes this sheet (and
    /// the unread error) with it.
    @State private var needsReconcile = false

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
            return "Still running: deleted right away, no supervisor approval, and the shift goes back to not started. Already clocked out: a delete request goes to your supervisor."
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
        .onDisappear {
            // Review warn 3 — reconcile a possibly-landed delete only after
            // this sheet is gone, so republishing todayVisits cannot tear it
            // down mid-read.
            if needsReconcile {
                needsReconcile = false
                Task { await appState.reconcileAfterFailedDelete() }
            }
        }
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
                    case .failed(let err, let uncertain):
                        // Review warn 3 — hedge ONLY when the outcome really
                        // is unknown. After a 403/409/billed refusal the
                        // server did not touch the visit, and "you do not
                        // have permission … it may already be deleted" is a
                        // lie. The reconcile is deferred to dismiss so this
                        // text cannot be torn down before it is read.
                        errorMessage = (isInProgress && uncertain)
                            ? err + " Check Today — the visit may already be deleted."
                            : err
                        needsReconcile = uncertain
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
