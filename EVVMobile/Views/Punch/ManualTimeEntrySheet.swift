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

    init(visit: Visit) {
        self.visit = visit
        // Default to the scheduled times; cap the end at "now" since a
        // manual entry records a visit that already happened.
        let now = Date()
        let defaultStart = min(visit.scheduledStart, now)
        let defaultEnd = min(visit.scheduledEnd, now)
        _startTime = State(initialValue: defaultStart)
        _endTime = State(initialValue: max(defaultEnd, defaultStart.addingTimeInterval(60)))
    }

    private var validationError: String? {
        if endTime <= startTime {
            return "End time must be after the start time."
        }
        if endTime > Date().addingTimeInterval(5 * 60) {
            return "End time can't be in the future."
        }
        return nil
    }

    private var durationText: String {
        let mins = max(0, Int(endTime.timeIntervalSince(startTime) / 60))
        return "\(mins / 60)h \(String(format: "%02d", mins % 60))m"
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
        }
    }

    private func confirm() {
        guard validationError == nil, !isSubmitting else { return }
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
