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
    @State private var selectedIndividualIds: Set<String> = []
    @State private var service: ServiceType = .inHomeSupport
    @State private var searchText = ""

    private let maxIndividuals = 2  // 1:2 group visits are the max

    /// Authorized services = intersection of all selected individuals' services.
    /// If none selected, show all. If intersection is empty, show nothing.
    private var authorizedServices: [ServiceType] {
        guard !selectedIndividualIds.isEmpty else { return ServiceType.allCases }

        let selectedIndividuals = appState.serverIndividuals.filter { selectedIndividualIds.contains($0.id) }
        guard !selectedIndividuals.isEmpty else { return ServiceType.allCases }

        // Start with first individual's services, intersect with each subsequent
        var intersection: Set<String>? = nil
        for individual in selectedIndividuals {
            let services = (individual.services != nil && !individual.services!.isEmpty)
                ? Set(individual.services!) : Set(ServiceType.allCases.map { $0.rawValue })
            if intersection == nil {
                intersection = services
            } else {
                intersection = intersection!.intersection(services)
            }
        }

        guard let final = intersection else { return ServiceType.allCases }
        return ServiceType.allCases.filter { final.contains($0.rawValue) }
    }

    private var filteredIndividuals: [ServerIndividualOption] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return appState.serverIndividuals }
        return appState.serverIndividuals.filter { $0.name.lowercased().contains(trimmed) }
    }

    /// Message when selected individuals have no common services
    private var noCommonServicesMessage: String? {
        guard selectedIndividualIds.count > 1, authorizedServices.isEmpty else { return nil }
        let names = appState.serverIndividuals
            .filter { selectedIndividualIds.contains($0.id) }
            .map { $0.name }
            .joined(separator: " and ")
        return "\(names) have no services in common. Remove one to continue."
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Individual(s)"), footer: Text("Select up to \(maxIndividuals) for a group (1:2) visit.")) {
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
                            Button(action: { toggleIndividual(individual) }) {
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
                                    if selectedIndividualIds.contains(individual.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Theme.success)
                                    } else if selectedIndividualIds.count >= maxIndividuals {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary.opacity(0.3))
                                    }
                                }
                            }
                            .disabled(!selectedIndividualIds.contains(individual.id) && selectedIndividualIds.count >= maxIndividuals)
                        }
                    }
                }

                Section(header: Text("Service"), footer: noCommonServicesMessage.map { Text($0).foregroundColor(Theme.danger) }) {
                    if noCommonServicesMessage != nil {
                        Text("No common authorized services")
                            .foregroundColor(.secondary)
                    } else if authorizedServices.isEmpty && !selectedIndividualIds.isEmpty {
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
                    .disabled(selectedIndividualIds.isEmpty || authorizedServices.isEmpty)
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

    private func toggleIndividual(_ individual: ServerIndividualOption) {
        if selectedIndividualIds.contains(individual.id) {
            selectedIndividualIds.remove(individual.id)
        } else if selectedIndividualIds.count < maxIndividuals {
            selectedIndividualIds.insert(individual.id)
        }
        // Auto-select first authorized service if current selection isn't in intersection
        if !authorizedServices.isEmpty && !authorizedServices.contains(service) {
            service = authorizedServices[0]
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
        let selectedIndividuals = appState.serverIndividuals.filter { selectedIndividualIds.contains($0.id) }
        guard !selectedIndividuals.isEmpty else { return }

        // Build Clients from the server individuals; store server ID in address field
        let clients = selectedIndividuals.map { individual in
            Client(
                id: UUID(),
                name: individual.name,
                address: individual.id,  // server individual ID for API call
                city: ""
            )
        }
        appState.startUnscheduledVisit(clients: clients, service: service)
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
