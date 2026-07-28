import SwiftUI
import MapKit
import CoreLocation

/// Identifiable wrapper for the single map annotation.
private struct ShiftMapPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct ShiftDetailView: View {
    let visit: Visit
    @State private var showContactAlert = false

    // MARK: - Map state
    @State private var mapRegion = MKCoordinateRegion()
    @State private var mapPin: ShiftMapPin?
    @State private var geocodeFailed = false
    @State private var geocodeStarted = false

    private var timeWindow: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d · h:mm a"
        let f2 = DateFormatter()
        f2.dateFormat = "h:mm a"
        return "\(f.string(from: visit.scheduledStart)) – \(f2.string(from: visit.scheduledEnd))"
    }

    /// The client's street address (mock mode includes city), if any.
    private var clientAddress: String? {
        let addr = visit.client.fullAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return addr.isEmpty ? nil : addr
    }

    /// What to show on the location row: real address first, then the
    /// (billing) location name from the server.
    private var displayAddress: String? {
        if let addr = clientAddress { return addr }
        if let loc = visit.serverLocation, !loc.isEmpty { return loc }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Map preview — shown whenever the client has an address
                if clientAddress != nil && !geocodeFailed {
                    ZStack {
                        if let pin = mapPin {
                            Map(coordinateRegion: $mapRegion, interactionModes: [], annotationItems: [pin]) { item in
                                MapMarker(coordinate: item.coordinate, tint: Theme.primary)
                            }
                            .frame(height: 180)
                            .cornerRadius(14)
                        } else {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.primary.opacity(0.08))
                                .frame(height: 180)
                            VStack(spacing: 8) {
                                ProgressView()
                                Text("Loading map…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onTapGesture { openDirections() }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        AvatarView(name: visit.client.name, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(visit.clients.map { $0.name }.joined(separator: " & "))
                                    .font(.title3.bold())
                                if visit.ratio == "2:1" {
                                    StatusBadge(text: "2:1", color: Theme.primary)
                                }
                            }
                            Text(visit.service.rawValue)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    Divider()
                    Label(timeWindow, systemImage: "clock.fill")
                        .font(.subheadline)
                    if let addr = displayAddress {
                        Label(addr, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                    }
                    if !visit.partners.isEmpty {
                        ForEach(visit.partners, id: \.staffId) { partner in
                            Label("With: \(partner.name)", systemImage: "person.2.fill")
                                .font(.subheadline)
                        }
                    } else if let partner = visit.teamStaff {
                        Label("Team visit with \(partner.name)", systemImage: "person.2.fill")
                            .font(.subheadline)
                    }
                }
                .cardStyle()

                VStack(spacing: 12) {
                    if displayAddress != nil {
                        Button(action: openDirections) {
                            Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }

                    Button(action: { showContactAlert = true }) {
                        Label("Contact Supervisor", systemImage: "phone.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                // Shift notes — only shown when the shift actually has notes
                let notes = visit.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shift Notes")
                            .font(.headline)
                        Text(notes)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .cardStyle()
                }
            }
            .padding(16)
        }
        .background(Theme.screenBackground.ignoresSafeArea())
        .navigationTitle("Shift Detail")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { geocodeIfNeeded() }
        .alert("Contact Supervisor", isPresented: $showContactAlert) {
            Button("Call Tanya Ruiz") {}
            Button("Message Tanya Ruiz") {}
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Geocoding

    private func geocodeIfNeeded() {
        guard !geocodeStarted, let addr = clientAddress else { return }
        geocodeStarted = true
        CLGeocoder().geocodeAddressString(addr) { placemarks, _ in
            DispatchQueue.main.async {
                guard let location = placemarks?.first?.location else {
                    geocodeFailed = true
                    return
                }
                let pin = ShiftMapPin(coordinate: location.coordinate)
                mapPin = pin
                mapRegion = MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 600,
                    longitudinalMeters: 600
                )
            }
        }
    }

    // MARK: - Directions

    private func openDirections() {
        guard let addr = displayAddress,
              let encoded = addr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://maps.apple.com/?daddr=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }
}
