import SwiftUI

struct MoreView: View {
    @EnvironmentObject var appState: AppState
    @State private var visitReminders = true
    @State private var openShiftAlerts = true
    @State private var docReminders = true
    @State private var biometric = true
    @State private var language = "English"

    private var lastSyncText: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: appState.lastSync)
    }

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
                            Text("Programs: In-Home, Community, Respite")
                                .font(.caption)
                                .foregroundColor(.secondary)
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

                // Sync Center
                Section(header: Text("Sync Center")) {
                    HStack {
                        Label("Pending items", systemImage: "tray.full")
                        Spacer()
                        Text("\(appState.pendingSyncCount)")
                            .foregroundColor(appState.pendingSyncCount > 0 ? Theme.warning : Theme.success)
                            .font(.headline)
                    }
                    HStack {
                        Label("Last sync", systemImage: "clock")
                        Spacer()
                        Text(lastSyncText).foregroundColor(.secondary)
                    }
                    Button(action: { appState.syncNow() }) {
                        if appState.isSyncing {
                            HStack {
                                ProgressView().scaleEffect(0.8)
                                Text("Syncing…")
                            }
                        } else {
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

                // Demo controls
                Section(header: Text("Demo"), footer: Text("When on, the next clock-in can't capture GPS and asks for a manually entered service address, flagging the visit for manager review.")) {
                    Toggle("Simulate GPS unavailable", isOn: $appState.simulateGPSUnavailable)
                }

                Section(header: Text("Demo — Note Reminders"),
                        footer: Text("Notes are due the same day as the visit. In real use, a reminder fires at 7:00 PM if a note is still open, and again at midnight when it becomes late. These buttons fire the same notifications instantly.")) {
                    Button(action: { appState.sendTestNoteReminder(late: false) }) {
                        Label("Send end-of-day reminder now", systemImage: "bell.badge")
                    }
                    Button(action: { appState.sendTestNoteReminder(late: true) }) {
                        Label("Send “note is late” alert now", systemImage: "bell.badge.waveform")
                            .foregroundColor(Theme.danger)
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
