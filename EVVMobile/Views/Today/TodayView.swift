import SwiftUI

struct TodayView: View {
    @EnvironmentObject var appState: AppState
    @State private var clockInTarget: Visit?
    @State private var showUnscheduled = false
    @State private var showNonBillable = false
    @State private var noteVisit: Visit?

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case ..<12: return "Good morning"
        case ..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var dateText: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    private var upcoming: [Visit] {
        let base = appState.mode == .server ? appState.todayOnlyVisits : appState.todayVisits
        return base
            .filter { $0.status == .scheduled }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if appState.activeVisit != nil {
                        ActiveVisitCard()
                    }

                    ForEach(appState.incompleteNoteVisits) { visit in
                        IncompleteNoteCard(visit: visit) {
                            noteVisit = visit
                        }
                    }

                    if appState.isLoadingShifts {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading shifts…")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }

                    if !upcoming.isEmpty {
                        Text("Up Next")
                            .font(.title3.bold())
                            .padding(.top, 4)
                        ForEach(upcoming) { visit in
                            UpNextCard(visit: visit) {
                                clockInTarget = visit
                            }
                        }
                    }

                    if appState.mode == .server && !appState.isLoadingShifts && appState.activeVisit == nil && upcoming.isEmpty && appState.incompleteNoteVisits.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No shifts today — check the Schedule tab for upcoming and open shifts.")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }

                    // F1: Show pending offline items
                    if !appState.offlineQueue.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath.icloud")
                                    .foregroundColor(Theme.warning)
                                Text("Pending Sync")
                                    .font(.headline)
                            }
                            Text("\(appState.offlineQueue.count) action(s) saved locally \u{2014} will sync when you\u{2019}re back online.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(appState.offlineQueue) { action in
                                HStack(spacing: 8) {
                                    Image(systemName: queuedActionIcon(action.type))
                                        .foregroundColor(Theme.warning)
                                        .font(.caption)
                                    Text(queuedActionLabel(action))
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text(relativeTime(action.createdAt))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(14)
                        .background(Theme.warning.opacity(0.1))
                        .cornerRadius(12)
                    }

                    otherActions
                }
                .padding(16)
            }
            .refreshable {
                if appState.mode == .server {
                    await appState.refreshServerShifts()
                } else {
                    appState.syncNow()
                    // Brief delay so the spinner is visible in mock mode
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            .background(Theme.screenBackground.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(item: $clockInTarget) { visit in
                ClockInConfirmSheet(visit: visit)
            }
            .sheet(isPresented: $showUnscheduled) {
                UnscheduledVisitSheet()
            }
            .sheet(isPresented: $showNonBillable) {
                NonBillableSheet()
            }
            .sheet(item: $noteVisit) { visit in
                if appState.mode == .server {
                    // B2 fix: server mode uses ServerAddNoteSheet
                    ServerAddNoteSheet(visit: visit)
                } else {
                    NavigationView {
                        DocumentationView(visit: visit)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(greeting), \(appState.currentStaff.name.split(separator: " ").first.map(String.init) ?? "")")
                    .font(.title2.bold())
                Text(dateText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            syncChip
        }
    }

    @ViewBuilder
    private var syncChip: some View {
        if appState.isSyncing {
            HStack(spacing: 5) {
                ProgressView().scaleEffect(0.6)
                Text("Syncing")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if !appState.effectivelyOnline {
            HStack(spacing: 5) {
                Image(systemName: "wifi.slash")
                    .font(.caption2)
                    .foregroundColor(Theme.danger)
                Text("Offline")
                    .font(.caption)
                    .foregroundColor(Theme.danger)
            }
        } else if appState.pendingSyncCount > 0 {
            HStack(spacing: 5) {
                Circle()
                    .fill(Theme.warning)
                    .frame(width: 8, height: 8)
                Text("\(appState.pendingSyncCount) pending")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(Theme.success)
                Text("Synced")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var otherActions: some View {
        VStack(spacing: 12) {
            Button(action: { showUnscheduled = true }) {
                Label("Start Unscheduled Visit", systemImage: "plus.circle.fill")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button(action: { showNonBillable = true }) {
                Label("Non-Billable Time", systemImage: "briefcase.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.top, 8)
    }
}

// MARK: - Offline queue display helpers

private func queuedActionIcon(_ type: QueuedAction.ActionType) -> String {
    switch type {
    case .clockIn: return "play.circle"
    case .clockOut: return "stop.circle"
    case .addNote: return "square.and.pencil"
    case .nonBillable: return "briefcase"
    case .unscheduledVisit: return "plus.circle"
    }
}

private func queuedActionLabel(_ action: QueuedAction) -> String {
    switch action.type {
    case .clockIn: return "Clock in"
    case .clockOut: return "Clock out"
    case .addNote: return "Note"
    case .nonBillable: return "Non-billable time"
    case .unscheduledVisit:
        if let name = action.unschedClientName {
            return "Unscheduled visit \u{2014} \(name)"
        }
        return "Unscheduled visit"
    }
}

private func relativeTime(_ date: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 60 { return "just now" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    return "\(hours)h ago"
}

struct IncompleteNoteCard: View {
    let visit: Visit
    let onFinish: () -> Void

    /// Notes are due the same day as the visit — once midnight passes, the
    /// card escalates from the yellow "Incomplete" state to a red LATE state.
    private var isLate: Bool { visit.noteIsLate }

    private var accent: Color { isLate ? Theme.danger : Theme.warning }

    private var whenText: String {
        let day = DateFormatter()
        day.dateFormat = "EEE, MMM d"
        let time = DateFormatter()
        time.dateFormat = "h:mm a"
        let start = visit.actualStart ?? visit.scheduledStart
        if Calendar.current.isDateInToday(start) {
            return "today, \(time.string(from: start))"
        }
        if Calendar.current.isDateInYesterday(start) {
            return "yesterday"
        }
        return day.string(from: start)
    }

    private var titleText: String {
        isLate
            ? "LATE — note for \(visit.client.name), \(whenText)"
            : "Incomplete note — \(visit.client.name), \(whenText)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isLate ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(accent)
                Text(titleText)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            if isLate {
                Text("Notes are due the same day as the visit. This one is past due and flagged for your manager.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Button(action: onFinish) {
                Label("Finish Note", systemImage: "square.and.pencil")
            }
            .buttonStyle(PrimaryButtonStyle(color: accent))
        }
        .padding(14)
        .background(accent.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accent.opacity(0.5), lineWidth: 1)
        )
        .cornerRadius(14)
    }
}
