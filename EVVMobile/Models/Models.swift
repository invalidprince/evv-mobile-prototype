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
    var teamStaff: Staff?          // 2:1 team visit partner
    var isGroup: Bool = false      // 1:2 group visit
    var notes: String = ""
    var timeFixStatus: TimeFixStatus = .none
    var deleteRequestStatus: DeleteRequestStatus = .none
    var manualLocation: ManualLocation?
    var manualLocationFlagged: Bool = false

    var client: Client { clients[0] }

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
