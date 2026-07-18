import SwiftUI

struct TodayView: View {
    @EnvironmentObject var appState: AppState
    @State private var clockInTarget: Visit?
    @State private var showUnscheduled = false
    @State private var showNonBillable = false

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
        appState.todayVisits
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

                    otherActions
                }
                .padding(16)
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
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.pendingSyncCount == 0 ? Theme.success : Theme.warning)
                    .frame(width: 10, height: 10)
                Text(appState.pendingSyncCount == 0 ? "Synced" : "Pending")
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
