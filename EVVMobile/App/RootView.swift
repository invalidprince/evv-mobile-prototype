import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.isLoggedIn {
            MainTabView()
        } else {
            LoginView()
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if appState.pendingSyncCount > 0 || appState.isSyncing {
                SyncBanner()
            }
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

struct SyncBanner: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            if appState.isSyncing {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Syncing…")
                    .font(.footnote.weight(.medium))
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                Text("\(appState.pendingSyncCount) visit\(appState.pendingSyncCount == 1 ? "" : "s") waiting to sync")
                    .font(.footnote.weight(.medium))
                Spacer()
                Button("Sync Now") { appState.syncNow() }
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.18))
        .foregroundColor(.primary)
    }
}
