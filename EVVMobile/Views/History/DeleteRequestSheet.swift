import SwiftUI

struct DeleteRequestSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let visit: Visit

    @State private var reason = "Duplicate entry"
    @State private var comment = ""

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

                Section(footer: Text("This sends a delete request to your supervisor for review. The visit stays on your record until it's approved.")) {
                    Button(role: .destructive, action: submit) {
                        Text("Submit Delete Request")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                }
            }
            .navigationTitle("Request Delete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() {
        appState.requestDelete(visitId: visit.id)
        dismiss()
    }
}
