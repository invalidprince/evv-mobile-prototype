import SwiftUI

struct HistoryRow: View {
    let visit: Visit
    let onTimeFix: () -> Void
    let onRequestDelete: () -> Void
    let onFinishNote: () -> Void

    private var dateText: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: visit.scheduledStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(dateText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.primary)
                Spacer()
                if visit.timeFixStatus != .none {
                    timeFixChip
                }
                if visit.deleteRequestStatus != .none {
                    deleteChip
                }
            }
            if visit.manualLocationFlagged {
                Label("Manual location — pending manager review", systemImage: "mappin.and.ellipse")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.warning.opacity(0.14))
                    .cornerRadius(8)
            }
            HStack(spacing: 12) {
                AvatarView(name: visit.client.name, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(visit.client.name).font(.headline)
                    Text(visit.service.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(visit.durationText)
                        .font(.headline)
                    HStack(spacing: 8) {
                        // Documentation status
                        Image(systemName: visit.docComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(visit.docComplete ? Theme.success : Theme.warning)
                            .font(.subheadline)
                        // Sync status
                        Image(systemName: visit.syncState == .synced ? "icloud.fill" : "icloud.slash")
                            .foregroundColor(visit.syncState == .synced ? Theme.success : Theme.warning)
                            .font(.subheadline)
                    }
                }
            }
            if !visit.docComplete {
                Button(action: onFinishNote) {
                    Label("Finish Note", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.warning)
                }
            }
            HStack(spacing: 20) {
                if visit.timeFixStatus == .none {
                    Button("Request Time Fix", action: onTimeFix)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Theme.primary)
                }
                if visit.deleteRequestStatus == .none {
                    Button("Request Delete", action: onRequestDelete)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Theme.danger)
                }
                Spacer()
            }
        }
        .cardStyle()
    }

    private var timeFixChip: some View {
        let (text, color): (String, Color) = {
            switch visit.timeFixStatus {
            case .pending: return ("FIX PENDING", Theme.warning)
            case .approved: return ("FIX APPROVED", Theme.success)
            case .denied: return ("FIX DENIED", Theme.danger)
            case .none: return ("", .clear)
            }
        }()
        return StatusBadge(text: text, color: color)
    }

    private var deleteChip: some View {
        let (text, color): (String, Color) = {
            switch visit.deleteRequestStatus {
            case .pending: return ("DELETE PENDING", Theme.warning)
            case .approved: return ("DELETE APPROVED", Theme.success)
            case .denied: return ("DELETE DENIED", Theme.danger)
            case .none: return ("", .clear)
            }
        }()
        return StatusBadge(text: text, color: color)
    }
}
