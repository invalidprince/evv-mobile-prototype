import UIKit
import UserNotifications

// PushRegistration.swift — build 115 (Todoist 6hjxG9X3F2846Q3q, Nick #evv
// 2026-10-13): "Every place the system sends an SMS/text today should also send
// an iOS push notification."
//
// The SERVER does the mirroring (evv-poc v0.4.702 push.js: punch alerts, eMAR
// alerts + watchdog manager text, weekly digest). This file only gets an APNs
// device token and hands it to the server for the SIGNED-IN staff member:
//
//   • after a real server sign-in (never in demo mode): ask notification
//     permission (same prompt the local reminders already use, so most phones
//     have answered it) → registerForRemoteNotifications → POST
//     /api/me/push-token { token, environment, bundleId }.
//   • on sign-out: POST /api/me/push-token/remove with the OUTGOING session's
//     bearer, so the next person to sign in on this phone does not receive the
//     previous user's alerts (the server also re-assigns a token on register).
//
// Foreground presentation is handled by NoteReminderCenter (the
// UNUserNotificationCenter delegate already shows banners in the foreground).

final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in PushRegistration.shared.didReceive(token: hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        DiagnosticLogger.shared.logAPI("Push registration failed: \(error.localizedDescription)")
    }
}

@MainActor
final class PushRegistration {
    static let shared = PushRegistration()

    private(set) var deviceToken: String?
    private var signedIn = false
    private var uploadedFor: String?

    /// APNs environment the token belongs to. Debug builds from Xcode use the
    /// development (sandbox) gateway; TestFlight/App Store builds production.
    static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private init() {}

    /// Call after a successful SERVER sign-in (not demo mode).
    func didSignIn() {
        signedIn = true
        uploadedFor = nil
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
        uploadIfReady()
    }

    func didReceive(token: String) {
        deviceToken = token
        uploadIfReady()
    }

    /// Call from sign-out BEFORE the session token is dropped. Fire-and-forget:
    /// sign-out never waits on the network.
    func didSignOut(bearer: String?) {
        signedIn = false
        uploadedFor = nil
        guard let token = deviceToken, let bearer = bearer, !bearer.isEmpty else { return }
        Task { await APIClient.shared.removePushToken(token, bearer: bearer) }
    }

    private func uploadIfReady() {
        guard signedIn, let token = deviceToken, uploadedFor != token else { return }
        uploadedFor = token
        let bundle = Bundle.main.bundleIdentifier ?? ""
        Task {
            do {
                try await APIClient.shared.registerPushToken(token, environment: Self.apnsEnvironment, bundleId: bundle)
            } catch {
                await MainActor.run { if self.uploadedFor == token { self.uploadedFor = nil } }
                DiagnosticLogger.shared.logAPI("Push token upload failed: \(error.localizedDescription)")
            }
        }
    }
}
