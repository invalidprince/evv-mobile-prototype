import SwiftUI

struct MoreView: View {
    @EnvironmentObject var appState: AppState
    @State private var visitReminders = true
    @State private var openShiftAlerts = true
    @State private var docReminders = true
    @State private var biometric = true
    @State private var language = "English"

    var body: some View {
        NavigationView {
            List {
                // Profile
                Section {
                    HStack(spacing: 14) {
                        AvatarView(name: appState.currentStaff.name, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(appState.currentStaff.name)
                                .font(.headline)
                            Text(appState.currentStaff.role)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if let staff = appState.serverStaff {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2)
                                    Text(staff.email)
                                }
                                .font(.caption)
                                .foregroundColor(Theme.success)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Credentials
                Section(header: Text("Credentials")) {
                    ForEach(MockData.credentials) { cred in
                        HStack {
                            credIcon(cred.status)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cred.name).font(.subheadline)
                                Text(cred.detail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Sync Status (passive — auto-sync handles everything)
                Section(header: Text("Sync Status"),
                        footer: Text("Data syncs automatically when you're online. Items created offline will sync as soon as connectivity is restored.")) {
                    // Connection status
                    HStack {
                        Label("Connection", systemImage: appState.effectivelyOnline ? "wifi" : "wifi.slash")
                        Spacer()
                        Text(appState.effectivelyOnline ? "Online" : "Offline")
                            .foregroundColor(appState.effectivelyOnline ? Theme.success : Theme.danger)
                            .font(.subheadline.weight(.medium))
                    }
                    // Pending items
                    HStack {
                        Label("Pending items", systemImage: "tray.full")
                        Spacer()
                        Text("\(appState.pendingSyncCount)")
                            .foregroundColor(appState.pendingSyncCount > 0 ? Theme.warning : Theme.success)
                            .font(.headline)
                    }
                    // Last sync
                    HStack {
                        Label("Last sync", systemImage: "clock")
                        Spacer()
                        Text(appState.lastSyncRelativeText)
                            .foregroundColor(.secondary)
                    }
                    // Sync status / manual fallback
                    if appState.isSyncing {
                        HStack {
                            ProgressView().scaleEffect(0.8)
                            Text("Syncing…")
                        }
                    } else if appState.pendingSyncCount > 0 && appState.effectivelyOnline {
                        Button(action: { appState.syncNow() }) {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }

                // Notifications
                Section(header: Text("Notifications")) {
                    Toggle("Visit reminders", isOn: $visitReminders)
                    Toggle("Open shift alerts", isOn: $openShiftAlerts)
                    Toggle("Documentation reminders", isOn: $docReminders)
                }

                // Settings
                Section(header: Text("Settings")) {
                    Toggle("Face ID / Touch ID sign-in", isOn: $biometric)
                    Picker("Language", selection: $language) {
                        Text("English").tag("English")
                        Text("Español").tag("Español")
                    }
                }

                // Server mode controls
                if appState.mode == .server {
                    Section(header: Text("Server"),
                            footer: Text("Offline queue: \(appState.offlineQueue.count) action(s) pending.")) {
                        Button(action: {
                            Task { await appState.refreshServerShifts() }
                        }) {
                            Label("Refresh Shifts", systemImage: "arrow.clockwise")
                        }
                    }
                }

                // Demo controls (only in mock mode)
                if appState.mode == .mock {
                    Section(header: Text("Demo"), footer: Text("GPS: when on, the next clock-in can’t capture GPS and asks for a manually entered service address, flagging the visit for manager review.\n\nOffline: simulates loss of connectivity. Pending items queue up and auto-sync when toggled back off.")) {
                        Toggle("Simulate GPS unavailable", isOn: $appState.simulateGPSUnavailable)
                        Toggle("Simulate offline", isOn: $appState.simulateOffline)
                    }

                    Section(header: Text("Demo — Note Reminders"),
                            footer: Text("Notes are due the same day as the visit. In real use, a reminder fires at 7:00 PM if a note is still open, and again at midnight when it becomes late. These buttons fire the same notifications instantly.")) {
                        Button(action: { appState.sendTestNoteReminder(late: false) }) {
                            Label("Send end-of-day reminder now", systemImage: "bell.badge")
                        }
                        Button(action: { appState.sendTestNoteReminder(late: true) }) {
                            Label("Send \"note is late\" alert now", systemImage: "bell.badge.waveform")
                                .foregroundColor(Theme.danger)
                        }
                    }
                }

                // Sign out
                Section {
                    Button(role: .destructive, action: { appState.signOut() }) {
                        HStack {
                            Spacer()
                            Text("Sign Out").font(.headline)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("More")
        }
        .navigationViewStyle(.stack)
    }

    private func credIcon(_ status: CredentialStatus) -> some View {
        Group {
            switch status {
            case .valid:
                Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.success)
            case .expiringSoon:
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.warning)
            case .expired:
                Image(systemName: "xmark.circle.fill").foregroundColor(Theme.danger)
            }
        }
        .font(.title3)
    }
}
