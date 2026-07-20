import SwiftUI

struct ShiftDetailView: View {
    let visit: Visit
    @State private var showContactAlert = false

    private var timeWindow: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d · h:mm a"
        let f2 = DateFormatter()
        f2.dateFormat = "h:mm a"
        return "\(f.string(from: visit.scheduledStart)) – \(f2.string(from: visit.scheduledEnd))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Map placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Theme.primary.opacity(0.08))
                        .frame(height: 180)
                    VStack(spacing: 8) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 40))
                            .foregroundColor(Theme.primary.opacity(0.5))
                        Text("Map preview")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                    if let loc = visit.serverLocation, !loc.isEmpty {
                        Label(loc, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                    } else {
                        Label(visit.client.fullAddress, systemImage: "mappin.and.ellipse")
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
                    Button(action: {}) {
                        Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button(action: { showContactAlert = true }) {
                        Label("Contact Supervisor", systemImage: "phone.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Shift Notes")
                        .font(.headline)
                    Text(visit.notes.isEmpty
                         ? "Client prefers morning routine before activities. Check communication log on arrival. Medication reminder at visit midpoint."
                         : visit.notes)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .cardStyle()
            }
            .padding(16)
        }
        .background(Theme.screenBackground.ignoresSafeArea())
        .navigationTitle("Shift Detail")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Contact Supervisor", isPresented: $showContactAlert) {
            Button("Call Tanya Ruiz") {}
            Button("Message Tanya Ruiz") {}
            Button("Cancel", role: .cancel) {}
        }
    }
}
