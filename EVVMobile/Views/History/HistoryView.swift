import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var payPeriod = 0 // 0 = this, 1 = last
    @State private var timeFixVisit: Visit?
    @State private var deleteVisit: Visit?
    @State private var noteVisit: Visit?
    @State private var addNoteVisit: Visit?

    // MARK: - Mock mode data

    private var mockFilteredVisits: [Visit] {
        let cal = Calendar.current
        let now = Date()
        let cutoff = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now))!
        let visits = appState.pastVisits.filter { v in
            payPeriod == 0 ? v.scheduledStart >= cutoff : v.scheduledStart < cutoff
        }
        return visits.sorted { $0.scheduledStart > $1.scheduledStart }
    }

    // MARK: - Server mode data

    private var serverGroupedVisits: [(label: String, visits: [Visit])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        var groups: [String: (date: Date, visits: [Visit])] = [:]
        for visit in appState.historyVisits {
            let day = cal.startOfDay(for: visit.actualStart ?? visit.scheduledStart)
            let label: String
            if cal.isDate(day, inSameDayAs: today) {
                label = "Today"
            } else if cal.isDate(day, inSameDayAs: yesterday) {
                label = "Yesterday"
            } else {
                let f = DateFormatter()
                f.dateFormat = "EEEE, MMM d"
                label = f.string(from: day)
            }
            if groups[label] == nil {
                groups[label] = (date: day, visits: [])
            }
            groups[label]!.visits.append(visit)
        }
        return groups.values
            .sorted { $0.date > $1.date }
            .map { (label: $0.visits.first.flatMap { v in
                let day = cal.startOfDay(for: v.actualStart ?? v.scheduledStart)
                if cal.isDate(day, inSameDayAs: today) { return "Today" }
                if cal.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
                let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f.string(from: day)
            } ?? "", visits: $0.visits.sorted { ($0.actualStart ?? $0.scheduledStart) > ($1.actualStart ?? $1.scheduledStart) }) }
    }

    private var totalHoursServer: Double {
        appState.historyVisits.reduce(0) { $0 + $1.hoursValue }
    }

    private var totalHoursMock: Double {
        mockFilteredVisits.reduce(0) { $0 + $1.hoursValue }
    }

    var body: some View {
        NavigationView {
            Group {
                if appState.mode == .server {
                    serverBody
                } else {
                    mockBody
                }
            }
            .background(Theme.screenBackground.ignoresSafeArea())
            .navigationTitle("History")
            .sheet(item: $timeFixVisit) { visit in
                TimeFixSheet(visit: visit)
            }
            .sheet(item: $deleteVisit) { visit in
                DeleteRequestSheet(visit: visit)
            }
            .sheet(item: $noteVisit) { visit in
                NavigationView {
                    DocumentationView(visit: visit)
                }
            }
            .sheet(item: $addNoteVisit) { visit in
                ServerAddNoteSheet(visit: visit)
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Server Mode Body

    private var serverBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                serverSummaryCard

                if appState.isLoadingHistory {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading history…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }

                if !appState.isLoadingHistory && appState.historyVisits.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No visit history yet")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }

                ForEach(serverGroupedVisits, id: \.label) { group in
                    Text(group.label)
                        .font(.title3.bold())
                        .padding(.top, 4)
                    ForEach(group.visits) { visit in
                        ServerHistoryRow(visit: visit,
                                         onTimeFix: { timeFixVisit = visit },
                                         onRequestDelete: { deleteVisit = visit },
                                         onAddNote: { addNoteVisit = visit },
                                         onFinishNote: { noteVisit = visit })
                    }
                }
            }
            .padding(16)
        }
        .refreshable {
            await appState.refreshHistory()
        }
        .onAppear {
            if appState.historyVisits.isEmpty {
                Task { await appState.refreshHistory() }
            }
        }
    }

    // MARK: - Mock Mode Body (unchanged)

    private var mockBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Pay Period", selection: $payPeriod) {
                    Text("This Pay Period").tag(0)
                    Text("Last Pay Period").tag(1)
                }
                .pickerStyle(.segmented)

                mockSummaryCard

                ForEach(mockFilteredVisits) { visit in
                    HistoryRow(visit: visit,
                               onTimeFix: { timeFixVisit = visit },
                               onRequestDelete: { deleteVisit = visit },
                               onFinishNote: { noteVisit = visit })
                }
            }
            .padding(16)
        }
    }

    private var serverSummaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Hours (14d)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f h", totalHoursServer))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Theme.primary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Visits")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(appState.historyVisits.count)")
                    .font(.system(size: 32, weight: .bold))
            }
        }
        .cardStyle()
    }

    private var mockSummaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Hours")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f h", totalHoursMock))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Theme.primary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Visits")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(mockFilteredVisits.count)")
                    .font(.system(size: 32, weight: .bold))
            }
        }
        .cardStyle()
    }
}

// MARK: - Server History Row

struct ServerHistoryRow: View {
    let visit: Visit
    let onTimeFix: () -> Void
    let onRequestDelete: () -> Void
    let onAddNote: () -> Void
    let onFinishNote: () -> Void

    private var timeText: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let start = visit.actualStart ?? visit.scheduledStart
        let end = visit.actualEnd
        let startStr = f.string(from: start)
        let endStr = end != nil ? f.string(from: end!) : "—"
        return "\(startStr) – \(endStr)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 12) {
                    AvatarView(name: visit.client.name, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(visit.client.name).font(.headline)
                        Text(visit.service.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(visit.durationText)
                        .font(.headline)
                    Text(timeText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Status chips row
            HStack(spacing: 6) {
                // Note status
                if visit.hasNote {
                    StatusBadge(text: "📝 Note", color: Theme.success)
                }
                // Doc status
                if let ds = visit.serverDocStatus, !ds.isEmpty {
                    StatusBadge(text: ds.capitalized, color: ds.lowercased() == "complete" ? Theme.success : Theme.warning)
                }
                // Pending request badges
                if visit.timeFixStatus == .pending {
                    StatusBadge(text: "⏳ time fix requested", color: Theme.warning)
                } else if visit.timeFixStatus == .approved {
                    StatusBadge(text: "FIX APPROVED", color: Theme.success)
                } else if visit.timeFixStatus == .denied {
                    StatusBadge(text: "FIX DENIED", color: Theme.danger)
                }
                if visit.deleteRequestStatus == .pending {
                    StatusBadge(text: "⏳ delete requested", color: Theme.warning)
                } else if visit.deleteRequestStatus == .approved {
                    StatusBadge(text: "DELETE APPROVED", color: Theme.success)
                } else if visit.deleteRequestStatus == .denied {
                    StatusBadge(text: "DELETE DENIED", color: Theme.danger)
                }
                Spacer()
            }

            // Action buttons
            HStack(spacing: 16) {
                Button(action: onAddNote) {
                    Label(visit.hasNote ? "Update Note" : "Add Note", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Theme.primary)
                }
                if visit.timeFixStatus == .none {
                    Button("Time Fix", action: onTimeFix)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Theme.primary)
                }
                if visit.deleteRequestStatus == .none {
                    Button("Delete", action: onRequestDelete)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Theme.danger)
                }
                Spacer()
            }
        }
        .cardStyle()
    }
}

// MARK: - Server Add Note Sheet

struct ServerAddNoteSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let visit: Visit

    @State private var noteText = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

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

                Section(header: Text("Note")) {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 120)
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
                            Text("Submit Note")
                                .frame(maxWidth: .infinity)
                                .font(.headline)
                        }
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Note submitted", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your note has been saved.")
            }
        }
    }

    private func submit() {
        guard let svid = visit.serverVisitId else { return }
        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            await appState.submitServerNote(visitId: visit.id, serverVisitId: svid, text: text)
            await MainActor.run {
                isSubmitting = false
                showSuccess = true
            }
        }
    }
}
