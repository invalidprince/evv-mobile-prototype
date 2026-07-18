import SwiftUI

struct ShiftRow: View {
    let visit: Visit

    private var timeWindow: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "\(f.string(from: visit.scheduledStart)) – \(f.string(from: visit.scheduledEnd))"
    }

    private var statusColor: Color {
        switch visit.status {
        case .scheduled: return Theme.primary
        case .inProgress: return Theme.success
        case .completed: return .secondary
        case .missed: return Theme.danger
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(timeWindow)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.primary)
                Spacer()
                StatusBadge(text: visit.status.rawValue.uppercased(), color: statusColor)
            }
            HStack(spacing: 12) {
                AvatarView(name: visit.client.name, size: 40)
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
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .cardStyle()
    }
}

struct OpenShiftsSection: View {
    @EnvironmentObject var appState: AppState

    private func window(_ shift: OpenShift) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE M/d, h:mm a"
        let f2 = DateFormatter()
        f2.dateFormat = "h:mm a"
        return "\(f.string(from: shift.start)) – \(f2.string(from: shift.end))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Open Shifts")
                .font(.title3.bold())
                .padding(.top, 8)

            ForEach(appState.openShifts) { shift in
                VStack(alignment: .leading, spacing: 10) {
                    Text(window(shift))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.primary)
                    HStack(spacing: 12) {
                        AvatarView(name: shift.client.name, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shift.client.name).font(.headline)
                            Text(shift.service.rawValue)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    HStack(spacing: 12) {
                        Button("Accept") { appState.acceptOpenShift(shift) }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.success)
                            .cornerRadius(10)
                        Button("Decline") { appState.declineOpenShift(shift) }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Theme.danger)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.danger.opacity(0.1))
                            .cornerRadius(10)
                    }
                }
                .cardStyle()
            }
        }
    }
}
