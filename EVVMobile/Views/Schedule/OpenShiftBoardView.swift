import SwiftUI

// MARK: - Open Shift Board (own screen, pushed from Schedule)

/// Card 6hcQmMwRQMr2r28H — the two open-shift sections used to live at the
/// bottom of the Schedule scroll, which made Schedule very long. They now live
/// here, on their own screen, reached from a compact entry row at the top of
/// Schedule (`OpenShiftBoardEntryRow`).
///
/// Content and pickup behavior are unchanged: `ServerOpenRulesSection` and
/// `ServerOpenShiftsSection` are the same views, moved verbatim. The
/// `ruleClaimMessage` alert moved here with them — it used to hang off
/// `ServerScheduleContent`, and a permanent pickup confirmed on this screen
/// would otherwise succeed silently.
///
/// Permissions: none new. The server only returns `openShifts` / `openRules`
/// this staff member is eligible to claim, and the pickup endpoints re-validate
/// eligibility server-side. This is a pure navigation change to data the user
/// can already see, so there is no new flag, no Report Permissions row and no
/// Settings surface.
struct OpenShiftBoardView: View {
    @EnvironmentObject var appState: AppState

    private var isEmpty: Bool {
        appState.serverOpenRules.isEmpty && appState.serverOpenShifts.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                if !appState.effectivelyOnline {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(Theme.danger)
                        Text("You're offline")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Theme.danger)
                        Spacer()
                        Text("Showing cached open shifts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Theme.danger.opacity(0.1))
                    .cornerRadius(10)
                }

                Text("Shifts nobody is assigned to yet. Pick one up and it's yours.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "hand.raised.slash")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No open shifts right now")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .accessibilityIdentifier("openShiftBoardEmpty")
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
        .background(Theme.screenBackground.ignoresSafeArea())
        .navigationTitle("Open Shifts")
        .navigationBarTitleDisplayMode(.inline)
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
            // Risk #2 on the card: the board needs its own refresh trigger or
            // it shows stale counts when opened after a background period.
            guard appState.effectivelyOnline else { return }
            Task { await appState.refreshServerShifts() }
        }
        .accessibilityIdentifier("openShiftBoard")
    }
}

// MARK: - Entry row on Schedule

/// Compact row at the top of Schedule. Hidden entirely when nothing is open,
/// so there is never a dead tap target. The count is the mitigation for the
/// discoverability risk on the card — keep it in the label.
struct OpenShiftBoardEntryRow: View {
    @EnvironmentObject var appState: AppState

    var openCount: Int {
        appState.serverOpenShifts.count + appState.serverOpenRules.count
    }

    var body: some View {
        NavigationLink(destination: OpenShiftBoardView()) {
            HStack(spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.title3)
                    .foregroundColor(Theme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(openCount == 1 ? "1 open shift available" : "\(openCount) open shifts available")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("Pick up a shift")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .frame(minHeight: 52)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("openShiftBoardEntry")
    }
}
