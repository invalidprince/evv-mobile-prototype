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
    @State private var selectedServiceName: String = ""
    @State private var searchText = ""
    // F2: Unlisted individual
    @State private var isUnlisted = false
    @State private var unlistedName = ""
    @State private var unlistedServiceName: String = ""

    private let maxIndividuals = 2  // 1:2 group visits are the max

    /// Footer for the Individual(s) section — shows cache date hint when offline.
    private var cachedFooter: some View {
        Group {
            if isUnlisted {
                Text("Enter the individual's name manually.")
            } else if let cacheDate = appState.individualsFromCacheDate {
                let f = RelativeDateTimeFormatter()
                Text("Cached \(f.localizedString(for: cacheDate, relativeTo: Date())) \u{2022} Select up to \(maxIndividuals) for a group (1:2) visit.")
                    .foregroundColor(.secondary)
            } else {
                Text("Select up to \(maxIndividuals) for a group (1:2) visit.")
            }
        }
    }

    /// Authorized services = intersection of all selected individuals' service descriptions.
    /// If none selected, show empty (must select an individual first).
    private var authorizedServices: [String] {
        guard !selectedIndividualIds.isEmpty else { return [] }

        let selectedIndividuals = appState.serverIndividuals.filter { selectedIndividualIds.contains($0.id) }
        guard !selectedIndividuals.isEmpty else { return [] }

        // Start with first individual's services, intersect with each subsequent
        var intersection: Set<String>? = nil
        for individual in selectedIndividuals {
            let services = individual.services ?? []
            if services.isEmpty { continue }
            let svcSet = Set(services)
            if intersection == nil {
                intersection = svcSet
            } else {
                intersection = intersection!.intersection(svcSet)
            }
        }

        guard let final = intersection else { return [] }
        return final.sorted()
    }

    /// All available services (for unlisted individual — show every service from all individuals)
    private var allAvailableServices: [String] {
        var allSvcs = Set<String>()
        for individual in appState.serverIndividuals {
            for svc in (individual.services ?? []) {
                allSvcs.insert(svc)
            }
        }
        return allSvcs.sorted()
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
                Section(header: Text("Individual(s)"), footer: cachedFooter) {

                    // F2: Unlisted Individual toggle
                    Button(action: {
                        withAnimation {
                            isUnlisted.toggle()
                            if isUnlisted {
                                selectedIndividualIds.removeAll()
                                selectedServiceName = ""
                            } else {
                                unlistedName = ""
                                unlistedServiceName = ""
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: isUnlisted ? "person.fill.questionmark" : "person.fill.questionmark")
                                .foregroundColor(isUnlisted ? .white : Theme.primary)
                                .font(.title3)
                            Text("Unlisted Individual")
                                .foregroundColor(isUnlisted ? .white : .primary)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if isUnlisted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, isUnlisted ? 10 : 0)
                        .background(isUnlisted ? Theme.primary : Color.clear)
                        .cornerRadius(8)
                    }

                    if isUnlisted {
                        TextField("Enter individual name", text: $unlistedName)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        if appState.isLoadingIndividuals && appState.serverIndividuals.isEmpty {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Loading individuals…")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        } else if appState.serverIndividuals.isEmpty && !appState.effectivelyOnline {
                            // Offline with no cached data
                            VStack(spacing: 6) {
                                Image(systemName: "wifi.slash")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Text("Connect to the internet once to load individuals")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 8)
                        } else if appState.serverIndividuals.isEmpty {
                            Text("No active individuals found")
                                .foregroundColor(.secondary)
                        } else {
                            TextField("Search…", text: $searchText)
                                .textFieldStyle(.roundedBorder)

                            // Constrained list: max ~4 visible rows (each ~56pt)
                            ScrollView {
                                LazyVStack(spacing: 0) {
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
                                            .padding(.vertical, 10)
                                        }
                                        .disabled(!selectedIndividualIds.contains(individual.id) && selectedIndividualIds.count >= maxIndividuals)

                                        Divider()
                                    }
                                }
                            }
                            .frame(maxHeight: 224) // ~4 rows × 56pt each
                        }
                    }
                }

                Section(header: Text("Service"), footer: noCommonServicesMessage.map { Text($0).foregroundColor(Theme.danger) }) {
                    if isUnlisted {
                        // F2: Show all available services for unlisted individual
                        if allAvailableServices.isEmpty && !appState.effectivelyOnline {
                            VStack(spacing: 6) {
                                Image(systemName: "wifi.slash")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Text("Connect to the internet once to load services")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 4)
                        } else if allAvailableServices.isEmpty {
                            Text("No services available")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        } else {
                            Picker("Service", selection: $unlistedServiceName) {
                                ForEach(allAvailableServices, id: \.self) { svcName in
                                    Text(svcName).tag(svcName)
                                }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                    } else if noCommonServicesMessage != nil {
                        Text("No common authorized services")
                            .foregroundColor(.secondary)
                    } else if !selectedIndividualIds.isEmpty && authorizedServices.isEmpty && !appState.effectivelyOnline {
                        VStack(spacing: 6) {
                            Image(systemName: "wifi.slash")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Text("Connect to the internet once to load services")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 4)
                    } else if !selectedIndividualIds.isEmpty && authorizedServices.isEmpty {
                        Text("No authorized services")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else if selectedIndividualIds.isEmpty {
                        Text("Select an individual first")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        Picker("Service", selection: $selectedServiceName) {
                            ForEach(authorizedServices, id: \.self) { svcName in
                                Text(svcName).tag(svcName)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                Section {
                    if isUnlisted {
                        // F2: Unlisted clock-in
                        Button(action: startUnlistedVisit) {
                            Label("Clock In Now", systemImage: "play.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(unlistedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unlistedServiceName.isEmpty)
                    } else {
                        Button(action: startVisit) {
                            Label("Clock In Now", systemImage: "play.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(selectedIndividualIds.isEmpty || selectedServiceName.isEmpty)

                        // "Clock In Without Service" fallback
                        if !selectedIndividualIds.isEmpty && authorizedServices.isEmpty {
                            Button(action: startVisitWithoutService) {
                                Label("Clock In Without Service", systemImage: "exclamationmark.triangle.fill")
                                    .frame(maxWidth: .infinity)
                                    .foregroundColor(.orange)
                            }
                        }
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
            .onAppear {
                // Always attempt a refresh; refreshIndividuals handles offline fallback
                Task { await appState.refreshIndividuals() }
            }
        }
    }

    private func toggleIndividual(_ individual: ServerIndividualOption) {
        if selectedIndividualIds.contains(individual.id) {
            selectedIndividualIds.remove(individual.id)
        } else if selectedIndividualIds.count < maxIndividuals {
            selectedIndividualIds.insert(individual.id)
        }
        // Auto-select first authorized service if current selection isn't in the list
        if !authorizedServices.isEmpty && !authorizedServices.contains(selectedServiceName) {
            selectedServiceName = authorizedServices[0]
        }
    }

    private func startVisit() {
        let selectedIndividuals = appState.serverIndividuals.filter { selectedIndividualIds.contains($0.id) }
        guard !selectedIndividuals.isEmpty, !selectedServiceName.isEmpty else { return }

        // Build Clients from the server individuals; store server ID in address field
        let clients = selectedIndividuals.map { individual in
            Client(
                id: UUID(),
                name: individual.name,
                address: individual.id,  // server individual ID for API call
                city: ""
            )
        }
        // Map selected service description to a ServiceType for backward compat
        let serviceType = mapServiceNameToType(selectedServiceName)
        appState.startUnscheduledVisit(clients: clients, service: serviceType, serviceName: selectedServiceName)
        showSuccess = true
    }

    private func startVisitWithoutService() {
        let selectedIndividuals = appState.serverIndividuals.filter { selectedIndividualIds.contains($0.id) }
        guard !selectedIndividuals.isEmpty else { return }

        let clients = selectedIndividuals.map { individual in
            Client(
                id: UUID(),
                name: individual.name,
                address: individual.id,
                city: ""
            )
        }
        appState.startUnscheduledVisitWithoutService(clients: clients)
        showSuccess = true
    }

    // F2: Start visit for unlisted individual
    private func startUnlistedVisit() {
        let name = unlistedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !unlistedServiceName.isEmpty else { return }

        // Create a dummy Client with empty address (no server ID)
        let client = Client(id: UUID(), name: name, address: "", city: "")
        let serviceType = mapServiceNameToType(unlistedServiceName)
        appState.startUnscheduledVisit(clients: [client], service: serviceType,
                                       serviceName: unlistedServiceName, unlistedName: name)
        showSuccess = true
    }

    private func mapServiceNameToType(_ name: String) -> ServiceType {
        let lower = name.lowercased()
        if lower.contains("home") || lower.contains("in-home") { return .inHomeSupport }
        if lower.contains("community") && lower.contains("participation") { return .communityParticipation }
        if lower.contains("companion") { return .companion }
        if lower.contains("respite") { return .respite }
        return .inHomeSupport
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
