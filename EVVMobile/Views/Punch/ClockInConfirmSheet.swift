import SwiftUI

struct ClockInConfirmSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let visit: Visit
    @State private var selectedClients: Set<UUID>
    @State private var showSuccess = false
    /// Build 57: success cover text — "Clocked in h:mm" for a confirmed punch,
    /// the queued wording when the punch is waiting for a connection.
    @State private var successMessage: String?
    /// Build 57: the request is in flight — button shows a spinner, sheet
    /// cannot be dismissed, Cancel disabled. Success is shown ONLY after the
    /// server confirms (or the punch is durably queued).
    @State private var isSubmitting = false
    /// Build 57: the server REFUSED the punch (4xx). Rendered inline in red
    /// with the server's own message; the sheet stays open. Before build 57
    /// the only error surface was RootView's alert, which cannot present
    /// behind this sheet + the success cover — so a 409 looked like success.
    @State private var submitError: String?

    // Manual address entry (GPS-unavailable fallback)
    @State private var manualStreet = ""
    @State private var manualCity = ""
    @State private var manualState = ""
    @State private var manualZip = ""
    @State private var isAcquiringLocation = false
    @State private var locationReady = false
    @ObservedObject private var locationManager = LocationManager.shared

    private var gpsUnavailable: Bool {
        appState.simulateGPSUnavailable ||
        locationManager.authorizationStatus == .denied ||
        locationManager.authorizationStatus == .restricted ||
        (!isAcquiringLocation && !locationReady && locationManager.locationError != nil)
    }

    private var manualAddressValid: Bool {
        !manualCity.trimmingCharacters(in: .whitespaces).isEmpty &&
        !manualState.trimmingCharacters(in: .whitespaces).isEmpty &&
        !manualZip.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// One active visit at a time — no new clock-in while a visit is running.
    private var punchBlocked: Bool { appState.hasActiveVisit }

    // Block confirm while a GPS fix is still being acquired so the punch
    // carries real coordinates (acquisition is bounded by a 10s timeout),
    // and always block while another visit is running.
    private var canConfirm: Bool { !punchBlocked && !isAcquiringLocation && !isSubmitting && (!gpsUnavailable || manualAddressValid) }

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
                            if isAcquiringLocation {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Acquiring location…")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                Circle().fill(gpsUnavailable ? Theme.danger : Theme.success)
                                    .frame(width: 8, height: 8)
                                Text(gpsUnavailable ? "GPS unavailable" : "Location acquired")
                                    .font(.subheadline)
                                    .foregroundColor(gpsUnavailable ? Theme.danger : .primary)
                            }
                        }
                    }
                }
                .cardStyle()
                .padding(.horizontal)

                if gpsUnavailable && !punchBlocked {
                    manualAddressCard
                }

                if punchBlocked {
                    Label("Clock out of your current visit first.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.danger)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Theme.danger.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.horizontal)
                }

                if let err = submitError {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.danger)
                        Text("You were NOT clocked in. Nothing was saved.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.danger.opacity(0.08))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .accessibilityIdentifier("clockInRejected")
                }

                Spacer(minLength: 12)

                Button(action: confirm) {
                    if isSubmitting {
                        HStack {
                            ProgressView().tint(.white)
                            Text("Clocking in…")
                        }
                    } else {
                        Label("Confirm Clock In", systemImage: "checkmark.circle.fill")
                    }
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
                    Button("Cancel") { dismiss() }.disabled(isSubmitting)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
            .fullScreenCover(isPresented: $showSuccess, onDismiss: { dismiss() }) {
                ClockInSuccessView(message: successMessage)
            }
            .task {
                // Acquire GPS location when the sheet appears
                if !appState.simulateGPSUnavailable {
                    isAcquiringLocation = true
                    let loc = await locationManager.acquireLocation()
                    isAcquiringLocation = false
                    locationReady = loc != nil
                }
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
        guard !isSubmitting else { return }
        // Guard against stale UI: never start while another visit is running.
        guard !appState.hasActiveVisit else {
            appState.surfacePunchBlocked()
            return
        }
        var location: ManualLocation?
        if gpsUnavailable {
            guard manualAddressValid else { return }
            location = ManualLocation(street: manualStreet.trimmingCharacters(in: .whitespaces),
                                      city: manualCity.trimmingCharacters(in: .whitespaces),
                                      state: manualState.trimmingCharacters(in: .whitespaces),
                                      zip: manualZip.trimmingCharacters(in: .whitespaces))
        }
        isSubmitting = true
        submitError = nil
        Task { @MainActor in
            // Build 57: success ONLY after the server confirms (or the punch is
            // durably queued). A refusal keeps the sheet open with the server's
            // message — the 2026-09-02 "Clocked in 5:17 PM" over a 409 must not
            // recur. The serverShiftId hint survives a background refresh that
            // regenerates the row UUIDs under this open sheet.
            let outcome = await appState.clockIn(visitId: visit.id,
                                                 serverShiftId: visit.serverShiftId,
                                                 manualLocation: location)
            isSubmitting = false
            switch outcome {
            case .synced:
                successMessage = nil          // "Clocked in h:mm a"
                showSuccess = true
            case .queued:
                successMessage = "Clock-in saved — will sync when online"
                showSuccess = true
            case .rejected(let message):
                submitError = message
            }
        }
    }
}
