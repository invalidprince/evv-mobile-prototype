import SwiftUI

struct TimeFixSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let visit: Visit

    @State private var newStart: Date
    @State private var newEnd: Date
    @State private var reason = "Forgot to clock in"
    @State private var comment = ""

    private let reasons = [
        "Forgot to clock in",
        "Forgot to clock out",
        "App/phone issue",
        "GPS failed to acquire",
        "Schedule changed on-site",
        "Other"
    ]

    init(visit: Visit) {
        self.visit = visit
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

                Section {
                    Button(action: submit) {
                        Text("Submit Request")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                }
            }
            .navigationTitle("Request Time Fix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() {
        appState.requestTimeFix(visitId: visit.id)
        dismiss()
    }
}
