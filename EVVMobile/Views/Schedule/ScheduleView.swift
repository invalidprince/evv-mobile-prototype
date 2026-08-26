import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationView {
            Group {
                if appState.mode == .server {
                    ServerScheduleContent()
                } else {
                    MockScheduleContent()
                }
            }
            .background(Theme.screenBackground.ignoresSafeArea())
            .navigationTitle("Schedule")
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Server Mode Schedule (7-day grouped view + open shifts)

struct ServerScheduleContent: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // B5: Offline banner
                if !appState.effectivelyOnline {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(Theme.danger)
                        Text("You're offline")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Theme.danger)
                        Spacer()
                        Text("Showing cached schedule")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Theme.danger.opacity(0.1))
                    .cornerRadius(10)
                }

                // B5: Error banner with retry
                if let error = appState.scheduleLoadError, appState.effectivelyOnline {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Theme.warning)
                            Text("Could not load schedule")
                                .font(.subheadline.weight(.medium))
                        }
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button(action: {
                            Task { await appState.refreshServerShifts() }
                        }) {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(14)
                    .background(Theme.warning.opacity(0.1))
                    .cornerRadius(12)
                }

                if appState.isLoadingShifts && appState.todayVisits.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading schedule…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                let groups = appState.groupedScheduleVisits

                if groups.isEmpty && !appState.isLoadingShifts && appState.scheduleLoadError == nil {
                    VStack(spacing: 10) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No shifts scheduled this week")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group.visits) { visit in
                            NavigationLink(destination: ShiftDetailView(visit: visit)) {
                                ShiftRow(visit: visit)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(group.label)
                            .font(.title3.bold())
                            .padding(.top, group.date == groups.first?.date ? 0 : 8)
                    }
                }

                if !appState.serverOpenRules.isEmpty {
                    ServerOpenRulesSection()
                }

                if !appState.serverOpenShifts.isEmpty {
                    ServerOpenShiftsSection()
                }
            }
            .padding(16)
        }
        .alert("You're on the schedule", isPresented: Binding(
            get: { appState.ruleClaimMessage != nil },
            set: { if !$0 { appState.ruleClaimMessage = nil } }
        )) {
            Button("OK", role: .cancel) { appState.ruleClaimMessage = nil }
        } message: {
            Text(appState.ruleClaimMessage ?? "")
        }
        .refreshable {
            await appState.refreshServerShifts()
        }
        .onAppear {
            // Re-fetch the schedule whenever this screen appears so shifts
            // created on the dashboard show up without a re-login.
            guard appState.effectivelyOnline else { return }
            Task { await appState.refreshServerShifts() }
        }
    }
}

// MARK: - Server Open Recurring Rules (permanent weekday pickup)

/// One card per open recurring rule — "Open · Mondays · 9:00 AM–5:00 PM ·
/// Erik Hoover · W7061" — with a "Pick up Mondays" action per weekday.
/// Claiming a weekday is PERMANENT: every future occurrence of that weekday
/// is assigned to the staff member until a manager reassigns it. The
/// confirmation dialog says so in plain words before anything is sent.
struct ServerOpenRulesSection: View {
    @EnvironmentObject var appState: AppState

    /// Pending confirmation — which rule + weekday the staff member tapped.
    struct PendingPickup: Identifiable {
        let rule: ServerOpenRule
        let weekday: Int
        var id: String { "\(rule.id)-\(weekday)" }
    }
    @State private var pending: PendingPickup?

    static let weekdayPlurals = ["Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays"]

    private func daysLabel(_ rule: ServerOpenRule) -> String {
        let names = rule.weekdays.compactMap { $0 >= 0 && $0 <= 6 ? Self.weekdayPlurals[$0] : nil }
        return names.joined(separator: " / ")
    }

    private func intervalNote(_ rule: ServerOpenRule) -> String? {
        guard let n = rule.intervalWeeks, n > 1 else { return nil }
        return n == 2 ? "Every other week" : "Every \(n) weeks"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "repeat.circle.fill")
                    .foregroundColor(Theme.primary)
                Text("Open Recurring Shifts")
                    .font(.title3.bold())
            }
            .padding(.top, 8)

            Text("Pick up a day of the week permanently — it's yours every week going forward.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(appState.serverOpenRules) { rule in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("Open · \(daysLabel(rule))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.primary)
                        if let note = intervalNote(rule) {
                            Text("· \(note)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Text("\(rule.start) – \(rule.end)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        AvatarView(name: rule.individual.name, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.individual.name)
                                .font(.headline)
                            if let ind2 = rule.individual2 {
                                Text("with \(ind2.name)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text(rule.service ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }

                    ForEach(rule.weekdays, id: \.self) { wd in
                        let key = "\(rule.id)-\(wd)"
                        Button(action: { pending = PendingPickup(rule: rule, weekday: wd) }) {
                            if appState.claimingRuleKey == key {
                                HStack(spacing: 8) {
                                    ProgressView().tint(.white)
                                    Text("Picking up…")
                                }
                            } else {
                                Label("Pick up \(Self.weekdayPlurals[wd])", systemImage: "repeat")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(color: Theme.success,
                                                        enabled: appState.claimingRuleKey == nil && appState.effectivelyOnline))
                        .disabled(appState.claimingRuleKey != nil || !appState.effectivelyOnline)
                    }

                    if !appState.effectivelyOnline {
                        Text("Connect to the internet to pick up a permanent day.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .cardStyle()
            }
        }
        .alert(item: $pending) { p in
            let day = Self.weekdayPlurals[p.weekday]
            return Alert(
                title: Text("Pick up \(day) permanently?"),
                message: Text("You'll be scheduled every \(String(day.dropLast())) \(p.rule.start) – \(p.rule.end) with \(p.rule.individual.name) from now on, until a manager reassigns it. This covers ALL future \(day), not just one date."),
                primaryButton: .default(Text("Pick up \(day)")) {
                    Task { await appState.claimRuleWeekday(ruleId: p.rule.id, weekday: p.weekday) }
                },
                secondaryButton: .cancel()
            )
        }
    }
}

// MARK: - Server Open Shifts Section

struct ServerOpenShiftsSection: View {
    @EnvironmentObject var appState: AppState

    private func shiftTimeDisplay(_ shift: ServerShift) -> String {
        // Parse date + start/end times for display
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        // Try to parse the date for a day label
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dayLabel: String
        if let date = dateFormatter.date(from: shift.date) {
            let cal = Calendar.current
            if cal.isDateInToday(date) {
                dayLabel = "Today"
            } else if cal.isDateInTomorrow(date) {
                dayLabel = "Tomorrow"
            } else {
                let displayFmt = DateFormatter()
                displayFmt.dateFormat = "EEE, MMM d"
                dayLabel = displayFmt.string(from: date)
            }
        } else {
            dayLabel = shift.date
        }

        return "\(dayLabel) · \(shift.start) – \(shift.end)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundColor(Theme.primary)
                Text("Open Shifts")
                    .font(.title3.bold())
            }
            .padding(.top, 8)

            ForEach(appState.serverOpenShifts, id: \.id) { shift in
                VStack(alignment: .leading, spacing: 10) {
                    Text(shiftTimeDisplay(shift))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.primary)

                    HStack(spacing: 12) {
                        AvatarView(name: shift.individual.name, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shift.individual.name)
                                .font(.headline)
                            Text(shift.service ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if let location = shift.location, !location.isEmpty {
                                Label(location, systemImage: "mappin.and.ellipse")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }

                    if let ratio = shift.ratio, ratio == "2:1" {
                        StatusBadge(text: "2:1", color: Theme.primary)
                    }

                    Button(action: {
                        Task {
                            await appState.claimOpenShift(shiftId: shift.id)
                        }
                    }) {
                        if appState.claimingShiftId == shift.id {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white)
                                Text("Picking up…")
                            }
                        } else {
                            Label("Pick Up Shift", systemImage: "hand.raised.fill")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.success, enabled: appState.claimingShiftId == nil))
                    .disabled(appState.claimingShiftId != nil)
                }
                .cardStyle()
            }
        }
    }
}

// MARK: - Mock Mode Schedule (existing week-strip layout)

struct MockScheduleContent: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedDay = Date()

    private var weekDays: [Date] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -3, to: cal.startOfDay(for: Date()))!
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var visitsForSelectedDay: [Visit] {
        let cal = Calendar.current
        let all = appState.todayVisits + appState.pastVisits
        return all
            .filter { cal.isDate($0.scheduledStart, inSameDayAs: selectedDay) }
            .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WeekStrip(days: weekDays, selected: $selectedDay)

                if visitsForSelectedDay.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No shifts this day")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(visitsForSelectedDay) { visit in
                        NavigationLink(destination: ShiftDetailView(visit: visit)) {
                            ShiftRow(visit: visit)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !appState.openShifts.isEmpty {
                    OpenShiftsSection()
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Week Strip (mock mode)

struct WeekStrip: View {
    let days: [Date]
    @Binding var selected: Date

    private func dayLetter(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: d)
    }

    private func dayNum(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"
        return f.string(from: d)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(days, id: \.self) { day in
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selected)
                    let isToday = Calendar.current.isDateInToday(day)
                    Button(action: { selected = day }) {
                        VStack(spacing: 4) {
                            Text(dayLetter(day))
                                .font(.caption2.weight(.medium))
                            Text(dayNum(day))
                                .font(.headline)
                        }
                        .frame(width: 48, height: 62)
                        .background(isSelected ? Theme.primary : Theme.cardBackground)
                        .foregroundColor(isSelected ? .white : (isToday ? Theme.primary : .primary))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isToday && !isSelected ? Theme.primary : Color.clear, lineWidth: 1.5)
                        )
                    }
                }
            }
        }
    }
}
