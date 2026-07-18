import SwiftUI

struct ScheduleView: View {
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
        NavigationView {
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
            .background(Theme.screenBackground.ignoresSafeArea())
            .navigationTitle("Schedule")
        }
        .navigationViewStyle(.stack)
    }
}

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
