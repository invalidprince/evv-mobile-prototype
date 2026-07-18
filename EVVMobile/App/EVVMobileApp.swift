import SwiftUI

@main
struct EVVMobileApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .accentColor(Theme.primary)
        }
    }
}
