import SwiftUI

struct UnscheduledVisitSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClients: Set<UUID> = []
    @State private var service: ServiceType = .inHomeSupport
    @State private var showSuccess = false

    private var chosenClients: [Client] {
        MockData.clients.filter { selectedClients.contains($0.id) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Client(s)"), footer: Text("Select more than one for a group (1:2) visit.")) {
                    ForEach(MockData.clients) { client in
                        Button(action: { toggle(client) }) {
                            HStack {
                                AvatarView(name: client.name, size: 36)
                                VStack(alignment: .leading) {
                                    Text(client.name).foregroundColor(.primary)
                                    Text(client.city).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedClients.contains(client.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Theme.success)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("Service")) {
                    Picker("Service", selection: $service) {
                        ForEach(ServiceType.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Button(action: startVisit) {
                        Label("Clock In Now", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(selectedClients.isEmpty)

                    Button(action: quickPunch) {
                        Label("Quick Punch (details later)", systemImage: "bolt.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Unscheduled Visit")
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

    private func toggle(_ client: Client) {
        if selectedClients.contains(client.id) {
            selectedClients.remove(client.id)
        } else {
            selectedClients.insert(client.id)
        }
    }

    private func startVisit() {
        appState.startUnscheduledVisit(clients: chosenClients, service: service)
        showSuccess = true
    }

    private func quickPunch() {
        let client = chosenClients.isEmpty ? [MockData.clients[0]] : chosenClients
        appState.startUnscheduledVisit(clients: client, service: service)
        showSuccess = true
    }
}
