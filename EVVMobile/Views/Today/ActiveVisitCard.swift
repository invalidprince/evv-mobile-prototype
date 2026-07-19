import SwiftUI

struct ActiveVisitCard: View {
    @EnvironmentObject var appState: AppState
    @State private var showClockOut = false
    @State private var showDocumentation = false
    @State private var clockOutAndNext = false

    private var nextVisit: Visit? {
        appState.todayVisits
            .filter { $0.status == .scheduled }
            .sorted { $0.scheduledStart < $1.scheduledStart }
            .first
    }

    var body: some View {
        if let visit = appState.activeVisit {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    StatusBadge(text: "CLOCKED IN", color: Theme.success)
                    Spacer()
                    if visit.isGroup {
                        StatusBadge(text: "GROUP 1:2", color: Theme.primary)
                    }
                    if visit.teamStaff != nil {
                        StatusBadge(text: "TEAM 2:1", color: Theme.primary)
                    }
                }

                if visit.manualLocationFlagged {
                    Label("Manual location — pending manager review", systemImage: "mappin.and.ellipse")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.warning)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.warning.opacity(0.14))
                        .cornerRadius(8)
                }

                HStack(spacing: 12) {
                    AvatarView(name: visit.client.name, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(visit.clients.map { $0.name }.joined(separator: " & "))
                            .font(.headline)
                        Text(visit.service.rawValue)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                Text(appState.elapsedText)
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .foregroundColor(Theme.primary)

                Button(action: {
                    clockOutAndNext = false
                    showClockOut = true
                }) {
                    Label("Clock Out", systemImage: "stop.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.danger))

                HStack(spacing: 12) {
                    Button(action: { showDocumentation = true }) {
                        Label("Add Note", systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    if nextVisit != nil {
                        Button(action: {
                            clockOutAndNext = true
                            showClockOut = true
                        }) {
                            Label("Clock Out & Into Next", systemImage: "arrow.right.circle")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .cardStyle()
            .fullScreenCover(isPresented: $showClockOut) {
                ClockOutFlow(visit: visit, thenClockIntoNext: clockOutAndNext ? nextVisit : nil)
            }
            .sheet(isPresented: $showDocumentation) {
                NavigationView {
                    DocumentationView(visit: visit)
                }
            }
        }
    }
}
