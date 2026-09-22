import SwiftUI

struct ActiveVisitCard: View {
    @EnvironmentObject var appState: AppState
    @State private var showClockOut = false
    @State private var showDocumentation = false
    @State private var clockOutAndNext = false
    /// Build 87 — "Request second staff" / "Request again" (server v0.4.615).
    @State private var showTwoToOneRequest = false
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
                    // Build 83 — a prior-day clock-in is not a happy green
                    // state; it is the thing blocking every other punch.
                    StatusBadge(text: visit.isStaleOpen ? "STILL CLOCKED IN" : "CLOCKED IN",
                                color: visit.isStaleOpen ? Theme.danger : Theme.success)
                    Spacer()
                    // build 86 — clocked in alone on a 2:1 service: still flagged.
                    if visit.showsSecondStaffRequired {
                        StatusBadge(text: "2:1 — SECOND STAFF REQUIRED", color: Theme.warning)
                    } else if visit.ratio == "2:1" {
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

                // Build 87 — 2:1 partner verification state (server v0.4.615):
                // waiting (countdown) / verified / not verified + request again.
                if appState.mode == .server, visit.ratio == "2:1", visit.serverVisitId != nil {
                    twoToOneRow(for: visit)
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
                        Text(visit.serviceLabel)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                if visit.isStaleOpen, let start = visit.actualStart {
                    // Days-old punch: the date matters more than a 400-hour
                    // running clock.
                    VStack(spacing: 2) {
                        Text("Clocked in \(Self.staleWhen(start))")
                            .font(.title3.weight(.bold))
                            .foregroundColor(Theme.danger)
                        Text("never clocked out")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text(appState.elapsedText)
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .foregroundColor(Theme.primary)
                }

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
            .sheet(isPresented: $showTwoToOneRequest) {
                TwoToOneRequestSheet(visit: visit)
            }
        }
    }

    /// Build 87 — the requester's view of the 2:1 verification: the latest
    /// request on THIS visit (appState.twoToOneMine, by server visit id).
    @ViewBuilder
    private func twoToOneRow(for visit: Visit) -> some View {
        let state = appState.twoToOneState(forServerVisitId: visit.serverVisitId)
        VStack(alignment: .leading, spacing: 6) {
            if let st = state, st.isPending {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = st.secondsRemaining(at: ctx.date)
                    HStack(spacing: 6) {
                        Image(systemName: "hourglass").foregroundColor(Theme.warning)
                        Text("Waiting for \(st.secondStaff.name) to verify they're here")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(String(format: "%d:%02d", left / 60, left % 60))
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundColor(left <= 15 ? Theme.danger : Theme.warning)
                    }
                }
                .accessibilityIdentifier("twoToOne.waiting")
            } else if let st = state, st.status == "confirmed" {
                Label("\(st.secondStaff.name) verified — clock-in times matched at \(st.clockIn ?? "")", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.success)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    if let st = state {
                        Label("\(st.secondStaff.name) \(st.status == "declined" ? "said they are not here" : "did not verify in time") — not clocked in", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if visit.showsSecondStaffRequired {
                        Label("Second staff member has not verified", systemImage: "person.2.slash")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    if state != nil || visit.showsSecondStaffRequired {
                        Button(state == nil ? "Request second staff" : "Request again") { showTwoToOneRequest = true }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .disabled(!appState.effectivelyOnline)
                            .accessibilityIdentifier("twoToOne.requestAgain")
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.10))
        .cornerRadius(8)
    }

    /// "Wed, Sep 3 at 10:46 AM" for a prior-day clock-in.
    static func staleWhen(_ start: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInYesterday(start) ? "'yesterday at' h:mm a" : "EEE, MMM d 'at' h:mm a"
        return f.string(from: start)
    }
}
