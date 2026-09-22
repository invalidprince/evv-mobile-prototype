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
    /// Human service name from the server (server v0.4.447). nil on older
    /// servers/mock data — then the enum label stands in, exactly as before.
    var serviceName: String?
    /// The ONE display discipline: server name → enum label fallback.
    var serviceLabel: String { serviceName ?? service.rawValue }
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
    /// Build 87 — the server INDIVIDUAL id (e.g. "C673069"), so the 2:1
    /// second-staff picker can ask the server who is eligible for THIS person.
    var serverIndividualId: String?
    /// All server visit IDs for this shift (used for 1:2 clock-out — clock out all).
    var serverVisitIds: [String] = []
    /// Ratio string from server, e.g. "2:1".
    var ratio: String?
    /// Partner info for 2:1 shifts from server.
    var partners: [PartnerInfo] = []
    /// build 86 / server v0.4.614 — the SERVICE is staffed 2:1 but only ONE
    /// staff member (you) is on the shift so far. Server-derived; the
    /// dashboard shows the same "needs 2nd staff" chip off the same rule.
    /// Older servers omit the key → nil → fallback below.
    var needsSecondStaff: Bool?
    /// THE one rule for the badge: the server's answer when present, else
    /// (older server) a 2:1 shift whose partner list is empty.
    var showsSecondStaffRequired: Bool {
        if let n = needsSecondStaff { return n }
        return ratio == "2:1" && partners.isEmpty && teamStaff == nil
    }
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

    /// Build 83 — server v0.4.604 `stillOpen`: the visit is clocked in with
    /// no clock-out, and was returned by History REGARDLESS of the 14-day
    /// window. Derived locally when the server did not send the key.
    var stillOpen: Bool = false

    /// Build 83 — a running visit whose clock-in is on a PRIOR day. Nick's
    /// V-2048 (Sep 3, never clocked out) blocked every clock-in for 18 days
    /// while nothing on the phone showed it. Today shows a persistent banner
    /// for these and History marks the row STILL CLOCKED IN.
    var isStaleOpen: Bool {
        guard status == .inProgress, actualEnd == nil, let start = actualStart else { return false }
        return start < Calendar.current.startOfDay(for: Date())
    }

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

    // MARK: - Duration (build 64)

    /// Server-computed duration in minutes (`GET /api/me/visits` → `duration`,
    /// server v0.4.450+ routes it through span-core so 12:00 AM → 12:00 AM is
    /// 1440 and 8:00 PM → 6:00 AM is 600). nil on mock/offline/queued rows and
    /// on a visit with a missing punch.
    var serverDurationMinutes: Int?

    /// THE one duration rule. Server value first (one source of truth); the
    /// local recompute is only the FALLBACK, and it goes through
    /// `ManualSpan.spanMinutes` — minutes-since-midnight math — because
    /// `actualStart`/`actualEnd` are parsed onto the SAME calendar date by
    /// `parseShiftDateTime`, so `end.timeIntervalSince(start)` was 0 for a
    /// 12-12 Lifesharing day and NEGATIVE for an overnight span (History read
    /// "0h 0m" and Total Hours (14d) shrank). nil ⇔ a punch is missing.
    var durationMinutes: Int? {
        if let m = serverDurationMinutes, m >= 0 { return m }
        guard let start = actualStart, let end = actualEnd else { return nil }
        return ManualSpan.spanMinutes(start: start, end: end)
    }

    var durationText: String {
        guard let mins = durationMinutes else { return "—" }
        return "\(mins / 60)h \(mins % 60)m"
    }

    var hoursValue: Double {
        guard let mins = durationMinutes else { return 0 }
        return Double(mins) / 60.0
    }
}

struct OpenShift: Identifiable {
    let id: UUID
    let client: Client
    let service: ServiceType
    /// Human service name (mock mode has none; real server open shifts render
    /// through ServerOpenShiftsSection, which reads the payload's serviceName).
    var serviceName: String? = nil
    /// The ONE display discipline, same as Visit.serviceLabel (v0.4.484).
    var serviceLabel: String { serviceName ?? service.rawValue }
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
///   • Untouched placeholder (both still midnight) → build 65: NO PROMPT AT
///     ALL. It was a hard block, then a confirm, and is now nothing — Nick
///     2026-09-10: "Nah just don't require it" / "all shifts, also across the
///     website AND iOS". The live span hint is the disclosure.
///   • End later than now (+10 min grace), today, not crossing midnight →
///     CONFIRM, never a block ("declaring the full scheduled window"). This is
///     the ONLY surviving manual-time prompt on either platform.
///
/// Build 62 (Nick 2026-09-09, #evv: "There's no way to put a date on this like
/// you can on desktop. Just fix this.") — the entry also carries a DATE, the
/// mirror of the desktop's `<input type="date" id="uv-date">`:
///   • Default TODAY; a future date is never allowed (`max = TODAY_ISO`).
///   • The earliest allowed date is the ACTING ROLE's window, which the server
///     sends as `manualBackdateMaxDays` on GET /api/me/shifts (v0.4.436) — the
///     same helper the POST enforces (`visit-core.backdateMaxDaysFor`). The
///     picker is a courtesy; `resolveManualDate` re-checks both bounds, so a
///     forged payload cannot slip a future or ancient date through.
///   • **0 days is a real answer meaning "today only"**, never "unknown".
///   • On a BACK-DATED entry the future-end confirmation is skipped — the
///     desktop's `confirmFutureEnd` returns true immediately when the date is
///     not today, because a past day has already elapsed and nagging about a
///     "future" end time on it would be nonsense (`visit-core.manualEntryNote`
///     makes the same distinction server-side).
enum ManualSpan {
    /// The server's default manual back-date window when it says nothing
    /// (older servers omit `manualBackdateMaxDays`). Matches
    /// `visit-core.MANUAL_BACKDATE_MAX_DAYS`. Only ever a FALLBACK — a value
    /// the server did send, including 0, always wins.
    static let defaultBackdateMaxDays = 30

    /// Earliest date a manual entry may be dated, given the role's window.
    /// `maxDays == 0` → today itself.
    static func earliestDate(maxDays: Int, today: Date = Date()) -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: today)
        let days = max(0, maxDays)
        return cal.date(byAdding: .day, value: -days, to: start) ?? start
    }

    /// The picker's selectable range: earliest…today. Never includes tomorrow.
    static func dateRange(maxDays: Int, today: Date = Date()) -> ClosedRange<Date> {
        let end = Calendar.current.startOfDay(for: today)
        return earliestDate(maxDays: maxDays, today: today)...end
    }

    /// True when `date` is the same calendar day as `today`.
    static func isToday(_ date: Date, today: Date = Date()) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: today)
    }

    /// "YYYY-MM-DD" for the server's optional `date` field. Formatted in the
    /// DEVICE's calendar/timezone from the day the staff member picked —
    /// never an ISO8601 instant, which could roll a day at a UTC boundary.
    static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Build 62 — a `.hourAndMinute` picker's Date still carries whatever day
    /// it was created on (today), so a back-dated entry's LOCAL row would land
    /// under today in History. This grafts the picked time onto the picked day.
    /// The server is unaffected either way — it takes "H:MM AM/PM" labels plus
    /// the separate `date` field, never an instant.
    static func combine(day: Date, time: Date) -> Date {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0,
                        of: cal.startOfDay(for: day)) ?? day
    }

    /// "Mon, Sep 8" — the sheet's inline confirmation of what day is being
    /// recorded, and the day-name in the cross-midnight hint.
    static func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    /// Footer copy naming the role's actual window (the desktop's per-role
    /// hint, v0.4.364: "Your role can back-date up to N days").
    static func backdateHint(maxDays: Int, today: Date = Date()) -> String {
        if maxDays <= 0 { return "Your role can only enter time for today." }
        let earliest = dayLabel(earliestDate(maxDays: maxDays, today: today))
        return "Your role can back-date up to \(maxDays) day\(maxDays == 1 ? "" : "s") (no earlier than \(earliest)). Future dates are never allowed."
    }
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

    /// Build 62 — the same hint, but a midnight-crossing span NAMES the day it
    /// ends on, because with a date picker present "spans midnight" alone no
    /// longer says which midnight. The visit's DATE stays the start date
    /// (server: `manualEntryNote` / `visit-core` keeps `date` = start day).
    static func hint(start: Date, end: Date, on date: Date) -> String {
        let base = hint(start: start, end: end)
        guard crossesMidnight(start: start, end: end) else { return base }
        let next = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date)) ?? date
        return "\(base) (ends \(dayLabel(next)))"
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
    /// nothing needs confirming. Mirrors the desktop's remaining `confirm()`.
    static func confirmationMessage(start: Date, end: Date, now: Date = Date()) -> String? {
        confirmationMessage(start: start, end: end, date: now, now: now)
    }

    /// Build 65 (Nick 2026-09-10, Todoist 6hQX2PvpHr59Pf9H: "It appears to always
    /// verify, I don't think it's necessarily required. That's why you enter in
    /// the times." / "Nah just don't require it." / "All shifts, also across the
    /// website AND iOS.") — the FULL-DAY / cross-midnight confirm is GONE on both
    /// platforms. A 12:00 AM → 12:00 AM entry is the NORMAL shape of a
    /// Lifesharing day, so prompting on it prompted on the common case and
    /// taught people to tap through. The passive `hint(start:end:on:)` string
    /// ("24h 0m — spans midnight (ends Fri, Sep 11)") stays visible under the
    /// pickers and is now the only disclosure — the desktop made exactly the
    /// same trade in `my-day.ejs`.
    ///
    /// `placeholderUntouched` is intentionally retained (the sheets show the
    /// hint from it and the offline harness asserts the shape) but no longer
    /// produces a confirmation. Do not wire it back to an alert.
    ///
    /// What SURVIVES: the future-end confirm. That is a different question —
    /// "this end time has not happened yet" (v0.4.128, asked for by name) — and
    /// it is still SKIPPED on a back-dated entry, matching the desktop's
    /// `confirmFutureEnd` (`if (dateIso && dateIso !== TODAY_ISO) return true`).
    static func confirmationMessage(start: Date, end: Date, date: Date, now: Date = Date()) -> String? {
        // A past day has already elapsed — there is no "future" end time on it.
        if !isToday(date, today: now) { return nil }
        if endIsInFuture(start: start, end: end, now: now) {
            let f = DateFormatter(); f.dateFormat = "h:mm a"
            return "The end time you entered (\(f.string(from: end))) has not occurred yet — it is currently \(f.string(from: now)).\n\nSave it anyway? Only do this if you are declaring the full service window you are scheduled to work."
        }
        return nil
    }
}
