import SwiftUI

// MARK: - Correction sheet (build 72 / server v0.4.533)
// eMAR CORRECTIONS from the phone (Todoist 6hWcVX84mgjMCvMH). Nick: "If
// someone forgot to record, in the desktop, you can make a correction. Allow
// corrections from iOS as well. Correction reason is required, and you have to
// put in the time you administered. HOWEVER, I don't want the eMAR displaying
// the correction reason. That's for our internal processes only."
//
// Server contract — POST /api/emar/administrations/:id/correct
//   { action: given|refused|held|missed, notes: <reason, required>,
//     given_at: <ISO-8601 with offset, required iff action == given> }
//   200 → the slot now shows the corrected record (a NEW row linked to the
//         old one; the original stays in the audit chain, superseded).
//   400 → validation (reason blank, time missing / future / off the dose's
//         date) — the server's prose is shown verbatim under the form.
//   403 → not allowed (role has no flag, or the dose is outside the role's
//         hours window — 48h for DSP / Lifesharing Provider by default).
//         The sheet shows why and offers only Cancel; the list is refreshed
//         so the button disappears.
//   409 → the record changed under us (already corrected / live pending) —
//         refresh and dismiss with a notice.
//
// ⚠️ ONLINE-ONLY, NEVER queued (same rule as recording): a replayed correction
// against a slot whose state moved is exactly what the 409s exist to refuse.
//
// ⚠️ THE REASON IS INTERNAL. It is sent once, lands in the server's audit log,
// and is never returned in any payload or rendered on any MAR surface — this
// sheet says so under the field so staff write it as an internal note.
struct CorrectAdministrationSheet: View {
    let med: DueMedication
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var action = "given"
    @State private var givenAt: Date = Date()
    @State private var reason = ""
    /// build 74 / server v0.4.552 — "Can record eMAR for others": empty =
    /// myself; a staff id = the correction is attributed to that staff member
    /// (their initials on the MAR; I stay the audit actor). The picker only
    /// renders when the server sent choices (canRecordForOthers).
    @State private var onBehalfStaffId = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    /// Set on a 403 — the server's own sentence about why (role / hours window).
    @State private var forbidden: String?
    /// Set on a 409 — the record moved under us; list refreshed.
    @State private var conflict: String?

    /// The four correction outcomes the server accepts (emar-core
    /// CORRECTION_ACTIONS). "Missed" is legal HERE (and only here): it is the
    /// only truthful repair of a false "given".
    private let actions: [(id: String, label: String, icon: String)] = [
        ("given", "Given", "checkmark.circle.fill"),
        ("refused", "Refused", "hand.raised.fill"),
        ("held", "Held", "pause.circle.fill"),
        ("missed", "Missed", "xmark.circle.fill"),
    ]

    private var online: Bool { appState.effectivelyOnline }
    private var needsTime: Bool { action == "given" }
    private var trimmedReason: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var terminal: Bool { forbidden != nil || conflict != nil }
    private var canSubmit: Bool {
        !isSubmitting && online && !terminal && !trimmedReason.isEmpty
            && (!needsTime || givenAt <= Date())
    }

    /// Agency-clock display for the picker + header (the MAR is in agency time).
    private static let agencyZone = TimeZone(identifier: "America/New_York") ?? .current

    var body: some View {
        NavigationView {
            Form {
                headerSection
                if !terminal {
                    outcomeSection
                    if needsTime { timeSection }
                    reasonSection
                    if !appState.medOnBehalfStaff.isEmpty { onBehalfSection }
                }
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.subheadline)
                            .foregroundColor(Theme.danger)
                    }
                }
                if !terminal { submitSection }
            }
            .environment(\.timeZone, Self.agencyZone)
            .navigationTitle("Correct Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(terminal ? "Close" : "Cancel") { dismiss() }
                }
            }
            .onAppear {
                // Default the administered time to what the CURRENT record says
                // (build 85: a given row's own administered time — a
                // re-correction starts from the truth, not from the slot), else
                // the dose's SCHEDULED time on its date (agency clock); either
                // way capped at now.
                if let cur = med.givenAtInstant, cur <= Date() {
                    givenAt = cur
                } else if let sched = med.scheduledInstant, sched <= Date() {
                    givenAt = sched
                } else {
                    givenAt = Date()
                }
            }
            .alert("Record corrected", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("The record now shows \(action). The original entry stays in the audit chain.")
            }
        }
        // Build 75: eMAR correction reason / time fields.
        .keyboardDismissable()
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(med.medName)
                    .font(.headline)
                Text(med.clientName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    if let dl = med.dateLabel {
                        Text(dl).font(.caption).foregroundColor(.secondary)
                    }
                    if let label = med.dueTimeLabel {
                        Label("Due \(label)", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("currently \(med.status)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    // build 85 — what the CURRENT record says the administered
                    // time is, so a re-correction starts from the truth.
                    if med.status == "given", let g = med.givenAtLabel, !g.isEmpty {
                        Text("at \(g)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
                if let why = forbidden {
                    Label(why, systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundColor(Theme.danger)
                        .padding(.top, 4)
                } else if let why = conflict {
                    Label("This record changed — the list has been refreshed. \(why)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(Theme.warning)
                        .padding(.top, 4)
                } else {
                    Text("A correction creates a new record linked to this one — the original stays in the audit chain.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                if !online {
                    Label("You're offline — connect to the internet to record a correction. Corrections are never queued.", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundColor(Theme.danger)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var outcomeSection: some View {
        Section(header: Text("What actually happened")) {
            ForEach(actions, id: \.id) { a in
                Button {
                    action = a.id
                } label: {
                    HStack {
                        Image(systemName: a.icon)
                            .foregroundColor(a.id == "given" ? Theme.success : (a.id == "missed" ? Theme.danger : Theme.warning))
                        Text(a.label)
                            .foregroundColor(.primary)
                        Spacer()
                        if action == a.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(Theme.primary)
                        }
                    }
                }
            }
        }
    }

    private var timeSection: some View {
        Section(
            header: Text("Time administered (required)"),
            footer: Text("The actual time the medication was given, in agency time — this is what the MAR will show, not the time you submit this. It cannot be in the future or off the dose's date.")
        ) {
            DatePicker(
                "Given at",
                selection: $givenAt,
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("emar-correct-given-at")
        }
    }

    private var reasonSection: some View {
        Section(
            header: Text("Correction reason (required)"),
            footer: Text("Internal use only — written to the audit log, never shown on the MAR.")
        ) {
            MultilineTextBox(placeholder: "Why is this record being corrected?", text: $reason)
                .accessibilityIdentifier("emar-correct-reason")
        }
    }

    /// build 74 — staff picker for "Can record eMAR for others" (Lifesharing
    /// Manager by default). Nick: "if it's past 48 hours and Kayla Kline
    /// absolutely knows the medication was given, she can go record it on
    /// behalf of another staff. Just keep the same process and give the option
    /// to select a staff in a staff dropdown."
    private var onBehalfSection: some View {
        Section(
            header: Text("Recorded on behalf of"),
            footer: Text("Pick the staff member who administered the medication — their initials go on the MAR. You stay on record in the audit log as the person who entered the correction.")
        ) {
            Picker("Staff member", selection: $onBehalfStaffId) {
                Text("Myself").tag("")
                ForEach(appState.medOnBehalfStaff) { s in
                    Text("\(s.name) (\(s.id))").tag(s.id)
                }
            }
            .accessibilityIdentifier("emar-correct-on-behalf")
        }
    }

    private var submitSection: some View {
        Section {
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    Spacer()
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Apply correction — \(actions.first { $0.id == action }?.label ?? action)")
                            .font(.headline)
                    }
                    Spacer()
                }
            }
            .disabled(!canSubmit)
        }
    }

    private func submit() async {
        guard online else {
            errorMessage = "You're offline. Corrections are online-only — reconnect and try again."
            return
        }
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await APIClient.shared.correctMedAdministration(
                id: med.id,
                action: action,
                notes: trimmedReason,
                givenAt: needsTime ? givenAt : nil,
                onBehalfStaffId: onBehalfStaffId.isEmpty ? nil : onBehalfStaffId
            )
            await appState.refreshDueMedications()
            isSubmitting = false
            showSuccess = true
        } catch {
            isSubmitting = false
            let apiErr = error as? APIError
            if case .conflict(let why)? = apiErr {
                // The record moved under us — never retry, refresh instead.
                conflict = why
                await appState.refreshDueMedications()
            } else if case .forbidden(let why)? = apiErr {
                // Not allowed (any more): show the server's reason; refreshing
                // drops the button the list drew a moment ago.
                forbidden = why
                await appState.refreshDueMedications()
            } else if case .responseUnreadable? = apiErr {
                // 200 with a body we could not parse = COMMITTED.
                await appState.refreshDueMedications()
                showSuccess = true
            } else {
                errorMessage = apiErr?.localizedDescription ?? error.localizedDescription
            }
        }
    }
}
