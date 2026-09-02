import Foundation

struct Client: Identifiable, Hashable {
    let id: UUID
    let name: String
    let address: String
    let city: String
    var allergies: [String] = []
    var safetyAlerts: [String] = []
    var protocols: [String] = []
    var communicationUnderstood: String = ""
    var adaptiveEquipment: String = ""
    var supervisionLevel: String = ""

    var fullAddress: String {
        let parts = [address, city]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: ", ")
    }
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
    /// All server visit IDs for this shift (used for 1:2 clock-out — clock out all).
    var serverVisitIds: [String] = []
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
    /// Free-text name for an unlisted individual (F2)
    var unlistedIndividualName: String?
    /// Whether the shift's service requires live EVV punches. Non-EVV
    /// services (e.g. Lifesharing per diem) use manual time entry — staff
    /// enter start/end times instead of clocking in/out; no GPS.
    var evvRequired: Bool = true
    /// Whether the service requires live clock in/out (decoupled from EVV).
    /// When false, staff can manually enter start/end times.
    var requiresClockIn: Bool = true
    /// v0.4.348 — "pending" on a staff-requested shift awaiting manager
    /// approval; nil on every normal visit. Denied requests never appear.
    var approvalStatus: String?

    /// A staff-requested shift the manager hasn't decided yet. Unmistakable
    /// badge everywhere it appears — a pending visit that reads as a real one
    /// is how bad billing happens.
    var isPendingApproval: Bool { approvalStatus == "pending" }

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

enum DataPoint: String, CaseIterable, Identifiable {
    case prompts = "Prompts"
    case successes = "Successes"
    case opportunities = "Opportunities"
    case notApplicable = "N/A"

    var id: String { rawValue }
}

/// Legacy prompt-level values (for backward compat with existing saved records).
/// These are only used when loading old data — new entries always use DataPoint.
enum LegacyPromptLevel: String {
    case independent = "Independent"
    case verbal = "Verbal"
    case gestural = "Gestural"
    case partialPhysical = "Partial Physical"
    case fullPhysical = "Full Physical"
}

struct Outcome: Identifiable {
    let id: UUID
    let clientId: UUID
    let title: String
    let goal: String
}

// MARK: - Visit note (per-goal data + narrative)

/// v0.4.152 — an outcome carries three counts plus an N/A flag. The old
/// `dataPoint` category + single `frequency` + goalOpportunity/behaviorObserved
/// booleans are GONE; `applyLegacy` maps old server/AI payloads onto this shape.
///
/// nil count = "not measured". 0 = "measured zero". They are different.
struct OutcomeEntry {
    var prompts: Int?
    var successes: Int?
    var opportunities: Int?
    var na = false
    var narrative: String = ""

    var hasCount: Bool { prompts != nil || successes != nil || opportunities != nil }

    var hasNarrative: Bool {
        !narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Three explicit 0s with no narrative means "not worked on" and counts as
    /// N/A — mirrors visit-core.normalizeOutcomeEntry (Nick 2026-08-15). With a
    /// narrative present the zeros are real measurements and stay as typed.
    var effectivelyNa: Bool {
        if na { return true }
        return !hasNarrative && prompts == 0 && successes == 0 && opportunities == 0
    }

    /// When N/A is checked, the outcome is complete without numbers or a
    /// narrative (the staff didn't work on this goal today). Otherwise it needs
    /// a count AND a narrative — per Nick 2026-08-17, data alone is no longer
    /// enough. Same rule the server enforces in visit-core.outcomeEntryMissing.
    var isComplete: Bool {
        if effectivelyNa { return true }
        return hasCount && hasNarrative
    }

    /// Which half is missing, for inline UI copy. nil when complete.
    var missingPart: MissingPart? {
        if effectivelyNa { return nil }
        if !hasCount && !hasNarrative { return .both }
        if !hasCount { return .data }
        if !hasNarrative { return .narrative }
        return nil
    }

    enum MissingPart {
        case data, narrative, both

        var label: String {
            switch self {
            case .data: return "a data point"
            case .narrative: return "a narrative"
            case .both: return "a data point and a narrative"
            }
        }
    }

    /// N/A wins: clearing counts keeps the stored state unambiguous, matching
    /// the server normalizer.
    mutating func setNa(_ on: Bool) {
        na = on
        if on { prompts = nil; successes = nil; opportunities = nil }
    }

    /// Map a legacy `promptLevel` (+ frequency) payload onto the new fields.
    /// Used when decoding an existing note or an AI draft written before
    /// v0.4.152. Never overwrites values already set from the new shape.
    mutating func applyLegacy(promptLevel: String?, frequency: Int?) {
        guard !na, !hasCount, let pl = promptLevel?.trimmingCharacters(in: .whitespaces), !pl.isEmpty else { return }
        let freq = frequency ?? 0
        switch pl {
        case DataPoint.notApplicable.rawValue:
            setNa(true)
        case DataPoint.prompts.rawValue:
            prompts = freq
        case DataPoint.successes.rawValue:
            successes = freq
        case DataPoint.opportunities.rawValue:
            opportunities = freq
        default:
            // Pre-2026 prompt scale (Independent/Verbal/…) — fold onto the
            // closest count so the note still reads sensibly.
            if let legacy = LegacyPromptLevel(rawValue: pl) {
                switch legacy {
                case .independent: successes = freq
                case .verbal, .gestural, .partialPhysical, .fullPhysical: prompts = freq
                }
            }
        }
    }
}

struct VisitNote {
    var outcomeEntries: [UUID: OutcomeEntry] = [:]   // keyed by Outcome.id
    var additionalComments: String = ""
    /// Answers to server-configured visit questions, keyed by question ID.
    /// Stored in wire format: radio/text answers are plain strings; checkbox
    /// answers are JSON-encoded array strings (e.g. "[\"A\",\"B\"]") — the
    /// same encoding the API uses for defaultValue and submission.
    /// Lives on the note so drafts/offline persistence carry it automatically.
    var questionAnswers: [Int: String] = [:]
    /// Legacy transport review bool. The transport question is now a dynamic
    /// server question; this is kept for AI-draft responses and old saved
    /// notes, and is still sent alongside questionAnswers for compat.
    var transportReviewedGoals: Bool?

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

// MARK: - Manual-time span rules (build 55)
// (Lives in Models.swift because the pbxproj lists files explicitly — a new
// file is not compiled by Xcode Cloud unless the project is regenerated.)

/// Manual-time (non-EVV service) span rules — the iOS mirror of the desktop
/// `views/my-day.ejs` conventions (`MANUAL_TIME_PLACEHOLDER`,
/// `spanCrossesMidnight`, `spanMinutes`, `uvPlaceholderUntouched`,
/// `confirmFutureEnd`) and of `visit-core.manualSpanMinutes` on the server.
///
/// Build 55 (Nick 2026-09-02, #evv): "Desktop defaults them to 12:00 AM –
/// 12:00 AM ('12-12'), but the app pre-filled 1:41 PM – 2:41 PM. Make the
/// mobile manual-time defaults match the desktop behavior."
///
/// THE RULES (all from the desktop, none invented here):
///   • Both boxes open at MIDNIGHT (12:00 AM). The app does not guess a
///     service window — staff type the real times.
///   • An end AT OR BEFORE the start CROSSES MIDNIGHT. 12:00 AM → 12:00 AM is
///     a full 24-hour Lifesharing day, never a validation error (Nick
///     2026-08-18: "you work midnight to midnight").
///   • Untouched placeholder (both still midnight) → CONFIRM, never a block.
///   • End later than now (+10 min grace), today, not crossing midnight →
///     CONFIRM, never a block ("declaring the full scheduled window").
enum ManualSpan {
    /// Midnight today in the device's calendar — the 12:00 AM placeholder.
    static func midnightToday(_ now: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: now)
    }

    /// Minutes since midnight for the picker's hour/minute (the date part of a
    /// `.hourAndMinute` DatePicker is irrelevant — the server takes labels).
    static func minutes(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// end <= start → the span runs past midnight into the next day.
    static func crossesMidnight(start: Date, end: Date) -> Bool {
        minutes(end) <= minutes(start)
    }

    /// Span length in minutes; 12:00 AM → 12:00 AM = 1440.
    static func spanMinutes(start: Date, end: Date) -> Int {
        let s = minutes(start), e = minutes(end)
        return e <= s ? (1440 - s + e) : (e - s)
    }

    /// "8h 15m" / "24h 0m — spans midnight" (desktop's uv-span-hint).
    static func hint(start: Date, end: Date) -> String {
        let m = spanMinutes(start: start, end: end)
        let label = "\(m / 60)h \(m % 60)m"
        return crossesMidnight(start: start, end: end) ? "\(label) — spans midnight" : label
    }

    /// Both boxes still show the untouched midnight placeholder.
    static func placeholderUntouched(start: Date, end: Date) -> Bool {
        minutes(start) == 0 && minutes(end) == 0
    }

    /// Desktop `confirmFutureEnd`: an end more than 10 min past "now" on a
    /// same-day, non-wrapping span asks the staff member to confirm.
    static func endIsInFuture(start: Date, end: Date, now: Date = Date()) -> Bool {
        if crossesMidnight(start: start, end: end) { return false }
        return minutes(end) > minutes(now) + 10
    }

    /// The confirmation copy the sheets show before submitting, or nil when
    /// nothing needs confirming. Mirrors the desktop's two `confirm()`s.
    static func confirmationMessage(start: Date, end: Date, now: Date = Date()) -> String? {
        if placeholderUntouched(start: start, end: end) {
            return "Save a full 24-hour entry from 12:00 AM to 12:00 AM?\n\nBoth times still show 12:00 AM. Choose Cancel if you meant to enter different times."
        }
        if endIsInFuture(start: start, end: end, now: now) {
            let f = DateFormatter(); f.dateFormat = "h:mm a"
            return "The end time you entered (\(f.string(from: end))) has not occurred yet — it is currently \(f.string(from: now)).\n\nSave it anyway? Only do this if you are declaring the full service window you are scheduled to work."
        }
        return nil
    }
}
