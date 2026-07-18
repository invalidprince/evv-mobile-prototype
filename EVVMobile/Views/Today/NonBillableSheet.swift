import SwiftUI

struct NonBillableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var category = "Training"
    @State private var note = ""
    @State private var started = false
    @State private var startTime: Date?

    private let categories = ["Training", "Travel", "Admin", "Meeting"]

    private var icon: String {
        switch category {
        case "Training": return "graduationcap.fill"
        case "Travel": return "car.fill"
        case "Admin": return "doc.text.fill"
        default: return "person.3.fill"
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Category")) {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section(header: Text("Note (optional)")) {
                    TextField("What are you working on?", text: $note)
                }

                Section {
                    if started {
                        HStack {
                            Image(systemName: icon)
                                .foregroundColor(Theme.primary)
                            Text("\(category) time started")
                                .font(.headline)
                            Spacer()
                            StatusBadge(text: "RUNNING", color: Theme.success)
                        }
                        Button(role: .destructive, action: { dismiss() }) {
                            Label("Stop & Save", systemImage: "stop.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        Button(action: {
                            started = true
                            startTime = Date()
                        }) {
                            Label("Start \(category) Time", systemImage: "play.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("Non-Billable Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
