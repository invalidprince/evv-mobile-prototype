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

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Visit")) {
                    HStack {
                        AvatarView(name: visit.client.name, size: 36)
                        VStack(alignment: .leading) {
                            Text(visit.client.name).font(.headline)
                            Text("\(visit.service.rawValue) · \(dateText)")
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

                Section(footer: Text("This sends a delete request to your supervisor for review. The visit stays on your record until it's approved.")) {
                    Button(role: .destructive, action: submit) {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Submit Delete Request")
                                .frame(maxWidth: .infinity)
                                .font(.headline)
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
            .navigationTitle("Request Delete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Delete request submitted", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your supervisor will review and respond.")
            }
        }
    }

    private func submit() {
        if appState.mode == .server, let svid = visit.serverVisitId {
            isSubmitting = true
            errorMessage = nil

            let fullReason = comment.isEmpty ? reason : "\(reason): \(comment)"

            Task {
                let err = await appState.submitServerDeleteRequest(
                    visitId: visit.id,
                    serverVisitId: svid,
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
            appState.requestDelete(visitId: visit.id)
            dismiss()
        }
    }
}
