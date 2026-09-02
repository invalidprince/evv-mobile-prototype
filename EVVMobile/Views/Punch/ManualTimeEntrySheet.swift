import SwiftUI

/// Manual time entry for non-EVV services (e.g. Lifesharing per diem).
/// Instead of live clock in/out, staff enter the visit start and end times.
/// No GPS acquisition — location is not applicable for these services.
struct ManualTimeEntrySheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let visit: Visit

    @State private var startTime: Date
    @State private var endTime: Date
    @State private var showSuccess = false
    // Build 54: await the server before showing success; a refusal is shown
    // inline (the root alert cannot present behind this sheet).
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var successMessage = "Time recorded"
    // Build 55: desktop-mirroring confirm (future end) instead of a hard block.
    @State private var confirmMessage: String?
    @State private var showConfirm = false

    init(visit: Visit) {
        self.visit = visit
        // Build 55: default to the SCHEDULED times exactly as the desktop's
        // my-day manual-time boxes do (`value="<%= to24h(s.start) %>"`) — no
        // capping at "now" and no forced +1 minute. A 12:00 AM → 12:00 AM
        // Lifesharing shift opens as 12:00 AM → 12:00 AM (a full day), which
        // the old min()/max() dance turned into an unsaveable pair.
        _startTime = State(initialValue: visit.scheduledStart)
        _endTime = State(initialValue: visit.scheduledEnd)
    }

    /// Build 55: no hard rules — mirrors the desktop. end <= start crosses
    /// midnight (12→12 = 24h); a not-yet-reached end is CONFIRMED (ManualSpan).
    private var validationError: String? { nil }

    private var durationText: String {
        ManualSpan.hint(start: startTime, end: endTime)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        AvatarView(name: visit.client.name, size: 64)
                        Text(visit.clients.map { $0.name }.joined(separator: " & "))
                            .font(.title3.bold())
                        Text(visit.service.rawValue)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 24)

                    // Non-EVV explainer
                    Label("This service doesn't use live clock in/out. Enter the visit start and end times.", systemImage: "pencil.and.list.clipboard")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.primary.opacity(0.08))
                        .cornerRadius(10)
                        .padding(.horizontal)

                    VStack(spacing: 12) {
                        DatePicker(selection: $startTime, displayedComponents: .hourAndMinute) {
                            Label("Start time", systemImage: "clock.fill")
                        }
                        Divider()
                        DatePicker(selection: $endTime, displayedComponents: .hourAndMinute) {
                            Label("End time", systemImage: "clock.badge.checkmark.fill")
                        }
                        Divider()
                        HStack {
                            Label("Duration", systemImage: "hourglass")
                            Spacer()
                            Text(durationText).font(.headline)
                        }
                    }
                    .cardStyle()
                    .padding(.horizontal)

                    if let error = validationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.danger)
                            .padding(.horizontal)
                    }

                    if let err = submitError {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Theme.danger)
                            Text("Nothing was saved. Adjust the times and try again.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.danger.opacity(0.08))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 12)

                    Button(action: confirm) {
                        if isSubmitting {
                            HStack {
                                ProgressView().tint(.white)
                                Text("Recording…")
                            }
                        } else {
                            Label("Record Time", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.success, enabled: validationError == nil && !isSubmitting))
                    .disabled(validationError != nil || isSubmitting)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
            .background(Theme.screenBackground.ignoresSafeArea())
            .navigationTitle("Record Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSubmitting)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
            .fullScreenCover(isPresented: $showSuccess, onDismiss: { dismiss() }) {
                ClockInSuccessView(message: successMessage)
            }
            .alert("Confirm times", isPresented: $showConfirm, presenting: confirmMessage) { _ in
                Button("Save") { submit() }
                Button("Cancel", role: .cancel) {}
            } message: { msg in
                Text(msg)
            }
        }
    }

    private func confirm() {
        guard validationError == nil, !isSubmitting else { return }
        // Untouched-placeholder prompt is an unscheduled-sheet concern (its
        // boxes open at midnight); here only the future-end confirm applies.
        if ManualSpan.endIsInFuture(start: startTime, end: endTime),
           let msg = ManualSpan.confirmationMessage(start: startTime, end: endTime) {
            confirmMessage = msg
            showConfirm = true
            return
        }
        submit()
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        submitError = nil
        let start = startTime, end = endTime
        Task { @MainActor in
            // Build 54: success ONLY after the server confirms (or the entry is
            // durably queued offline). A rejection keeps the sheet open with
            // the server's message — never success over a record that was
            // never written.
            let outcome = await appState.recordManualTime(visitId: visit.id, start: start, end: end)
            isSubmitting = false
            switch outcome {
            case .synced:
                successMessage = "Time recorded"
                showSuccess = true
            case .queued:
                successMessage = "Time saved — will sync when online"
                showSuccess = true
            case .rejected(let message):
                submitError = message
            }
        }
    }
}
