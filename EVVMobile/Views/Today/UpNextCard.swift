import SwiftUI

struct UpNextCard: View {
    @EnvironmentObject var appState: AppState
    let visit: Visit
    let onClockIn: () -> Void

    private var timeWindow: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "\(f.string(from: visit.scheduledStart)) – \(f.string(from: visit.scheduledEnd))"
    }

    private var isBlocked: Bool { appState.activeVisit != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(timeWindow)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.primary)
                Spacer()
                if visit.ratio == "2:1" {
                    StatusBadge(text: "2:1", color: Theme.primary)
                }
                if visit.isGroup {
                    StatusBadge(text: "GROUP 1:2", color: Theme.primary)
                } else if visit.teamStaff != nil && visit.ratio == nil {
                    StatusBadge(text: "TEAM 2:1", color: Theme.primary)
                }
            }

            HStack(spacing: 12) {
                AvatarView(name: visit.client.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(visit.clients.map { $0.name }.joined(separator: " & "))
                        .font(.headline)
                    Text(visit.service.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Label(visit.client.fullAddress, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            if !visit.partners.isEmpty {
                ForEach(visit.partners, id: \.staffId) { partner in
                    Label("With: \(partner.name)", systemImage: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let partner = visit.teamStaff {
                Label("With: \(partner.name)", systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: onClockIn) {
                Label(isBlocked ? "Clock out first" : "Clock In", systemImage: "play.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.success, enabled: !isBlocked))
            .disabled(isBlocked)
        }
        .cardStyle()
    }
}
