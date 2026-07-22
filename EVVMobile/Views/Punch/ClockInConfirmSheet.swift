import SwiftUI

struct ClockInConfirmSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let visit: Visit
    @State private var selectedClients: Set<UUID>
    @State private var showSuccess = false

    // Manual address entry (GPS-unavailable fallback)
    @State private var manualStreet = ""
    @State private var manualCity = ""
    @State private var manualState = ""
    @State private var manualZip = ""

    private var gpsUnavailable: Bool { appState.simulateGPSUnavailable }

    private var manualAddressValid: Bool {
        !manualCity.trimmingCharacters(in: .whitespaces).isEmpty &&
        !manualState.trimmingCharacters(in: .whitespaces).isEmpty &&
        !manualZip.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canConfirm: Bool { !gpsUnavailable || manualAddressValid }

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
            ScrollView {
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
                        Label("GPS", systemImage: gpsUnavailable ? "location.slash.fill" : "location.fill")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(gpsUnavailable ? Theme.danger : Theme.success)
                                .frame(width: 8, height: 8)
                            Text(gpsUnavailable ? "GPS unavailable" : "Location acquired")
                                .font(.subheadline)
                                .foregroundColor(gpsUnavailable ? Theme.danger : .primary)
                        }
                    }
                }
                .cardStyle()
                .padding(.horizontal)

                if gpsUnavailable {
                    manualAddressCard
                }

                Spacer(minLength: 12)

                Button(action: confirm) {
                    Label("Confirm Clock In", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.success, enabled: canConfirm))
                .disabled(!canConfirm)
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
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

    private var manualAddressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Enter Service Address", systemImage: "mappin.and.ellipse")
                .font(.headline)
            Text("GPS couldn't be captured. Enter the address where this service is being provided.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Street address (optional)", text: $manualStreet)
                .textFieldStyle(.roundedBorder)
            TextField("City *", text: $manualCity)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                TextField("State *", text: $manualState)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 100)
                TextField("Zip code *", text: $manualZip)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
            }

            Label("This visit will be flagged for manager review.", systemImage: "flag.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.warning)
        }
        .cardStyle()
        .padding(.horizontal)
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

    private let maxClients = 2  // 1:2 group visits are the max

    private func toggle(_ client: Client) {
        if selectedClients.contains(client.id) {
            if selectedClients.count > 1 { selectedClients.remove(client.id) }
        } else if selectedClients.count < maxClients {
            selectedClients.insert(client.id)
        }
    }

    private func confirm() {
        var location: ManualLocation?
        if gpsUnavailable {
            guard manualAddressValid else { return }
            location = ManualLocation(street: manualStreet.trimmingCharacters(in: .whitespaces),
                                      city: manualCity.trimmingCharacters(in: .whitespaces),
                                      state: manualState.trimmingCharacters(in: .whitespaces),
                                      zip: manualZip.trimmingCharacters(in: .whitespaces))
        }
        appState.clockIn(visitId: visit.id, manualLocation: location)
        showSuccess = true
    }
}
