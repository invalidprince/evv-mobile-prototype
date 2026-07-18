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
