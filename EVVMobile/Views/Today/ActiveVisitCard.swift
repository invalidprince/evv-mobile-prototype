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

    /// True when the active visit already has documentation content — either a
    /// note submitted mid-shift (hasNote) or a locally saved draft. Drives the
    /// Add vs Edit label on the mid-visit documentation button.
    private func hasDocContent(for visit: Visit) -> Bool {
        if visit.hasNote { return true }
        if appState.mode == .server, let svid = visit.serverVisitId,
           appState.serverNoteDraft(for: svid).hasContent {
            return true
        }
        return appState.noteDraft(for: visit.id).hasContent
    }

    var body: some View {
        if let visit = appState.activeVisit {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    StatusBadge(text: "CLOCKED IN", color: Theme.success)
                    Spacer()
                    if visit.ratio == "2:1" {
                        StatusBadge(text: "2:1", color: Theme.primary)
                    }
                    if visit.isGroup {
                        StatusBadge(text: "GROUP 1:2", color: Theme.primary)
                    }
                    if visit.teamStaff != nil && visit.ratio == nil {
                        StatusBadge(text: "TEAM 2:1", color: Theme.primary)
                    }
                }

                if !visit.partners.isEmpty {
                    ForEach(visit.partners, id: \.staffId) { partner in
                        Label("With: \(partner.name)", systemImage: "person.2.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.primary.opacity(0.1))
                            .cornerRadius(8)
                    }
                } else if let partner = visit.teamStaff {
                    Label("With: \(partner.name)", systemImage: "person.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.primary.opacity(0.1))
                        .cornerRadius(8)
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

                // Mid-visit documentation: write (or keep editing) the visit
                // note without clocking out. Everything entered here persists
                // as a draft and prefills the clock-out documentation step.
                Button(action: { showDocumentation = true }) {
                    Label(
                        hasDocContent(for: visit) ? "Edit Documentation" : "Add Documentation",
                        systemImage: hasDocContent(for: visit) ? "doc.text.fill" : "square.and.pencil"
                    )
                }
                .buttonStyle(SecondaryButtonStyle())

                if visit.hasNote {
                    Label("Note submitted — you can update it until clock-out.", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundColor(Theme.success)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if nextVisit != nil {
                    HStack {
                        Spacer()
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
