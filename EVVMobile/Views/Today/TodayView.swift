import SwiftUI

struct TodayView: View {
    @EnvironmentObject var appState: AppState
    @State private var clockInTarget: Visit?
    @State private var showUnscheduled = false
    @State private var showNonBillable = false
    @State private var noteVisit: Visit?
    /// Build 71 — missed scheduled shift being resolved (server v0.4.505).
    @State private var missedTarget: MissedShiftItem?

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

                    // Build 83 — a visit still running from a PRIOR day is a
                    // problem that blocks every clock-in; say so at the top of
                    // Today until it is closed. Nick's Sep 3 Erik Hoover punch
                    // sat open for 18 days with nothing on the phone saying so.
                    ForEach(appState.staleOpenVisits, id: \.id) { visit in
                        StaleOpenVisitBanner(visit: visit)
                    }

                    if appState.activeVisit != nil {
                        ActiveVisitCard()
                    }

                    // eMAR (v0.4.274): meds are time-bound — deliberately ABOVE
                    // the pending-sync block and incomplete notes. A missed med
                    // is more urgent than an unsynced note. Hidden entirely when
                    // the staff member has no eMAR-enabled individuals today.
                    if appState.mode == .server
                        && (!appState.dueMedications.isEmpty || !appState.prnMedications.isEmpty
                            || !appState.correctableMedications.isEmpty) {
                        MedicationsDueCard()
                    }

                    // Pending sync items shown above incomplete notes
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

                    // Build 71 — scheduled shifts that were never started and
                    // still owe a reason (server v0.4.505). Above the incomplete
                    // notes: a shift with NO visit at all outranks a visit with
                    // an unfinished note. Server mode only — the list is derived
                    // server-side and never cached.
                    if appState.mode == .server {
                        ForEach(appState.missedShifts) { item in
                            MissedShiftCard(item: item, isOffline: !appState.effectivelyOnline) {
                                missedTarget = item
                            }
                        }
                    }

                    ForEach(appState.incompleteNoteVisits) { visit in
                        IncompleteNoteCard(visit: visit, isOffline: !appState.effectivelyOnline) {
                            noteVisit = visit
                        }
                    }

                    if appState.isLoadingShifts {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading shifts\u{2026}")
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

                    if appState.mode == .server && !appState.isLoadingShifts && appState.activeVisit == nil && upcoming.isEmpty && appState.incompleteNoteVisits.isEmpty && appState.missedShifts.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No shifts today \u{2014} check the Schedule tab for upcoming and open shifts.")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }

                    otherActions
                }
                .padding(16)
            }
            .refreshable {
                if appState.mode == .server {
                    await appState.refreshServerShifts()
                    // Build 70 — the incomplete-documentation cards for
                    // PREVIOUS dates come from historyVisits
                    // (GET /api/me/visits); /api/me/shifts is today-forward
                    // only. A pull-to-refresh on Today has to refresh the
                    // data Today actually renders.
                    await appState.refreshHistory()
                    await appState.refreshDueMedications()
                    await appState.refreshMissedShifts()
                } else {
                    appState.syncNow()
                    // Brief delay so the spinner is visible in mock mode
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            .background(Theme.screenBackground.ignoresSafeArea())
            .navigationBarHidden(true)
            .onAppear {
                // Warm up GPS as soon as the Today screen shows so a clock-in
                // moments later can use the cached fix instead of waiting.
                LocationManager.shared.warmUp()
                // Build 70 — Today renders incomplete-documentation cards for
                // PREVIOUS dates out of historyVisits, so Today has to be one
                // of the screens that keeps History warm. Debounced (the
                // build-53 helper) so tab-flipping does not hammer
                // /api/me/visits, and deliberately NOT awaited on the view's
                // own task — refreshHistory() runs unstructured internally
                // precisely because SwiftUI cancels these.
                if appState.mode == .server {
                    Task { await appState.refreshHistoryIfStale() }
                }
            }
            .sheet(item: $clockInTarget) { visit in
                if visit.requiresClockIn {
                    ClockInConfirmSheet(visit: visit)
                } else {
                    // Service doesn't require clock-in: manual time entry
                    ManualTimeEntrySheet(visit: visit)
                }
            }
            .sheet(isPresented: $showUnscheduled) {
                UnscheduledVisitSheet()
            }
            .sheet(isPresented: $showNonBillable) {
                NonBillableSheet()
            }
            .sheet(item: $noteVisit) { visit in
                NavigationView {
                    DocumentationView(visit: visit)
                }
            }
            .sheet(item: $missedTarget, onDismiss: {
                // Either path changes what the server derives (a reason
                // recorded, or a pending visit now covering the shift) —
                // re-read the list and History so the card and the ⏳ badge
                // reflect the server, never a local guess.
                Task {
                    await appState.refreshMissedShifts()
                    await appState.refreshHistory()
                }
            }) { item in
                MissedShiftResolveSheet(item: item)
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
            // One active visit at a time: block starting an unscheduled visit
            // while any visit is running (scheduled or unscheduled).
            Button(action: { showUnscheduled = true }) {
                Label("Start Unscheduled Visit", systemImage: "plus.circle.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(appState.hasActiveVisit)
            .opacity(appState.hasActiveVisit ? 0.5 : 1)

            if appState.hasActiveVisit {
                Text("Clock out of your current visit first.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

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
    case .timeFix: return "clock.arrow.2.circlepath"
    case .manualTime: return "pencil.circle"
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
    case .timeFix: return "Change request"
    case .manualTime: return "Manual time entry"
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
    var isOffline: Bool = false
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
            ? "LATE \u{2014} note for \(visit.client.name), \(whenText)"
            : "Incomplete note \u{2014} \(visit.client.name), \(whenText)"
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
            .buttonStyle(PrimaryButtonStyle(color: isOffline ? .gray : accent))
            .disabled(isOffline)
            if isOffline {
                Label("Requires internet connection", systemImage: "wifi.slash")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
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

// MARK: - Stale open visit banner (build 83)

/// "You're still clocked in on Erik Hoover from Sep 3 — clock out." A visit
/// that is running from a PRIOR day blocks every clock-in (server one-active-
/// visit rule) and, before build 83 / server v0.4.604, was visible nowhere on
/// the phone. Persistent on Today until the visit is closed. Same red accent
/// as a LATE note: this is a problem, not a state. Lives in TodayView.swift
/// on purpose — no new file, so no hand-edited pbxproj (the v0.4.430 trap).
struct StaleOpenVisitBanner: View {
    @EnvironmentObject var appState: AppState
    let visit: Visit
    @State private var showClockOut = false

    private var whenText: String {
        guard let start = visit.actualStart else { return "another day" }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInYesterday(start) ? "'yesterday,' h:mm a" : "EEE, MMM d 'at' h:mm a"
        return f.string(from: start)
    }

    /// The Today copy of this visit (what `clockOut()` acts on); this row
    /// itself when Today has not caught up yet.
    private var target: Visit {
        appState.todayVisits.first(where: { $0.serverVisitId == visit.serverVisitId && $0.status == .inProgress }) ?? visit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundColor(Theme.danger)
                Text("You're still clocked in on \(visit.clients.map { $0.name }.joined(separator: " & ")) from \(whenText)")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            Text("You can't clock in anywhere else until this visit is clocked out.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button {
                showClockOut = true
            } label: {
                Label("Clock Out of That Visit", systemImage: "stop.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.danger))
            .accessibilityIdentifier("today.staleOpenClockOut")
        }
        .padding(14)
        .background(Theme.danger.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.danger.opacity(0.5), lineWidth: 1)
        )
        .cornerRadius(14)
        .accessibilityIdentifier("today.staleOpenBanner")
        .fullScreenCover(isPresented: $showClockOut, onDismiss: {
            Task {
                await appState.refreshServerShifts()
                await appState.refreshHistory()
            }
        }) {
            ClockOutFlow(visit: target)
        }
    }
}
