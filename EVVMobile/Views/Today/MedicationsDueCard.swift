import SwiftUI

// MARK: - Medications Due card (build 30 / server v0.4.274)
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
                }
            }
            Spacer()
            if med.recordable {
                Button("Record") {
                    recordTarget = med
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
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

// MARK: - Record sheet (given / refused / held / missed)

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

    private let actions: [(id: String, label: String, icon: String)] = [
        ("given", "Given", "checkmark.circle.fill"),
        ("refused", "Refused", "hand.raised.fill"),
        ("held", "Held", "pause.circle.fill"),
        ("missed", "Missed", "xmark.circle.fill"),
    ]

    /// Same rule the server enforces: refused / held / missed need a reason.
    private var reasonRequired: Bool { action != "given" }
    private var canSubmit: Bool {
        !isSubmitting && appState.effectivelyOnline
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
            .navigationTitle("Record Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
            }
            .padding(.vertical, 2)
        }
    }

    private var outcomeSection: some View {
        Section(header: Text("Outcome")) {
            ForEach(actions, id: \.id) { a in
                outcomeRow(a)
            }
        }
    }

    private func outcomeRow(_ a: (id: String, label: String, icon: String)) -> some View {
        let iconColor: Color = a.id == "given" ? Theme.success : (a.id == "missed" ? Theme.danger : Theme.warning)
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
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
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
