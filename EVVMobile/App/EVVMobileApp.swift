import SwiftUI

@main
struct EVVMobileApp: App {
    @StateObject private var appState = AppState()
    // Build 115 — receives the APNs device token (PushRegistration.swift).
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .accentColor(Theme.primary)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        appState.handleSceneActive()
                    }
                }
        }
    }
}
