import SwiftUI

struct ClockInConfirmSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let visit: Visit
    @State private var selectedClients: Set<UUID>
    @State private var showSuccess = false

    init(visit: Visit) {
        self.visit = visit
        _selectedClients = State(initialValue: Set(visit.clients.map { $0.id }))
    }

    private var timeText: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: Date())
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    AvatarView(name: visit.client.name, size: 64)
                    Text(visit.clients.map { $0.name }.joined(separator: " & "))
                        .font(.title3.bold())
                    Text(visit.service.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 24)

                if let partner = visit.teamStaff {
                    Label("Clocking in: You + \(partner.name)", systemImage: "person.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Theme.primary.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.horizontal)
                }

                if visit.isGroup {
                    groupClientPicker
                }

                VStack(spacing: 12) {
                    HStack {
                        Label("Time", systemImage: "clock.fill")
                        Spacer()
                        Text(timeText).font(.headline)
                    }
                    Divider()
                    HStack {
                        Label("GPS", systemImage: "location.fill")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(Theme.success).frame(width: 8, height: 8)
                            Text("Location acquired").font(.subheadline)
                        }
                    }
                }
                .cardStyle()
                .padding(.horizontal)

                Spacer()

                Button(action: confirm) {
                    Label("Confirm Clock In", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.success))
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .background(Theme.screenBackground.ignoresSafeArea())
            .navigationTitle("Clock In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showSuccess, onDismiss: { dismiss() }) {
                ClockInSuccessView()
            }
        }
    }

    private var groupClientPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Group visit — confirm clients present:")
                .font(.subheadline.weight(.semibold))
            ForEach(visit.clients) { client in
                Button(action: { toggle(client) }) {
                    HStack {
                        Text(client.name).foregroundColor(.primary)
                        Spacer()
                        Image(systemName: selectedClients.contains(client.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedClients.contains(client.id) ? Theme.success : .secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .cardStyle()
        .padding(.horizontal)
    }

    private func toggle(_ client: Client) {
        if selectedClients.contains(client.id) {
            if selectedClients.count > 1 { selectedClients.remove(client.id) }
        } else {
            selectedClients.insert(client.id)
        }
    }

    private func confirm() {
        appState.clockIn(visitId: visit.id)
        showSuccess = true
    }
}
