import Foundation

struct Client: Identifiable, Hashable {
    let id: UUID
    let name: String
    let address: String
    let city: String
    var allergies: [String] = []
    var safetyAlerts: [String] = []
    var protocols: [String] = []

    var fullAddress: String { "\(address), \(city)" }
}

struct Staff: Identifiable, Hashable {
    let id: UUID
    let name: String
    let role: String
}

/// Lightweight partner info from server (for 2:1 display).
struct PartnerInfo: Hashable {
    let staffId: String
    let name: String
}

/// App-wide running mode.
enum AppMode: String {
    case mock   // Existing demo data
    case server // Connected to live backend
}

enum ServiceType: String, CaseIterable, Identifiable {
    case inHomeSupport = "In-Home Support"
    case communityParticipation = "Community Participation"
    case companion = "Companion"
    case respite = "Respite"

    var id: String { rawValue }
}

enum VisitStatus: String {
    case scheduled = "Scheduled"
    case inProgress = "In Progress"
    case completed = "Completed"
    case missed = "Missed"
}

enum SyncState: String {
    case synced = "Synced"
    case pending = "Pending"
    case failed = "Failed"
}

enum TimeFixStatus: String {
    case none
    case pending = "Pending"
    case approved = "Approved"
    case denied = "Denied"
}

enum DeleteRequestStatus: String {
    case none
    case pending = "Pending"
    case approved = "Approved"
    case denied = "Denied"
}

struct ManualLocation: Hashable {
    var street: String = ""
    var city: String
    var state: String
    var zip: String

    var display: String {
        street.isEmpty ? "\(city), \(state) \(zip)" : "\(street), \(city), \(state) \(zip)"
    }
}

struct Visit: Identifiable {
    let id: UUID
    var clients: [Client]
    var service: ServiceType
    var scheduledStart: Date
    var scheduledEnd: Date
    var actualStart: Date?
    var actualEnd: Date?
    var status: VisitStatus
    var syncState: SyncState = .synced
    var docComplete: Bool = false
    var teamStaff: Staff?          // 2:1 team visit partner (mock mode)
    var isGroup: Bool = false      // 1:2 group visit
    var notes: String = ""
    var timeFixStatus: TimeFixStatus = .none
    var deleteRequestStatus: DeleteRequestStatus = .none
    var manualLocation: ManualLocation?
    var manualLocationFlagged: Bool = false

    /// Whether the visit has a note attached (server mode).
    var hasNote: Bool = false
    /// Documentation status string from server (e.g. "complete", "pending").
    var serverDocStatus: String?

    // MARK: - Server-mode fields
    /// Server shift ID (used for clock-in API call).
    var serverShiftId: Int?
    /// Server visit ID (used for clock-out API call).
    var serverVisitId: String?
    /// Ratio string from server, e.g. "2:1".
    var ratio: String?
    /// Partner info for 2:1 shifts from server.
    var partners: [PartnerInfo] = []
    /// Location string from server.
    var serverLocation: String?
    /// Set when documentation was (or is) late — i.e. the note was still
    /// incomplete after the service day ended, or was completed after it.
    /// Visible to managers. Once set by a late completion it never clears:
    /// late is a fact, not a temporary state.
    var lateDocumentation: Bool = false

    var client: Client { clients[0] }

    // MARK: - Same-day note rule

    /// The agency-local service day (start of day) the visit occurred on.
    var serviceDay: Date {
        Calendar.current.startOfDay(for: actualStart ?? scheduledStart)
    }

    /// Notes are due the same day as the visit; the deadline is midnight
    /// (start of the following day, agency-local).
    var noteDeadline: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: serviceDay) ?? serviceDay
    }

    /// True while the note is still incomplete and the service day has passed.
    var noteIsLate: Bool {
        status == .completed && !docComplete && Date() >= noteDeadline
    }

    /// True when the note was finished, but only after its service day ended.
    var noteCompletedLate: Bool {
        docComplete && lateDocumentation
    }

    var durationText: String {
        guard let start = actualStart, let end = actualEnd else { return "—" }
        let mins = Int(end.timeIntervalSince(start) / 60)
        return "\(mins / 60)h \(mins % 60)m"
    }

    var hoursValue: Double {
        guard let start = actualStart, let end = actualEnd else { return 0 }
        return end.timeIntervalSince(start) / 3600
    }
}

struct OpenShift: Identifiable {
    let id: UUID
    let client: Client
    let service: ServiceType
    let start: Date
    let end: Date
}

enum PromptLevel: String, CaseIterable, Identifiable {
    case independent = "Independent"
    case verbal = "Verbal"
    case gestural = "Gestural"
    case partialPhysical = "Partial Physical"
    case fullPhysical = "Full Physical"

    var id: String { rawValue }
}

struct Outcome: Identifiable {
    let id: UUID
    let clientId: UUID
    let title: String
    let goal: String
}

// MARK: - Visit note (per-goal data + narrative)

struct OutcomeEntry {
    var promptLevel: PromptLevel?
    var frequency: Int = 0
    var goalOpportunity = false
    var behaviorObserved = false
    var narrative: String = ""

    var isComplete: Bool {
        promptLevel != nil && !narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct VisitNote {
    var outcomeEntries: [UUID: OutcomeEntry] = [:]   // keyed by Outcome.id
    var additionalComments: String = ""

    func isComplete(for outcomes: [Outcome]) -> Bool {
        outcomes.allSatisfy { outcomeEntries[$0.id]?.isComplete == true }
    }
}

struct Credential: Identifiable {
    let id = UUID()
    let name: String
    let status: CredentialStatus
    let detail: String
}

enum CredentialStatus {
    case valid, expiringSoon, expired
}
