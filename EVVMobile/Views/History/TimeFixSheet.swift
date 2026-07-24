import SwiftUI

struct TimeFixSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let visit: Visit
    /// Optional callback when a time-fix is successfully submitted (B4: auto-confirm clock out)
    var onSubmitted: (() -> Void)? = nil

    @State private var newStart: Date
    @State private var newEnd: Date
    @State private var reason = "Forgot to clock in"
    @State private var comment = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var showOfflineQueued = false
    @State private var errorMessage: String?

    private let reasons = [
        "Forgot to clock in",
        "Forgot to clock out",
        "App/phone issue",
        "GPS failed to acquire",
        "Schedule changed on-site",
        "Other"
    ]

    init(visit: Visit, onSubmitted: (() -> Void)? = nil) {
        self.visit = visit
        self.onSubmitted = onSubmitted
        _newStart = State(initialValue: visit.actualStart ?? visit.scheduledStart)
        _newEnd = State(initialValue: visit.actualEnd ?? visit.scheduledEnd)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Visit")) {
                    HStack {
                        AvatarView(name: visit.client.name, size: 36)
                        VStack(alignment: .leading) {
                            Text(visit.client.name).font(.headline)
                            Text(visit.service.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Corrected Times")) {
                    DatePicker("Clock In", selection: $newStart, displayedComponents: [.hourAndMinute])
                    DatePicker("Clock Out", selection: $newEnd, displayedComponents: [.hourAndMinute])
                }

                Section(header: Text("Reason")) {
                    Picker("Reason", selection: $reason) {
                        ForEach(reasons, id: \.self) { r in
                            Text(r).tag(r)
                        }
                    }
                }

                Section(header: Text("Comment")) {
                    TextField("Add details for your supervisor…", text: $comment)
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

                Section {
                    Button(action: submit) {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Submit Request")
                                .frame(maxWidth: .infinity)
                                .font(.headline)
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
            .navigationTitle("Request Time Fix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Time fix request submitted", isPresented: $showSuccess) {
                Button("OK") {
                    onSubmitted?()
                    dismiss()
                }
            } message: {
                Text("Your supervisor will review and respond.")
            }
            .alert("Change request queued", isPresented: $showOfflineQueued) {
                Button("OK") {
                    onSubmitted?()
                    dismiss()
                }
            } message: {
                Text("Your change request will be submitted when you\u{2019}re back online.")
            }
        }
    }

    private func submit() {
        if appState.mode == .server {
            isSubmitting = true
            errorMessage = nil

            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            let newInStr = formatter.string(from: newStart)
            let newOutStr = formatter.string(from: newEnd)
            let fullReason = comment.isEmpty ? reason : "\(reason): \(comment)"

            // Offline: queue immediately and show offline confirmation
            if !appState.effectivelyOnline {
                appState.enqueueOfflineTimeFix(
                    localVisitId: visit.id,
                    serverVisitId: visit.serverVisitId,
                    newIn: newInStr,
                    newOut: newOutStr,
                    reason: fullReason
                )
                isSubmitting = false
                showOfflineQueued = true
                return
            }

            guard let svid = visit.serverVisitId else {
                errorMessage = "Visit not synced yet"
                isSubmitting = false
                return
            }

            Task {
                let err = await appState.submitServerTimeFix(
                    visitId: visit.id,
                    serverVisitId: svid,
                    newIn: newInStr,
                    newOut: newOutStr,
                    reason: fullReason
                )
                await MainActor.run {
                    isSubmitting = false
                    if let err = err {
                        errorMessage = err
                    } else {
                        showSuccess = true
                    }
                }
            }
        } else {
            // Mock mode
            appState.requestTimeFix(visitId: visit.id)
            dismiss()
        }
    }
}
