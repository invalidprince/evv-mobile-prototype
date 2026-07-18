import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var payPeriod = 0 // 0 = this, 1 = last
    @State private var timeFixVisit: Visit?

    private var filteredVisits: [Visit] {
        let cal = Calendar.current
        let now = Date()
        let cutoff = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now))!
        let visits = appState.pastVisits.filter { v in
            payPeriod == 0 ? v.scheduledStart >= cutoff : v.scheduledStart < cutoff
        }
        return visits.sorted { $0.scheduledStart > $1.scheduledStart }
    }

    private var totalHours: Double {
        filteredVisits.reduce(0) { $0 + $1.hoursValue }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Pay Period", selection: $payPeriod) {
                        Text("This Pay Period").tag(0)
                        Text("Last Pay Period").tag(1)
                    }
                    .pickerStyle(.segmented)

                    summaryCard

                    ForEach(filteredVisits) { visit in
                        HistoryRow(visit: visit) {
                            timeFixVisit = visit
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.screenBackground.ignoresSafeArea())
            .navigationTitle("History")
            .sheet(item: $timeFixVisit) { visit in
                TimeFixSheet(visit: visit)
            }
        }
        .navigationViewStyle(.stack)
    }

    private var summaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Hours")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f h", totalHours))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Theme.primary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Visits")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(filteredVisits.count)")
                    .font(.system(size: 32, weight: .bold))
            }
        }
        .cardStyle()
    }
}
