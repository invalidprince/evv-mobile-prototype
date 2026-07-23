import SwiftUI

struct NonBillableSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var category = "Training"
    @State private var note = ""
    @State private var started = false
    @State private var startTime: Date?
    @State private var minutesText = ""
    @State private var selectedDate = Date()
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    private let categories = ["Training", "Travel", "Admin", "Meeting", "Other"]

    private var icon: String {
        switch category {
        case "Training": return "graduationcap.fill"
        case "Travel": return "car.fill"
        case "Admin": return "doc.text.fill"
        case "Other": return "ellipsis.circle.fill"
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

                if appState.mode == .server {
                    serverFields
                } else {
                    mockFields
                }
            }
            .navigationTitle("Non-Billable Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Non-billable time saved", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your \(category.lowercased()) time has been recorded.")
            }
        }
    }

    // MARK: - Server mode fields

    @ViewBuilder
    private var serverFields: some View {
        Section(header: Text("Date")) {
            DatePicker("Date", selection: $selectedDate, displayedComponents: [.date])
        }

        Section(header: Text("Duration (minutes)")) {
            TextField("e.g. 30", text: $minutesText)
                .keyboardType(.numberPad)
        }

        Section(header: Text("Note (required)"), footer: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Text("A note describing the activity is required.").foregroundColor(Theme.danger) : nil) {
            TextField("What are you working on?", text: $note)
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
            Button(action: submitServer) {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Submit \(category) Time", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
            }
            .disabled(isSubmitting || (Int(minutesText) ?? 0) <= 0 || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Mock mode fields (original)

    @ViewBuilder
    private var mockFields: some View {
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

    // MARK: - Server submit

    private func submitServer() {
        guard let minutes = Int(minutesText), minutes > 0 else {
            errorMessage = "Please enter a valid number of minutes."
            return
        }
        guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter a note describing the activity."
            return
        }
        isSubmitting = true
        errorMessage = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: selectedDate)

        Task {
            let success = await appState.submitServerNonBillable(
                category: category,
                minutes: minutes,
                note: note,
                date: dateStr
            )
            await MainActor.run {
                isSubmitting = false
                if success {
                    showSuccess = true
                } else {
                    errorMessage = appState.serverError ?? "Failed to submit"
                }
            }
        }
    }
}
