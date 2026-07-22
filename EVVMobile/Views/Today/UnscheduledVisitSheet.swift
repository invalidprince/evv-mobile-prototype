import SwiftUI

struct UnscheduledVisitSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showSuccess = false

    var body: some View {
        if appState.mode == .server {
            ServerUnscheduledContent(showSuccess: $showSuccess, onDismiss: { dismiss() })
                .environmentObject(appState)
        } else {
            MockUnscheduledContent(showSuccess: $showSuccess, onDismiss: { dismiss() })
                .environmentObject(appState)
        }
    }
}

// MARK: - Server Mode (real individuals from API)

struct ServerUnscheduledContent: View {
    @EnvironmentObject var appState: AppState
    @Binding var showSuccess: Bool
    let onDismiss: () -> Void
    @State private var selectedIndividualId: String?
    @State private var service: ServiceType = .inHomeSupport
    @State private var searchText = ""

    /// The selected individual's authorized services
    private var authorizedServices: [ServiceType] {
        guard let id = selectedIndividualId,
              let individual = appState.serverIndividuals.first(where: { $0.id == id }),
              let services = individual.services, !services.isEmpty else {
            return ServiceType.allCases
        }
        return ServiceType.allCases.filter { st in
            services.contains(st.rawValue)
        }
    }

    private var filteredIndividuals: [ServerIndividualOption] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return appState.serverIndividuals }
        return appState.serverIndividuals.filter { $0.name.lowercased().contains(trimmed) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Individual"), footer: Text("Select the individual for this unscheduled visit.")) {
                    if appState.isLoadingIndividuals {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading individuals…")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else if appState.serverIndividuals.isEmpty {
                        Text("No active individuals found")
                            .foregroundColor(.secondary)
                    } else {
                        TextField("Search…", text: $searchText)
                            .textFieldStyle(.roundedBorder)

                        ForEach(filteredIndividuals) { individual in
                            Button(action: {
                                selectedIndividualId = individual.id
                                // Auto-select first authorized service when individual changes
                                let auths = authorizedServicesFor(individual)
                                if !auths.isEmpty && !auths.contains(service) {
                                    service = auths[0]
                                }
                            }) {
                                HStack {
                                    AvatarView(name: individual.name, size: 36)
                                    VStack(alignment: .leading) {
                                        Text(individual.name).foregroundColor(.primary)
                                        if let services = individual.services, !services.isEmpty {
                                            Text(services.joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if selectedIndividualId == individual.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Theme.success)
                                    }
                                }
                            }
                        }
                    }
                }

                Section(header: Text("Service"), footer: selectedIndividualId != nil && authorizedServices.isEmpty ? Text("This individual has no authorized services.").foregroundColor(Theme.danger) : nil) {
                    if authorizedServices.isEmpty && selectedIndividualId != nil {
                        Text("No authorized services")
                            .foregroundColor(.secondary)
                    } else {
                        Picker("Service", selection: $service) {
                            ForEach(authorizedServices) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                Section {
                    Button(action: startVisit) {
                        Label("Clock In Now", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(selectedIndividualId == nil || authorizedServices.isEmpty)
                }
            }
            .navigationTitle("Unscheduled Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
            .fullScreenCover(isPresented: $showSuccess, onDismiss: { onDismiss() }) {
                ClockInSuccessView()
            }
            .onAppear {
                if appState.serverIndividuals.isEmpty {
                    Task { await appState.refreshIndividuals() }
                }
            }
        }
    }

    /// Compute authorized services for a specific individual
    private func authorizedServicesFor(_ individual: ServerIndividualOption) -> [ServiceType] {
        guard let services = individual.services, !services.isEmpty else {
            return ServiceType.allCases
        }
        return ServiceType.allCases.filter { st in
            services.contains(st.rawValue)
        }
    }

    private func startVisit() {
        guard let individualId = selectedIndividualId,
              let individual = appState.serverIndividuals.first(where: { $0.id == individualId }) else { return }

        // Build a Client from the server individual; store server ID in address field
        let client = Client(
            id: UUID(),
            name: individual.name,
            address: individual.id,  // server individual ID for API call
            city: ""
        )
        appState.startUnscheduledVisit(clients: [client], service: service)
        showSuccess = true
    }
}

// MARK: - Mock Mode (existing demo data)

struct MockUnscheduledContent: View {
    @EnvironmentObject var appState: AppState
    @Binding var showSuccess: Bool
    let onDismiss: () -> Void
    @State private var selectedClients: Set<UUID> = []
    @State private var service: ServiceType = .inHomeSupport
    @State private var searchText = ""

    private let maxIndividuals = 2  // 2:1 shifts are the max

    private var chosenClients: [Client] {
        MockData.clients.filter { selectedClients.contains($0.id) }
    }

    private var filteredClients: [Client] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return MockData.clients }
        return MockData.clients.filter { $0.name.lowercased().contains(trimmed) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Client(s)"), footer: Text("Select up to \(maxIndividuals) for a group (1:2) visit.")) {
                    TextField("Search…", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    ForEach(filteredClients) { client in
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
                                } else if selectedClients.count >= maxIndividuals {
                                    // Show disabled state when at cap
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary.opacity(0.3))
                                }
                            }
                        }
                        .disabled(!selectedClients.contains(client.id) && selectedClients.count >= maxIndividuals)
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
                    Button("Cancel") { onDismiss() }
                }
            }
            .fullScreenCover(isPresented: $showSuccess, onDismiss: { onDismiss() }) {
                ClockInSuccessView()
            }
        }
    }

    private func toggle(_ client: Client) {
        if selectedClients.contains(client.id) {
            selectedClients.remove(client.id)
        } else if selectedClients.count < maxIndividuals {
            selectedClients.insert(client.id)
        }
        // If at max, tapping an unselected client does nothing (button is disabled)
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
