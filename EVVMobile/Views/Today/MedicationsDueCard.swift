import SwiftUI

// MARK: - Medications Due card (build 33 / server v0.4.295)
// eMAR on the Today tab: due administrations + PRN meds for eMAR-enabled
// individuals on today's shifts (server payload = the same dueMedsForStaff
// scoping the web My Day renders — GET /api/me/medications).
//
// ⚠️ ONLINE-ONLY — deliberate, per Nick 2026-08-26. Recording a medication
// must NEVER enter the offline queue: an administration stamped with its SYNC
// time instead of its ADMINISTRATION time is a 6400/6500 compliance problem,
// and a second device whose due list hasn't refreshed is a double-dose risk.
// Offline this card is read-only with a "Reconnect to record" banner. Do NOT
// change that. The clock-in/out punch queue is a separate, untouched system.
//
// 🔑 build 33 — the GIVE WINDOW (server v0.4.295: 1h before due → 1h after,
// auto-missed at +60). Builds ≤32 rendered a plain "Record" button on every
// unrecorded dose and staff only discovered the refusal on TAP — the server
// has always refused it with a clean 409, so nothing was ever mis-recorded,
// but the UI was lying about what was possible.
//
// ⚠️ THE CLIENT-SIDE HIDE IS A HINT, NOT THE CONTROL. `giveAllowed` &c. are
// server-computed hints; `emar-core.recordAdministration` is the gate. Two
// consequences that are deliberate here:
//   1. 🔒 build 44 / server v0.4.322 — NOTHING is recordable outside the
//      window any more. Nick (2026-08-28): "for future medications and past
//      missed ones, you should not be able to document refused or held. It
//      was missed, that's it." The server ships those rows `recordable:
//      false`, so the button vanishes; the window chip explains why. Missed
//      is final for staff — a manager corrects the record on the web.
//      (build 41 / server v0.4.315 — "Missed" is GONE as a manual outcome:
//      missed is AUTOMATIC.)
//   2. The sheet re-checks and surfaces the server's 409 prose verbatim,
//      because a dose can tip from open → closed while the sheet is open —
//      and since v0.4.322 that refusal is TERMINAL: every outcome is dropped
//      and the sheet can only be dismissed.
struct MedicationsDueCard: View {
    @EnvironmentObject var appState: AppState
    @State private var recordTarget: DueMedication?
    @State private var prnTarget: PrnMedication?

    private var online: Bool { appState.effectivelyOnline }
    private var outstanding: [DueMedication] {
        appState.dueMedications.filter { $0.recordable }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("💊")
                Text("Medications Due")
                    .font(.headline)
                Spacer()
                if !outstanding.isEmpty {
                    Text("\(outstanding.count) outstanding")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.warning.opacity(0.18))
                        .foregroundColor(Theme.warning)
                        .cornerRadius(8)
                } else if !appState.dueMedications.isEmpty {
                    Text("All recorded")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.success.opacity(0.15))
                        .foregroundColor(Theme.success)
                        .cornerRadius(8)
                }
            }

            if !online {
                Label("You're offline — reconnect to record medications. Nothing here is ever queued.", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundColor(Theme.danger)
            }

            ForEach(appState.dueMedications) { med in
                medRow(med)
                if med.id != appState.dueMedications.last?.id || !appState.prnMedications.isEmpty {
                    Divider()
                }
            }

            if !appState.prnMedications.isEmpty {
                Text("PRN (as needed)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                ForEach(appState.prnMedications) { med in
                    Button {
                        prnTarget = med
                    } label: {
                        HStack {
                            Image(systemName: "pills")
                                .foregroundColor(online ? Theme.primary : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(med.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)
                                Text(med.clientName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!online)
                    .opacity(online ? 1 : 0.5)
                }
            }
        }
        .padding(14)
        .background(outstanding.isEmpty ? Theme.cardBackground : Theme.warning.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(outstanding.isEmpty ? Color.clear : Theme.warning.opacity(0.5), lineWidth: 1)
        )
        .cornerRadius(14)
        .sheet(item: $recordTarget) { med in
            RecordAdministrationSheet(med: med)
        }
        .sheet(item: $prnTarget) { med in
            PRNSheet(med: med)
        }
    }

    @ViewBuilder
    private func medRow(_ med: DueMedication) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(med.medName)
                    .font(.subheadline.weight(.semibold))
                Text(med.clientName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    // Server-rendered wall-clock label — shown as given, never
                    // converted through the device timezone.
                    if let label = med.dueTimeLabel {
                        Label(label, systemImage: "clock")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    statusChip(med)
                    if med.late {
                        Text("late")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.warning.opacity(0.2))
                            .foregroundColor(Theme.warning)
                            .cornerRadius(5)
                    }
                    // 🔒 v0.4.295 window chip — mirrors the web's my-day.ejs
                    //    "opens 7:00 PM" / "window closed" treatment so staff
                    //    see WHY Given isn't on offer without tapping.
                    if let chip = med.windowChipLabel {
                        let closed = med.giveWindowState == "closed"
                        Text("\u{1F512} \(chip)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background((closed ? Theme.danger : Color.secondary).opacity(0.15))
                            .foregroundColor(closed ? Theme.danger : .secondary)
                            .cornerRadius(5)
                            .accessibilityLabel(med.windowExplanation ?? chip)
                    }
                }
            }
            Spacer()
            if med.recordable {
                // v0.4.322 servers only mark a dose recordable INSIDE its
                // window, so this is normally "Record". The "Document" label
                // survives solely for pre-v0.4.322 servers that still send
                // recordable=true on out-of-window doses.
                Button(med.canGive ? "Record" : "Document") {
                    recordTarget = med
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(med.canGive ? Theme.primary : Color.secondary)
                .disabled(!online)
                .opacity(online ? 1 : 0.5)
            } else if let initials = med.initials {
                Text(initials)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func statusChip(_ med: DueMedication) -> some View {
        let (color, label): (Color, String) = {
            switch med.status {
            case "given": return (Theme.success, "given")
            case "refused": return (Theme.warning, "refused")
            case "held": return (Theme.primary, "held")
            case "missed": return (Theme.danger, "missed")
            default: return (.secondary, med.status)
            }
        }()
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(5)
    }
}

// MARK: - Record sheet (given / refused / held — missed is automatic, v0.4.315)

struct RecordAdministrationSheet: View {
    let med: DueMedication
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var action = "given"
    @State private var notes = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var wasLate = false
    /// Set when the SERVER refuses on the window (409) even though the client
    /// thought it was open — a dose can tip closed while this sheet is up.
    @State private var windowRefusal: String?

    /// 🔒 build 41 / server v0.4.315 — NO "Missed" here, per Nick: missed is
    /// automatic. A dose nobody records flips itself to missed when the give
    /// window closes; staff only record what actually happened. The server
    /// refuses a manual missed (400), so older builds' Missed button gets a
    /// clear error rather than writing anything.
    private let allActions: [(id: String, label: String, icon: String)] = [
        ("given", "Given", "checkmark.circle.fill"),
        ("refused", "Refused", "hand.raised.fill"),
        ("held", "Held", "pause.circle.fill"),
    ]

    /// 🔒 build 44 / server v0.4.322 — once the server refuses on the window,
    /// EVERY outcome is gone: missed is final, no late refused/held write-ups
    /// (Nick 2026-08-28). An empty list disables Submit; the header shows the
    /// server's own prose. `!canGive` (old servers / mid-race hints) still
    /// drops only Given.
    private var actions: [(id: String, label: String, icon: String)] {
        if windowRefusal != nil { return [] }
        guard med.canGive else {
            return allActions.filter { $0.id != "given" }
        }
        return allActions
    }

    /// Same rule the server enforces: refused / held need a reason.
    private var reasonRequired: Bool { action != "given" }
    private var canSubmit: Bool {
        !isSubmitting && appState.effectivelyOnline
            && actions.contains(where: { $0.id == action })
            && (!reasonRequired || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationView {
            Form {
                headerSection
                outcomeSection
                notesSection
                errorSection
                submitSection
            }
            .navigationTitle(med.canGive ? "Record Medication" : "Document Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // Never open pre-selected on an outcome that isn't offered.
                if !actions.contains(where: { $0.id == action }) {
                    action = actions.first?.id ?? "refused"
                }
            }
            .alert("Administration recorded", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text(wasLate ? "Recorded as \(action) (late — past the due window)." : "Recorded as \(action).")
            }
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(med.medName)
                    .font(.headline)
                Text(med.clientName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let label = med.dueTimeLabel {
                    Label("Due \(label)", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let instructions = med.instructions, !instructions.isEmpty {
                    Text(instructions)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                // 🔒 The server's own prose, shown up front — the same sentence
                //    a 409 would have carried, before the tap instead of after.
                if let why = windowRefusal ?? med.windowExplanation {
                    Label(why, systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundColor(Theme.danger)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var outcomeSection: some View {
        Section(
            header: Text("Outcome"),
            footer: Group {
                if windowRefusal != nil {
                    Text("The give window closed and this dose was automatically marked missed — missed is final and can no longer be documented. A manager can correct the record on the web dashboard.")
                } else if !med.canGive {
                    Text("“Given” is unavailable outside the one-hour give window. A manager can correct the record on the web dashboard.")
                }
            }
        ) {
            ForEach(actions, id: \.id) { a in
                outcomeRow(a)
            }
        }
    }

    private func outcomeRow(_ a: (id: String, label: String, icon: String)) -> some View {
        let iconColor: Color = a.id == "given" ? Theme.success : Theme.warning
        return Button {
            action = a.id
        } label: {
            HStack {
                Image(systemName: a.icon)
                    .foregroundColor(iconColor)
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

    private var notesSection: some View {
        Section(header: Text(reasonRequired ? "Reason (required)" : "Notes (optional)")) {
            MultilineTextBox(
                placeholder: reasonRequired ? "Why was the medication \(action)?" : "Optional notes",
                text: $notes
            )
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let err = errorMessage {
            Section {
                Text(err)
                    .font(.subheadline)
                    .foregroundColor(Theme.danger)
            }
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
                        Text("Record \(actions.first { $0.id == action }?.label ?? action)")
                            .font(.headline)
                    }
                    Spacer()
                }
            }
            .disabled(!canSubmit)
        }
    }

    private func submit() async {
        guard appState.effectivelyOnline else {
            errorMessage = "You're offline. Medication recording is online-only — reconnect and try again."
            return
        }
        isSubmitting = true
        errorMessage = nil
        do {
            let late = try await APIClient.shared.recordMedAdministration(
                id: med.id,
                action: action,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            wasLate = late
            await appState.refreshDueMedications()
            isSubmitting = false
            showSuccess = true
        } catch {
            isSubmitting = false
            let msg = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            // 🔒 A 409 here means the SERVER closed the window on us mid-sheet
            //    (or this is a build racing an auto-miss). Surface its reason
            //    verbatim and refresh the list — do NOT show a generic "server
            //    error" for a rule we understand. Since server v0.4.322 the
            //    refusal is terminal (missed is final): `actions` empties, the
            //    submit button disables, and the only path is Cancel.
            if case .conflict(let reason)? = (error as? APIError) {
                windowRefusal = reason
                errorMessage = nil
                await appState.refreshDueMedications()
            } else if case .serverError(409, let reason)? = (error as? APIError) {
                windowRefusal = reason
                errorMessage = nil
                await appState.refreshDueMedications()
            } else {
                errorMessage = msg
            }
        }
    }
}

// MARK: - iOS 15-compatible multiline text input (TextField axis: needs iOS 16)

struct MultilineTextBox: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(Color(UIColor.placeholderText))
                    .padding(.top, 8)
                    .padding(.leading, 5)
            }
            TextEditor(text: $text)
                .frame(minHeight: 60)
        }
    }
}

// MARK: - PRN sheet (as-needed administration)

struct PRNSheet: View {
    let med: PrnMedication
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var reason = ""
    @State private var result = ""
    @State private var notes = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    private var canSubmit: Bool {
        !isSubmitting && appState.effectivelyOnline
            && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(med.name)
                            .font(.headline)
                        Text(med.clientName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if let indication = med.prnReason, !indication.isEmpty {
                            Text("Indication: \(indication)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let instructions = med.instructions, !instructions.isEmpty {
                            Text(instructions)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section(header: Text("Reason (required)")) {
                    MultilineTextBox(placeholder: "Why was the medication given?", text: $reason)
                }

                Section(header: Text("Result (optional)")) {
                    MultilineTextBox(placeholder: "What was the outcome?", text: $result)
                }

                Section(header: Text("Notes (optional)")) {
                    MultilineTextBox(placeholder: "Optional notes", text: $notes)
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.subheadline)
                            .foregroundColor(Theme.danger)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Record PRN")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("PRN Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("PRN recorded", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("The PRN administration was recorded.")
            }
        }
    }

    private func submit() async {
        guard appState.effectivelyOnline else {
            errorMessage = "You're offline. Medication recording is online-only — reconnect and try again."
            return
        }
        isSubmitting = true
        errorMessage = nil
        do {
            try await APIClient.shared.recordPrnAdministration(

                clientId: med.clientId,
                medicationId: med.id,
                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                result: result.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            await appState.refreshDueMedications()
            isSubmitting = false
            showSuccess = true
        } catch {
            isSubmitting = false
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}
