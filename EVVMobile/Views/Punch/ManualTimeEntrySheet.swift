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

                    Spacer(minLength: 12)

                    Button(action: confirm) {
                        Label("Record Time", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.success, enabled: validationError == nil))
                    .disabled(validationError != nil)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
            .background(Theme.screenBackground.ignoresSafeArea())
            .navigationTitle("Record Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showSuccess, onDismiss: { dismiss() }) {
                ClockInSuccessView(message: "Time recorded")
            }
        }
    }

    private func confirm() {
        guard validationError == nil else { return }
        appState.recordManualTime(visitId: visit.id, start: startTime, end: endTime)
        showSuccess = true
    }
}
