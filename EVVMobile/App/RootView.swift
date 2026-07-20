import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .alert("Server Error", isPresented: $appState.showServerError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.serverError ?? "An unknown error occurred")
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            SyncStatusBanner()
            TabView {
                TodayView()
                    .tabItem { Label("Today", systemImage: "sun.max.fill") }
                ScheduleView()
                    .tabItem { Label("Schedule", systemImage: "calendar") }
                HistoryView()
                    .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                MoreView()
                    .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
            }
        }
    }
}

// MARK: - Passive sync-status banner

/// Always-visible thin banner showing current sync state. No manual action
/// required — auto-sync handles everything.  A manual "Sync" button is
/// available as an optional fallback only when items are queued and online.
struct SyncStatusBanner: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            if appState.isSyncing {
                // ⏳ Actively syncing
                ProgressView()
                    .scaleEffect(0.7)
                Text("Syncing…")
                    .font(.footnote.weight(.medium))
            } else if !appState.effectivelyOnline {
                // 📡 Offline
                Image(systemName: "wifi.slash")
                    .font(.footnote)
                    .foregroundColor(Theme.danger)
                if appState.pendingSyncCount > 0 {
                    Text("\(appState.pendingSyncCount) item\(appState.pendingSyncCount == 1 ? "" : "s") queued — will sync automatically")
                        .font(.footnote.weight(.medium))
                } else {
                    Text("Offline")
                        .font(.footnote.weight(.medium))
                }
            } else if appState.pendingSyncCount > 0 {
                // Online with items pending (brief window before debounced sync fires)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                Text("Syncing \(appState.pendingSyncCount) item\(appState.pendingSyncCount == 1 ? "" : "s")…")
                    .font(.footnote.weight(.medium))
                Spacer()
                // Optional manual fallback
                Button("Sync Now") { appState.syncNow() }
                    .font(.footnote.weight(.semibold))
            } else {
                // ✓ Everything synced
                Image(systemName: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundColor(Theme.success)
                Text("Synced \(appState.lastSyncRelativeText)")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bannerBackground)
        .foregroundColor(.primary)
    }

    private var bannerBackground: some View {
        Group {
            if appState.isSyncing || appState.pendingSyncCount > 0 {
                Theme.warning.opacity(0.18)
            } else if !appState.effectivelyOnline {
                Theme.danger.opacity(0.14)
            } else {
                Theme.success.opacity(0.12)
            }
        }
    }
}
