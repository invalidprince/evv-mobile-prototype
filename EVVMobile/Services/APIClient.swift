import Foundation

// MARK: - API Response Types (Codable)

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct GoogleLoginRequest: Encodable {
    let idToken: String
}

struct LoginResponse: Decodable {
    let token: String
    let staff: ServerStaff
}

struct TokenRefreshResponse: Decodable {
    let token: String
}

struct ServerStaff: Decodable {
    let id: String
    let name: String
    let email: String
    let department: String
    let departmentName: String
}

struct ServerIndividual: Decodable {
    let id: String
    let name: String
    /// Client's home/service address (from the dashboard client record).
    let address: String?
    /// Geofence radius in feet (from the dashboard client record).
    let geofence: Int?
}

struct ServerPartner: Decodable {
    let staffId: String
    let name: String
}

struct ServerVisitInfo: Decodable {
    let id: String
    let clockIn: String
    let clockOut: String?
    let status: String?
    let minutes: Int?
    let docStatus: String?
    let hasNote: Bool?
}

struct ServerShiftVisitInfo: Decodable {
    let id: String
    let clientId: String?
    let clockIn: String?
    let clockOut: String?
    let status: String?
    let docStatus: String?
    let hasNote: Bool?
}

struct ServerShift: Decodable {
    let id: Int
    let date: String
    let start: String
    let end: String
    let service: String?
    let ratio: String?
    let individual: ServerIndividual
    let location: String?
    let partners: [ServerPartner]?
    let myVisit: ServerVisitInfo?
    /// All visits for this shift (populated for 1:2 shifts)
    let myVisits: [ServerShiftVisitInfo]?
    /// Whether the shift's service requires live EVV punches (default true).
    /// Non-EVV services (e.g. Lifesharing per diem) use manual time entry.
    let evvRequired: Bool?
    /// Whether the service requires live clock in/out punches (default true).
    /// When false, staff can manually enter start/end times instead of punching.
    /// Decoupled from evvRequired — a service can be non-EVV but still require clock-in.
    let requiresClockIn: Bool?
    /// Whether GPS capture is required on punches for this service.
    let gpsRequired: Bool?
}

struct ShiftsResponse: Decodable {
    let shifts: [ServerShift]
    let openShifts: [ServerShift]?
    /// Open RECURRING rules available for permanent weekday pickup
    /// (server v0.4.276). Older servers omit the key.
    let openRules: [ServerOpenRule]?
}

/// An active, unassigned recurring schedule a staff member can permanently
/// claim one weekday of ("I'll take Mondays") — GET /api/me/shifts `openRules`.
struct ServerOpenRule: Decodable, Identifiable {
    let id: Int
    /// Weekdays the rule covers, 0 = Sunday … 6 = Saturday (sorted).
    let weekdays: [Int]
    let start: String
    let end: String
    let service: String?
    /// 1 = weekly, 2 = every other week, N = every N weeks.
    let intervalWeeks: Int?
    let individual: ServerIndividual
    let individual2: ServerIndividual?
}

/// Success payload of POST /api/recurring/:id/claim-weekday.
struct ClaimRuleResponse: Decodable {
    let ok: Bool?
    let ruleId: Int?
    let weekday: Int?
    let weekdayLabel: String?
    let assigned: Int?
    let kept: Int?
    let conflicts: Int?
    let remainingDays: [Int]?
}

struct ClockInRequest: Encodable {
    let lat: Double?
    let lng: Double?
    let accuracy: Double?
    /// Manually entered service address (GPS-unavailable fallback punch).
    let address: String?
}

struct ClockOutRequest: Encodable {
    let lat: Double?
    let lng: Double?
    let accuracy: Double?
    let signature: String?
    let signatureSkipReason: String?
    /// Manually entered service address (GPS-unavailable fallback punch).
    let address: String?
}

struct ClockInResponse: Decodable {
    let visit: ServerVisitInfo
}

struct ManualTimeRequest: Encodable {
    let start: String
    let end: String
}

struct ManualTimeResponse: Decodable {
    let visit: ServerVisitInfo
    /// All created visits (one per individual for 1:2 shifts)
    let visits: [UnscheduledVisitCreated]?
}

struct ClockOutResponse: Decodable {
    let visit: ServerVisitInfo
}

struct ServerVisitRecord: Decodable {
    let id: String
    let shiftId: Int?
    let individual: ServerIndividual?
    let service: String?
    let clockIn: String?
    let clockOut: String?
    let status: String?
}

struct VisitsResponse: Decodable {
    let visits: [ServerVisitRecord]
}

// MARK: - History Visit (GET /me/visits)

struct ServerHistoryVisit: Decodable, Identifiable {
    let id: String
    let shiftId: Int?
    let individual: ServerIndividual?
    let service: String?
    let clockIn: String?
    let clockOut: String?
    let status: String?
    let date: String?
    let duration: Int?
    let docStatus: String?
    let hasNote: Bool?
}

struct HistoryVisitsResponse: Decodable {
    let visits: [ServerHistoryVisit]
}

// MARK: - Requests (GET /me/requests)

struct ServerException: Decodable, Identifiable {
    let id: String
    let visitId: String?
    let type: String?        // "Time-change request" or "Delete request"
    let status: String?      // "new", "in progress", "resolved"
    let resolution: String?  // "approved", "denied", etc.
    let detail: String?
    let date: String?
}

struct RequestsResponse: Decodable {
    let requests: [ServerException]?
    let exceptions: [ServerException]?

    var items: [ServerException] {
        requests ?? exceptions ?? []
    }
}

// MARK: - Note response

struct NoteResponse: Decodable {
    let ok: Bool?
    let docStatus: String?
}

// MARK: - Structured Documentation

/// Wrapper that swallows per-element decode failures so one malformed item
/// never kills an entire array (`[FailableDecodable<T>]` + compactMap).
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// Decode a JSON value that the server may emit as either a single string or
/// an array of strings (legacy records store e.g. `diagnosis` as one string).
private func decodeStringOrArray<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [String]? {
    if let arr = try? c.decodeIfPresent([String].self, forKey: key) { return arr }
    if let arr = try? c.decodeIfPresent([FailableDecodable<String>].self, forKey: key) {
        return arr.compactMap { $0.value }
    }
    if let str = try? c.decodeIfPresent(String.self, forKey: key) {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [trimmed]
    }
    return nil
}

struct ServerOutcome: Decodable, Identifiable {
    let id: Int
    let title: String
    let goal: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id, title, goal, status
        case text          // some endpoints emit the outcome text as "text"
        case description   // dashboard stores the goal detail as "description"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id: tolerate a numeric string
        if let i = try? c.decode(Int.self, forKey: .id) {
            id = i
        } else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) {
            id = i
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Outcome id missing or not an integer")
        }
        // title: fall back to "text" if "title" is absent/null
        let titleVal = ((try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil)
            ?? ((try? c.decodeIfPresent(String.self, forKey: .text)) ?? nil)
        title = titleVal?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        goal = ((try? c.decodeIfPresent(String.self, forKey: .goal)) ?? nil)
            ?? ((try? c.decodeIfPresent(String.self, forKey: .description)) ?? nil)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? nil
    }
}

struct ServerHealthInfo: Decodable {
    let allergies: [String]?
    let safetyAlerts: [String]?
    let protocols: [String]?
    let diagnosis: [String]?
    let healthNotes: String?
    let communicationUnderstood: String?
    let adaptiveEquipment: String?
    let supervisionLevel: String?

    enum CodingKeys: String, CodingKey {
        case allergies, safetyAlerts, protocols, diagnosis
        case healthNotes, communicationUnderstood, adaptiveEquipment, supervisionLevel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // These fields vary between string and [String] depending on how the
        // client record was entered — accept both.
        allergies = decodeStringOrArray(c, .allergies)
        safetyAlerts = decodeStringOrArray(c, .safetyAlerts)
        protocols = decodeStringOrArray(c, .protocols)
        diagnosis = decodeStringOrArray(c, .diagnosis)
        healthNotes = (try? c.decodeIfPresent(String.self, forKey: .healthNotes)) ?? nil
        communicationUnderstood = (try? c.decodeIfPresent(String.self, forKey: .communicationUnderstood)) ?? nil
        adaptiveEquipment = (try? c.decodeIfPresent(String.self, forKey: .adaptiveEquipment)) ?? nil
        supervisionLevel = (try? c.decodeIfPresent(String.self, forKey: .supervisionLevel)) ?? nil
    }
}

struct ServerOutcomeEntry: Decodable {
    let outcomeId: Int?
    let title: String?
    // v0.4.152 shape — three counts + N/A.
    let prompts: Int?
    let successes: Int?
    let opportunities: Int?
    let na: Bool?
    // Legacy shape — notes submitted before v0.4.152 still carry these.
    let promptLevel: String?
    let frequency: Int?
    let narrative: String?
}

struct ServerExistingNote: Decodable {
    let type: String?
    let outcomes: [ServerOutcomeEntry]?
    let additionalComments: String?
    let submittedAt: String?
    let submittedBy: String?
    // Legacy flat note fields
    let comments: String?
    let goals: [String]?
    /// Transport review question answer (legacy bool — new notes carry the
    /// same info inside questionAnswers)
    let transportReviewedGoals: Bool?
    /// Previously submitted answers to server-configured visit questions.
    let questionAnswers: [ServerQuestionAnswer]?

    enum CodingKeys: String, CodingKey {
        case type, outcomes, additionalComments, submittedAt, submittedBy
        case comments, goals, transportReviewedGoals, questionAnswers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? nil
        // Per-element lenient decode — one malformed entry doesn't kill the note
        if let raw = try? c.decodeIfPresent([FailableDecodable<ServerOutcomeEntry>].self, forKey: .outcomes) {
            outcomes = raw.compactMap { $0.value }
        } else {
            outcomes = nil
        }
        additionalComments = (try? c.decodeIfPresent(String.self, forKey: .additionalComments)) ?? nil
        submittedAt = (try? c.decodeIfPresent(String.self, forKey: .submittedAt)) ?? nil
        submittedBy = (try? c.decodeIfPresent(String.self, forKey: .submittedBy)) ?? nil
        comments = (try? c.decodeIfPresent(String.self, forKey: .comments)) ?? nil
        goals = decodeStringOrArray(c, .goals)
        transportReviewedGoals = (try? c.decodeIfPresent(Bool.self, forKey: .transportReviewedGoals)) ?? nil
        // Per-element lenient decode — one malformed answer doesn't kill prefill
        if let raw = try? c.decodeIfPresent([FailableDecodable<ServerQuestionAnswer>].self, forKey: .questionAnswers) {
            questionAnswers = raw.compactMap { $0.value }
        } else {
            questionAnswers = nil
        }
    }
}

/// A server-configured visit documentation question (service/department/
/// individual scoped, managed in the dashboard).
///
/// Wire contract (stable): all fields always present. `options` is empty for
/// text questions. `defaultValue` is a plain string for radio/text and a
/// JSON-ENCODED ARRAY STRING for checkbox (e.g. "[\"A\",\"B\"]") — or null.
/// Decoding is defensive anyway: int-or-string id, unknown type falls back to
/// "text", and a malformed element is dropped via FailableDecodable upstream.
struct ServerDocQuestion: Decodable, Identifiable {
    let id: Int
    let scope: String        // "service" | "department" | "individual"
    let text: String
    let type: String         // "radio" | "checkbox" | "text"
    let options: [String]
    let defaultValue: String?
    let required: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, scope, text, type, options, defaultValue, required, sortOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id: tolerate a numeric string
        if let i = try? c.decode(Int.self, forKey: .id) {
            id = i
        } else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) {
            id = i
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Question id missing or not an integer")
        }
        let textVal = (((try? c.decodeIfPresent(String.self, forKey: .text)) ?? nil) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textVal.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .text, in: c, debugDescription: "Question text missing or empty")
        }
        text = textVal
        scope = ((try? c.decodeIfPresent(String.self, forKey: .scope)) ?? nil) ?? "service"
        let t = ((try? c.decodeIfPresent(String.self, forKey: .type)) ?? nil) ?? "text"
        type = ["radio", "checkbox", "text"].contains(t) ? t : "text"
        options = decodeStringOrArray(c, .options) ?? []
        defaultValue = (try? c.decodeIfPresent(String.self, forKey: .defaultValue)) ?? nil
        required = ((try? c.decodeIfPresent(Bool.self, forKey: .required)) ?? nil) ?? true
        sortOrder = ((try? c.decodeIfPresent(Int.self, forKey: .sortOrder)) ?? nil)
            ?? Int((((try? c.decodeIfPresent(String.self, forKey: .sortOrder)) ?? nil) ?? "")) ?? 0
    }
}

/// A previously submitted question answer from existingNote.questionAnswers.
/// Used for prefill (a saved answer wins over the question's defaultValue).
struct ServerQuestionAnswer: Decodable {
    let questionId: Int
    let scope: String?
    let question: String?
    let type: String?
    let answer: String

    enum CodingKeys: String, CodingKey {
        case questionId, scope, question, type, answer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // questionId: tolerate a numeric string
        if let i = try? c.decode(Int.self, forKey: .questionId) {
            questionId = i
        } else if let s = try? c.decode(String.self, forKey: .questionId), let i = Int(s) {
            questionId = i
        } else {
            throw DecodingError.dataCorruptedError(forKey: .questionId, in: c, debugDescription: "questionId missing or not an integer")
        }
        scope = (try? c.decodeIfPresent(String.self, forKey: .scope)) ?? nil
        question = (try? c.decodeIfPresent(String.self, forKey: .question)) ?? nil
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? nil
        answer = ((try? c.decodeIfPresent(String.self, forKey: .answer)) ?? nil) ?? ""
    }
}

// MARK: - Service Location (CMS Place of Service) — build 28 / server v0.4.241+

/// One allowed service-location option for this visit (already scoped to the
/// individual's departments by the server — the picker can never offer a value
/// the submit validator would refuse).
struct ServerServiceLocationOption: Decodable, Identifiable {
    let code: String
    let label: String
    let posCode: String?
    var id: String { code }

    enum CodingKeys: String, CodingKey { case code, label, posCode }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = (try? c.decode(String.self, forKey: .code)) ?? ""
        label = ((try? c.decodeIfPresent(String.self, forKey: .label)) ?? nil) ?? code
        posCode = (try? c.decodeIfPresent(String.self, forKey: .posCode)) ?? nil
    }
}

/// The visit's resolved Service Location payload from the documentation
/// template. `locked` means the service code pins the location — render a
/// static label and send nothing the staff can change.
struct ServerServiceLocation: Decodable {
    let locked: Bool?
    let selected: String?
    let autoApplied: String?
    let lockedByService: String?
    let required: Bool?
    let options: [ServerServiceLocationOption]?

    enum CodingKeys: String, CodingKey {
        case locked, selected, autoApplied, lockedByService, required, options
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        locked = (try? c.decodeIfPresent(Bool.self, forKey: .locked)) ?? nil
        selected = (try? c.decodeIfPresent(String.self, forKey: .selected)) ?? nil
        autoApplied = (try? c.decodeIfPresent(String.self, forKey: .autoApplied)) ?? nil
        lockedByService = (try? c.decodeIfPresent(String.self, forKey: .lockedByService)) ?? nil
        required = (try? c.decodeIfPresent(Bool.self, forKey: .required)) ?? nil
        if let raw = try? c.decodeIfPresent([FailableDecodable<ServerServiceLocationOption>].self, forKey: .options) {
            options = raw.compactMap { $0.value }.filter { !$0.code.isEmpty }
        } else {
            options = nil
        }
    }
}

struct DocumentationTemplateResponse: Decodable {
    let visitId: String?
    let outcomes: [ServerOutcome]?
    let healthInfo: ServerHealthInfo?
    let existingNote: ServerExistingNote?
    let aiAssistEnabled: Bool?
    let signatureCaptured: Bool?
    /// Server-configured visit questions (pre-filtered + pre-sorted for this visit).
    let questions: [ServerDocQuestion]?
    /// Where the service was delivered (CMS Place of Service) — nil on older
    /// servers or when no location types are configured.
    let serviceLocation: ServerServiceLocation?

    enum CodingKeys: String, CodingKey {
        case visitId, outcomes, healthInfo, existingNote, aiAssistEnabled, signatureCaptured, questions, serviceLocation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        visitId = (try? c.decodeIfPresent(String.self, forKey: .visitId)) ?? nil
        // Per-element lenient decode — a single malformed outcome is dropped
        // instead of failing the whole template ("Data error" bug).
        if let raw = try? c.decodeIfPresent([FailableDecodable<ServerOutcome>].self, forKey: .outcomes) {
            outcomes = raw.compactMap { $0.value }
        } else {
            outcomes = nil
        }
        // Health info / existing note are best-effort: server data shapes vary
        // (legacy notes can be plain strings) and must never block the form.
        healthInfo = (try? c.decodeIfPresent(ServerHealthInfo.self, forKey: .healthInfo)) ?? nil
        existingNote = (try? c.decodeIfPresent(ServerExistingNote.self, forKey: .existingNote)) ?? nil
        aiAssistEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .aiAssistEnabled)) ?? nil
        signatureCaptured = (try? c.decodeIfPresent(Bool.self, forKey: .signatureCaptured)) ?? nil
        // Per-element lenient decode — one malformed question never kills the form.
        if let raw = try? c.decodeIfPresent([FailableDecodable<ServerDocQuestion>].self, forKey: .questions) {
            questions = raw.compactMap { $0.value }
        } else {
            questions = nil
        }
        // Best-effort: a malformed serviceLocation must never block the form.
        serviceLocation = (try? c.decodeIfPresent(ServerServiceLocation.self, forKey: .serviceLocation)) ?? nil
    }
}

struct DocumentationSubmitResponse: Decodable {
    let ok: Bool?
    let docStatus: String?
}

// MARK: - Non-billable

struct NonBillableEntry: Decodable, Identifiable {
    let id: Int?
    let date: String?
    let category: String?
    let minutes: Int?
    let note: String?
    let createdAt: String?
}

struct NonBillableListResponse: Decodable {
    let entries: [NonBillableEntry]?
}

struct NonBillableCreateResponse: Decodable {
    let id: Int?
    let ok: Bool?
}

// MARK: - Time fix / delete request responses

struct ExceptionResponse: Decodable {
    let ok: Bool?
    let exceptionId: String?
}

// MARK: - Individuals (for unscheduled visit selection)

struct ServerIndividualOption: Codable, Identifiable {
    let id: String
    let name: String
    let services: [String]?
    let serviceCodes: [String]?
    /// Services (descriptions + codes) that do NOT require live EVV punches
    /// — these use manual time entry instead of clock in/out.
    let nonEvvServices: [String]?
}

struct IndividualsResponse: Decodable {
    let individuals: [ServerIndividualOption]
}

// MARK: - Unscheduled visit creation

struct UnscheduledVisitRequest: Encodable {
    let clientIds: [String]?
    let service: String?
    let lat: Double?
    let lng: Double?
    let accuracy: Double?
    /// Manually entered service address (GPS-unavailable fallback punch).
    let address: String?
    let unlistedName: String?
    /// Manual time entry (non-EVV services): "H:MM AM/PM" strings
    let startTime: String?
    let endTime: String?
}

struct UnscheduledVisitCreated: Decodable {
    let id: String
    let clientId: String?
    let clockIn: String
}

struct UnscheduledVisitResponse: Decodable {
    let shift: ServerShift?
    let visit: ServerVisitInfo
    /// All created visits (one per individual for 1:2 unscheduled)
    let visits: [UnscheduledVisitCreated]?
}

struct APIErrorResponse: Decodable {
    let error: String
}

// MARK: - Staff Documents (v0.4.194 — compliance vault, no offline support)

struct StaffDocumentSlot: Decodable, Identifiable {
    let typeId: Int
    let name: String
    let category: String
    let statusKey: String
    let statusLabel: String
    let chip: String
    let expiresOn: String?
    let rejectReason: String?
    let fileName: String?
    var id: Int { typeId }
}

struct StaffDocumentsResponse: Decodable {
    let documents: [StaffDocumentSlot]
}

struct StaffDocumentUploadResponse: Decodable {
    let ok: Bool
    let message: String?
}

// MARK: - Work tab (v0.4.273 — To-Dos + derived items, ONLINE-ONLY)

/// One row on the Work tab. `kind == "todo"` is a real, checkable to-do from
/// the `todos` table; `kind == "auto"` is a derived line that clears itself
/// when the underlying work is done (never checkable). Most auto items carry
/// a `webPath` into the web app; `native == "documents"` routes to the native
/// My Documents screen instead.
struct WorkItem: Decodable, Identifiable {
    let key: String
    let kind: String
    let category: String?
    let title: String
    let detail: String?
    let dueDate: String?
    let overdue: Bool
    var done: Bool
    let checkable: Bool
    let todoId: Int?
    let webPath: String?
    let native: String?
    var id: String { key }
    var isTodo: Bool { kind == "todo" }
}

struct WorkTeamRollup: Decodable {
    let total: Int
    let overdue: Int
    let webPath: String?
}

struct WorkTodosResponse: Decodable {
    let items: [WorkItem]
    let teamRollup: WorkTeamRollup?
    let openCount: Int
}

struct ToggleTodoResponse: Decodable {
    let ok: Bool
    let done: Bool
}

// MARK: - eMAR (v0.4.274 — Today-tab medications, ONLINE-ONLY)

/// One due (scheduled) administration slot for today. `recordable` is decided
/// SERVER-side (pending/missed with nothing recorded yet). `dueTimeLabel` is a
/// wall-clock label rendered by the server — display it as given, never run
/// `dueTime` through a device-timezone conversion.
///
/// 🔑 build 33 / server v0.4.295 — the GIVE WINDOW fields.
/// 🔒 build 44 / server v0.4.322 — `recordable` is now NARROWED to the give
///    window on the server (Nick 2026-08-28: "for future medications and past
///    missed ones, you should not be able to document refused or held. It was
///    missed, that's it."). A missed or not-yet-open dose arrives with
///    `recordable: false`, so the Record button disappears; only the window
///    chip + status chip explain why. Missed is final — the repair path is a
///    manager correction on the web dashboard.
///
///   `recordable`  = "staff can write a first record on this slot RIGHT NOW"
///   `giveAllowed` = the flag a client hides/disables its GIVEN option on.
///
/// ⚠️ THESE ARE A HINT, NOT THE CONTROL. `emar-core.recordAdministration`
/// refuses a late `given` no matter which client sends it (clean 409 +
/// `window` state), which is what makes the rule binding on builds ≤32 that
/// know nothing about these fields. Never treat the client-side hide as the
/// enforcement — always surface the server's 409 reason if a race slips
/// through (a dose can go missed while the sheet is open).
///
/// All five are OPTIONAL on purpose: a server that predates v0.4.295, or the
/// `MockData` demo payload, simply omits them and the app falls back to the
/// pre-window behaviour instead of failing to decode the whole due list.
struct DueMedication: Decodable, Identifiable {
    let id: Int
    let clientId: String
    let clientName: String
    let medName: String
    let instructions: String?
    let route: String?
    let dueTime: String?
    let dueTimeLabel: String?
    let status: String
    let late: Bool
    let initials: String?
    let recordable: Bool
    let giveAllowed: Bool?
    /// 'none' (no due_at — unconstrained) | 'early' | 'open' | 'closed'
    let giveWindowState: String?
    let giveWindowOpensLabel: String?
    let giveWindowClosesLabel: String?
    let giveWindowReason: String?

    /// Missing field (old server / mock data) ⇒ fall back to `recordable`, the
    /// pre-v0.4.295 behaviour. Never default to `false`: that would hide Given
    /// on every dose the moment the app talked to an older backend.
    var canGive: Bool { giveAllowed ?? recordable }

    /// True when the server told us the window is shut (either side of it).
    /// 'none' is NOT a closed window — it means the dose has no due time at
    /// all and is unconstrained.
    /// ⚠️ build 44 — keyed on "unrecorded" (status), NOT on `recordable`:
    /// since server v0.4.322 an out-of-window dose is no longer recordable at
    /// all, and the chip must still render on exactly those rows so staff see
    /// WHY there is no button.
    var windowBlocked: Bool {
        guard status == "pending" || status == "missed", initials == nil,
              let s = giveWindowState else { return false }
        return (s == "early" || s == "closed") && !canGive
    }

    /// Short chip text mirroring the web's my-day.ejs treatment:
    /// early → "opens 7:00 PM", closed → "window closed".
    var windowChipLabel: String? {
        guard windowBlocked else { return nil }
        if giveWindowState == "early" {
            if let opens = giveWindowOpensLabel { return "opens \(opens)" }
            return "not open yet"
        }
        if let closes = giveWindowClosesLabel { return "window closed \(closes)" }
        return "window closed"
    }

    /// The server's own prose refusal, shown in the record sheet so staff read
    /// the same sentence the API would have returned on a 409.
    var windowExplanation: String? {
        guard windowBlocked else { return nil }
        if let reason = giveWindowReason, !reason.isEmpty { return reason }
        if giveWindowState == "early", let opens = giveWindowOpensLabel {
            return "Too early — this dose cannot be recorded as given until \(opens)."
        }
        if let closes = giveWindowClosesLabel {
            return "This dose is past its one-hour window (it closed at \(closes)) and can no longer be recorded as given."
        }
        return "This dose is outside its one-hour give window."
    }
}

/// A PRN (as-needed) medication available to record for an individual on
/// today's shifts. Recording requires a reason; result is optional.
struct PrnMedication: Decodable, Identifiable {
    let id: Int
    let clientId: String
    let clientName: String
    let name: String
    let prnReason: String?
    let instructions: String?
    let route: String?
}

struct MedicationsResponse: Decodable {
    let due: [DueMedication]
    let prnMeds: [PrnMedication]
    let enabledClientIds: [String]
}

struct RecordAdministrationResponse: Decodable {
    let ok: Bool
    let late: Bool?
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case unauthorized(String)
    case conflict(String)
    case forbidden(String)
    case networkError(Error)
    case serverError(Int, String)
    case decodingError(Error)
    /// The server returned 2xx — the write SUCCEEDED — but the response body
    /// couldn't be decoded. This must never be treated as "the write failed":
    /// the V-2032 incident (2026-08-28) was a saved punch the app deleted
    /// because the 201 body was unreadable.
    case responseUnreadable(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized(let msg): return msg
        case .conflict(let msg): return msg
        case .forbidden(let msg): return msg
        case .networkError(let err):
            if isCancellation { return "Request was interrupted" }
            return "Connection error: \(err.localizedDescription)"
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        case .decodingError(let err): return "Data error: \(err.localizedDescription)"
        case .responseUnreadable:
            return "Your punch was recorded but the app couldn't read the response \u{2014} it will re-sync automatically."
        }
    }

    var isNetworkError: Bool {
        if case .networkError = self { return true }
        return false
    }

    /// True when the local record must be RETAINED and queued for re-sync:
    /// either the request may never have reached the server (network error) or
    /// it provably DID and succeeded (2xx with an unreadable body). A punch the
    /// user physically made must never vanish from the UI on these — the
    /// server-side idempotency check makes the replay safe.
    var isRetainable: Bool {
        if case .networkError = self { return true }
        if case .responseUnreadable = self { return true }
        return false
    }

    /// True when the underlying error is a task/request cancellation
    /// (NSURLErrorCancelled or Swift CancellationError).  These should
    /// never be surfaced to the user as real failures.
    var isCancellation: Bool {
        guard case .networkError(let err) = self else { return false }
        if let urlError = err as? URLError, urlError.code == .cancelled { return true }
        if err is CancellationError { return true }
        return false
    }
}

// MARK: - Offline Queue Item

struct QueuedAction: Identifiable, Codable {
    let id: UUID
    let type: ActionType
    let shiftId: Int?
    let visitId: String?
    let lat: Double?
    let lng: Double?
    let accuracy: Double?
    /// Manually entered service address (GPS-unavailable fallback punch).
    let address: String?
    let createdAt: Date
    // Note fields (for offline note queuing)
    let noteText: String?
    // Non-billable fields (for offline queuing)
    let nbCategory: String?
    let nbMinutes: Int?
    let nbNote: String?
    let nbDate: String?
    // Unscheduled visit fields (F1 offline)
    let unschedClientIds: [String]?
    let unschedService: String?
    let unschedClientName: String?   // F2 unlisted individual name
    let localVisitId: UUID?          // Links to the optimistic local Visit
    // Clock-out fields
    let signature: String?           // Base64 PNG for offline clock-out
    let signatureSkipReason: String? // Signature skip reason for offline clock-out
    // Time fix fields (offline time-fix queuing)
    let timeFixNewIn: String?
    let timeFixNewOut: String?
    let timeFixReason: String?
    // Manual time entry fields (non-EVV services, offline queuing)
    let manualStart: String?
    let manualEnd: String?
    // Retry tracking
    var retryCount: Int

    /// EVV punches are the legal record — these action types are NEVER
    /// silently discarded from the offline queue, no matter how many times
    /// the server rejects them.
    var isPunch: Bool {
        switch type {
        case .clockIn, .clockOut, .unscheduledVisit, .manualTime: return true
        case .addNote, .nonBillable, .timeFix: return false
        }
    }

    enum ActionType: String, Codable {
        case clockIn
        case clockOut
        case addNote
        case nonBillable
        case unscheduledVisit
        case timeFix
        case manualTime
    }

    enum CodingKeys: String, CodingKey {
        case id, type, shiftId, visitId, lat, lng, accuracy, address, createdAt
        case noteText, nbCategory, nbMinutes, nbNote, nbDate
        case unschedClientIds, unschedService, unschedClientName, localVisitId
        case signature, signatureSkipReason, timeFixNewIn, timeFixNewOut, timeFixReason, retryCount
        case manualStart, manualEnd
    }

    init(id: UUID, type: ActionType, shiftId: Int?, visitId: String?,
         lat: Double?, lng: Double?, accuracy: Double?, address: String? = nil, createdAt: Date,
         noteText: String? = nil, nbCategory: String? = nil, nbMinutes: Int? = nil,
         nbNote: String? = nil, nbDate: String? = nil,
         unschedClientIds: [String]? = nil, unschedService: String? = nil,
         unschedClientName: String? = nil, localVisitId: UUID? = nil,
         signature: String? = nil,
         signatureSkipReason: String? = nil,
         timeFixNewIn: String? = nil, timeFixNewOut: String? = nil, timeFixReason: String? = nil,
         manualStart: String? = nil, manualEnd: String? = nil,
         retryCount: Int = 0) {
        self.id = id
        self.type = type
        self.shiftId = shiftId
        self.visitId = visitId
        self.lat = lat
        self.lng = lng
        self.accuracy = accuracy
        self.address = address
        self.createdAt = createdAt
        self.noteText = noteText
        self.nbCategory = nbCategory
        self.nbMinutes = nbMinutes
        self.nbNote = nbNote
        self.nbDate = nbDate
        self.unschedClientIds = unschedClientIds
        self.unschedService = unschedService
        self.unschedClientName = unschedClientName
        self.localVisitId = localVisitId
        self.signature = signature
        self.signatureSkipReason = signatureSkipReason
        self.timeFixNewIn = timeFixNewIn
        self.timeFixNewOut = timeFixNewOut
        self.timeFixReason = timeFixReason
        self.manualStart = manualStart
        self.manualEnd = manualEnd
        self.retryCount = retryCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        type = try c.decode(ActionType.self, forKey: .type)
        shiftId = try c.decodeIfPresent(Int.self, forKey: .shiftId)
        visitId = try c.decodeIfPresent(String.self, forKey: .visitId)
        lat = try c.decodeIfPresent(Double.self, forKey: .lat)
        lng = try c.decodeIfPresent(Double.self, forKey: .lng)
        accuracy = try c.decodeIfPresent(Double.self, forKey: .accuracy)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        noteText = try c.decodeIfPresent(String.self, forKey: .noteText)
        nbCategory = try c.decodeIfPresent(String.self, forKey: .nbCategory)
        nbMinutes = try c.decodeIfPresent(Int.self, forKey: .nbMinutes)
        nbNote = try c.decodeIfPresent(String.self, forKey: .nbNote)
        nbDate = try c.decodeIfPresent(String.self, forKey: .nbDate)
        unschedClientIds = try c.decodeIfPresent([String].self, forKey: .unschedClientIds)
        unschedService = try c.decodeIfPresent(String.self, forKey: .unschedService)
        unschedClientName = try c.decodeIfPresent(String.self, forKey: .unschedClientName)
        localVisitId = try c.decodeIfPresent(UUID.self, forKey: .localVisitId)
        signature = try c.decodeIfPresent(String.self, forKey: .signature)
        signatureSkipReason = try c.decodeIfPresent(String.self, forKey: .signatureSkipReason)
        timeFixNewIn = try c.decodeIfPresent(String.self, forKey: .timeFixNewIn)
        timeFixNewOut = try c.decodeIfPresent(String.self, forKey: .timeFixNewOut)
        timeFixReason = try c.decodeIfPresent(String.self, forKey: .timeFixReason)
        manualStart = try c.decodeIfPresent(String.self, forKey: .manualStart)
        manualEnd = try c.decodeIfPresent(String.self, forKey: .manualEnd)
        retryCount = (try? c.decodeIfPresent(Int.self, forKey: .retryCount)) ?? 0
    }
}

// MARK: - API Client

actor APIClient {
    static let shared = APIClient()

    let baseURL: String

    private var token: String?

    init(baseURL: String = "https://d2hmfpgqkgeyu.cloudfront.net/api") {
        self.baseURL = baseURL
    }

    func setToken(_ token: String?) {
        self.token = token
    }

    func getToken() -> String? {
        return token
    }

    // MARK: - Login

    func login(email: String, password: String) async throws -> LoginResponse {
        let url = URL(string: "\(baseURL)/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LoginRequest(email: email, password: password))
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 401 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Invalid credentials"
            throw APIError.unauthorized(errBody)
        }
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Login failed"
            throw APIError.serverError(statusCode, errBody)
        }

        do {
            let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
            self.token = loginResponse.token
            return loginResponse
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Google Login

    func loginWithGoogle(idToken: String) async throws -> LoginResponse {
        let url = URL(string: "\(baseURL)/login/google")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GoogleLoginRequest(idToken: idToken))
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 401 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Invalid credentials"
            throw APIError.unauthorized(errBody)
        }
        if statusCode == 403 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Not authorized"
            throw APIError.forbidden(errBody)
        }
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Google login failed"
            throw APIError.serverError(statusCode, errBody)
        }

        do {
            let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)
            self.token = loginResponse.token
            return loginResponse
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Token refresh

    /// Sliding session renewal (server v0.4.275). Tokens expire after 12h
    /// (HIPAA automatic logoff); refreshing while the app is in active use
    /// keeps a long shift alive without weakening the expiry.
    func refreshToken() async {
        guard token != nil else { return }
        let url = URL(string: "\(baseURL)/token/refresh")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuth(&request)
        request.timeoutInterval = 15
        guard let (data, response) = try? await performRequest(request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let refreshed = try? JSONDecoder().decode(TokenRefreshResponse.self, from: data)
        else { return } // best-effort: a failed refresh just leaves the current token
        self.token = refreshed.token
    }

    // MARK: - Shifts

    func fetchShifts() async throws -> [ServerShift] {
        let url = URL(string: "\(baseURL)/me/shifts")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuth(&request)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to fetch shifts"
            throw APIError.serverError(statusCode, errBody)
        }

        do {
            return try JSONDecoder().decode(ShiftsResponse.self, from: data).shifts
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Clock In

    func clockIn(shiftId: Int, lat: Double? = nil, lng: Double? = nil, accuracy: Double? = nil, address: String? = nil) async throws -> ServerVisitInfo {
        let url = URL(string: "\(baseURL)/shifts/\(shiftId)/clock-in")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        request.httpBody = try JSONEncoder().encode(ClockInRequest(lat: lat, lng: lng, accuracy: accuracy, address: address))
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 409 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Already clocked in"
            throw APIError.conflict(errBody)
        }
        guard statusCode == 200 || statusCode == 201 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Clock in failed"
            throw APIError.serverError(statusCode, errBody)
        }

        do {
            return try JSONDecoder().decode(ClockInResponse.self, from: data).visit
        } catch {
            // 2xx reached: the punch is COMMITTED server-side. Never report
            // this as a failed write — see APIError.responseUnreadable.
            throw APIError.responseUnreadable(error)
        }
    }

    // MARK: - Manual Time Entry (non-EVV services)

    func manualTimeEntry(shiftId: Int, start: String, end: String) async throws -> ManualTimeResponse {
        let url = URL(string: "\(baseURL)/shifts/\(shiftId)/manual-time")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        request.httpBody = try JSONEncoder().encode(ManualTimeRequest(start: start, end: end))
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 409 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Manual time entry not allowed"
            throw APIError.conflict(errBody)
        }
        if statusCode == 403 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Not authorized"
            throw APIError.forbidden(errBody)
        }
        guard statusCode == 200 || statusCode == 201 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Manual time entry failed"
            throw APIError.serverError(statusCode, errBody)
        }

        do {
            return try JSONDecoder().decode(ManualTimeResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Clock Out

    func clockOut(visitId: String, lat: Double? = nil, lng: Double? = nil, accuracy: Double? = nil, signature: String? = nil, signatureSkipReason: String? = nil, address: String? = nil) async throws -> ServerVisitInfo {
        let url = URL(string: "\(baseURL)/visits/\(visitId)/clock-out")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        request.httpBody = try JSONEncoder().encode(ClockOutRequest(lat: lat, lng: lng, accuracy: accuracy, signature: signature, signatureSkipReason: signatureSkipReason, address: address))
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 409 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Already clocked out"
            throw APIError.conflict(errBody)
        }
        if statusCode == 403 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Not authorized"
            throw APIError.forbidden(errBody)
        }
        guard statusCode == 200 || statusCode == 201 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Clock out failed"
            throw APIError.serverError(statusCode, errBody)
        }

        do {
            return try JSONDecoder().decode(ClockOutResponse.self, from: data).visit
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Claim Shift

    func claimShift(shiftId: Int) async throws -> ServerShift {
        let url = URL(string: "\(baseURL)/shifts/\(shiftId)/claim")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 409 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Shift no longer available"
            throw APIError.conflict(errBody)
        }
        guard statusCode == 200 || statusCode == 201 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to claim shift"
            throw APIError.serverError(statusCode, errBody)
        }

        // Decode defensively: try {"shift": ...} wrapper first, then bare shift
        struct WrappedClaimResponse: Decodable {
            let shift: ServerShift
        }
        if let wrapped = try? JSONDecoder().decode(WrappedClaimResponse.self, from: data) {
            return wrapped.shift
        }
        do {
            return try JSONDecoder().decode(ServerShift.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Permanently claim one weekday of an open recurring rule (server
    /// v0.4.276). ONLINE-ONLY by design — never enqueued in the offline queue:
    /// a permanent claim of every future Monday must not fire silently hours
    /// after the staff member tapped it.
    func claimRuleWeekday(ruleId: Int, weekday: Int) async throws -> ClaimRuleResponse {
        let url = URL(string: "\(baseURL)/recurring/\(ruleId)/claim-weekday")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["weekday": weekday])
        request.timeoutInterval = 20

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 409 {
            // Taken by someone else, or overlapping shifts — the server names
            // the clashing dates in the message.
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "That schedule is no longer available"
            throw APIError.conflict(errBody)
        }
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to pick up the weekday"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(ClaimRuleResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - History Visits

    func fetchHistoryVisits(days: Int = 14) async throws -> [ServerHistoryVisit] {
        let url = URL(string: "\(baseURL)/me/visits?days=\(days)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuth(&request)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to fetch history"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(HistoryVisitsResponse.self, from: data).visits
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Requests (exceptions)

    func fetchRequests() async throws -> [ServerException] {
        let url = URL(string: "\(baseURL)/me/requests")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuth(&request)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to fetch requests"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(RequestsResponse.self, from: data).items
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Add Note

    func addNote(visitId: String, text: String) async throws -> NoteResponse {
        let url = URL(string: "\(baseURL)/visits/\(visitId)/note")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        request.httpBody = try JSONEncoder().encode(["text": text])
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 403 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Not authorized"
            throw APIError.forbidden(errBody)
        }
        guard statusCode == 200 || statusCode == 201 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to add note"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(NoteResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Structured Documentation

    func fetchDocumentation(visitId: String) async throws -> DocumentationTemplateResponse {
        let url = URL(string: "\(baseURL)/visits/\(visitId)/documentation")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuth(&request)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to fetch documentation"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(DocumentationTemplateResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func submitDocumentation(visitId: String, outcomes: [[String: Any]], additionalComments: String, questionAnswers: [[String: Any]] = [], transportReviewedGoals: Bool? = nil, serviceLocation: String? = nil, aiAssisted: Bool = false, aiInputText: String? = nil, aiModel: String? = nil) async throws -> DocumentationSubmitResponse {
        let url = URL(string: "\(baseURL)/visits/\(visitId)/documentation")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        var body: [String: Any] = [
            "outcomes": outcomes,
            "additionalComments": additionalComments,
            "questionAnswers": questionAnswers
        ]
        // Legacy compat: when the seeded transport question was answered Yes/No,
        // also send the old bool (server maps both ways; belt-and-suspenders).
        if let transport = transportReviewedGoals {
            body["transportReviewedGoals"] = transport
        }
        // Service Location (build 28): the server treats a PRESENT key as "this
        // client knows about the field" and validates it, so the key is only
        // sent when there is a real non-empty value to send.
        if let loc = serviceLocation, !loc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["serviceLocation"] = loc
        }
        if aiAssisted {
            body["aiAssisted"] = true
            if let inputText = aiInputText { body["aiInputText"] = inputText }
            if let model = aiModel { body["aiModel"] = model }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 403 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Not authorized"
            throw APIError.forbidden(errBody)
        }
        guard statusCode == 200 || statusCode == 201 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to submit documentation"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(DocumentationSubmitResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - AI Assist Draft

    func generateAIDraft(visitId: String, inputText: String) async throws -> AIDraftResponse {
        let url = URL(string: "\(baseURL)/visits/\(visitId)/ai-draft")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        let body: [String: Any] = ["inputText": inputText]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 25 // AI calls can take up to 20s server-side

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "AI draft failed"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(AIDraftResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Voice Documentation Conversation

    func docConversation(
        visitId: String,
        outcomes: [ConversationOutcome],
        individualName: String,
        service: String,
        history: [[String: String]],
        finish: Bool
    ) async throws -> DocConversationResponse {
        let url = URL(string: "\(baseURL)/ai/doc-conversation")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        request.timeoutInterval = 30 // Conversation turns may take a moment

        let outcomeDicts: [[String: Any]] = outcomes.map { o in
            var d: [String: Any] = ["title": o.title]
            if let g = o.goal { d["goal"] = g }
            return d
        }

        let body: [String: Any] = [
            "visitId": visitId,
            "outcomes": outcomeDicts,
            "individualName": individualName,
            "service": service,
            "history": history,
            "finish": finish,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Conversation request failed"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(DocConversationResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Non-Billable

    func createNonBillable(date: String?, category: String, minutes: Int, note: String) async throws -> NonBillableCreateResponse {
        let url = URL(string: "\(baseURL)/nonbillable")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        var body: [String: Any] = ["category": category, "minutes": minutes, "note": note]
        if let d = date { body["date"] = d }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 || statusCode == 201 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to create non-billable entry"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(NonBillableCreateResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func fetchNonBillable() async throws -> [NonBillableEntry] {
        let url = URL(string: "\(baseURL)/me/nonbillable")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuth(&request)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to fetch non-billable entries"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(NonBillableListResponse.self, from: data).entries ?? []
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Time Fix Request

    func requestTimeFix(visitId: String, newIn: String?, newOut: String?, reason: String) async throws -> ExceptionResponse {
        let url = URL(string: "\(baseURL)/visits/\(visitId)/time-fix")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        var body: [String: Any] = ["reason": reason]
        if let ni = newIn { body["newIn"] = ni }
        if let no = newOut { body["newOut"] = no }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 409 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "A request is already pending for this visit."
            throw APIError.conflict(errBody)
        }
        if statusCode == 403 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Not authorized"
            throw APIError.forbidden(errBody)
        }
        guard statusCode == 200 || statusCode == 201 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to submit time fix"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(ExceptionResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Delete Request

    func requestDelete(visitId: String, reason: String) async throws -> ExceptionResponse {
        let url = URL(string: "\(baseURL)/visits/\(visitId)/delete-request")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        let body: [String: Any] = ["reason": reason]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 409 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "A request is already pending for this visit."
            throw APIError.conflict(errBody)
        }
        if statusCode == 403 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Not authorized"
            throw APIError.forbidden(errBody)
        }
        guard statusCode == 200 || statusCode == 201 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to submit delete request"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(ExceptionResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Individuals (for unscheduled visit)

    func fetchIndividuals() async throws -> [ServerIndividualOption] {
        let url = URL(string: "\(baseURL)/individuals")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuth(&request)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to fetch individuals"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(IndividualsResponse.self, from: data).individuals
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Unscheduled Visit

    func createUnscheduledVisit(clientIds: [String], service: String?, lat: Double? = nil, lng: Double? = nil, accuracy: Double? = nil, address: String? = nil, unlistedName: String? = nil, startTime: String? = nil, endTime: String? = nil) async throws -> UnscheduledVisitResponse {
        let url = URL(string: "\(baseURL)/shifts/unscheduled")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        request.httpBody = try JSONEncoder().encode(
            UnscheduledVisitRequest(clientIds: clientIds.isEmpty ? nil : clientIds, service: service, lat: lat, lng: lng, accuracy: accuracy, address: address, unlistedName: unlistedName, startTime: startTime, endTime: endTime)
        )
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 || statusCode == 201 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to create unscheduled visit"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(UnscheduledVisitResponse.self, from: data)
        } catch {
            // 2xx reached: the visit is COMMITTED server-side. Never report
            // this as a failed write — see APIError.responseUnreadable.
            throw APIError.responseUnreadable(error)
        }
    }

    // MARK: - Shifts (full response)

    func fetchShiftsResponse() async throws -> ShiftsResponse {
        let url = URL(string: "\(baseURL)/me/shifts")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuth(&request)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to fetch shifts"
            throw APIError.serverError(statusCode, errBody)
        }

        do {
            return try JSONDecoder().decode(ShiftsResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Diagnostic Logs (F3)

    func submitLogs(entries: [[String: String]]) async throws {
        let url = URL(string: "\(baseURL)/logs")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["entries": entries])
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 || statusCode == 201 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to submit logs"
            throw APIError.serverError(statusCode, errBody)
        }
    }

    // MARK: - Helpers

    // MARK: - Staff Documents (compliance vault — live only, never queued)

    func fetchMyDocuments() async throws -> [StaffDocumentSlot] {
        let url = URL(string: "\(baseURL)/me/documents")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuth(&request)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to fetch documents"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(StaffDocumentsResponse.self, from: data).documents
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func uploadStaffDocument(typeId: Int, fileData: Data, filename: String, mimeType: String) async throws -> StaffDocumentUploadResponse {
        let url = URL(string: "\(baseURL)/me/documents/\(typeId)/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuth(&request)
        request.timeoutInterval = 60

        let boundary = "evv-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Upload failed"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(StaffDocumentUploadResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Work tab (v0.4.273 — online-only, never queued)

    func fetchWorkTodos() async throws -> WorkTodosResponse {
        let url = URL(string: "\(baseURL)/me/todos")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuth(&request)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to fetch to-dos"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(WorkTodosResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Toggle a REAL to-do (kind "todo"). Auto items are never toggleable —
    /// they clear by doing the underlying work. ONLINE-ONLY by design: callers
    /// must never enqueue this into the offline queue.
    func toggleTodo(id: Int) async throws -> Bool {
        let url = URL(string: "\(baseURL)/todos/\(id)/toggle")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuth(&request)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Could not update the to-do"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(ToggleTodoResponse.self, from: data).done
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - eMAR (v0.4.274 — online-only, NEVER queued)

    /// Due meds + PRN meds for the authenticated staff member — the same
    /// dueMedsForStaff payload the web My Day renders.
    func fetchDueMedications() async throws -> MedicationsResponse {
        let url = URL(string: "\(baseURL)/me/medications")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuth(&request)
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Failed to fetch medications"
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(MedicationsResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Record a due administration (given / refused / held).
    /// A reason is required for refused/held — enforced server-side.
    /// "Missed" is NOT a manual action (build 41 / server v0.4.315): missed is
    /// automatic — the server flips an untouched slot when its window closes
    /// and refuses a hand-picked missed with a 400.
    /// ⚠️ ONLINE-ONLY by design: callers must never enqueue this into the
    /// offline queue — a med recorded at sync time instead of administration
    /// time is a compliance problem, and a stale due list on a second device
    /// is a double-dose risk.
    func recordMedAdministration(id: Int, action: String, notes: String?) async throws -> Bool {
        let url = URL(string: "\(baseURL)/emar/administrations/\(id)/record")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        request.timeoutInterval = 15
        var body: [String: Any] = ["action": action]
        if let notes = notes, !notes.isEmpty { body["notes"] = notes }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Could not record the administration"
            // 🔒 build 33 — 409 is the GIVE-WINDOW refusal (server v0.4.295,
            //    emar-core.recordAdministration). Surface it as .conflict like
            //    every other route in this client so callers can branch on the
            //    rule instead of string-matching a generic "Server error
            //    (409)" prefix. The body carries the server's own prose, which
            //    is what the record sheet shows verbatim.
            if statusCode == 409 { throw APIError.conflict(errBody) }
            throw APIError.serverError(statusCode, errBody)
        }
        do {
            return try JSONDecoder().decode(RecordAdministrationResponse.self, from: data).late ?? false
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// Record a PRN (as-needed) administration. Reason required; result optional.
    /// ⚠️ ONLINE-ONLY — same rule as recordMedAdministration.
    func recordPrnAdministration(clientId: String, medicationId: Int, reason: String, result: String?, notes: String?) async throws {
        let url = URL(string: "\(baseURL)/individuals/\(clientId)/emar/prn")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        request.timeoutInterval = 15
        var body: [String: Any] = ["medication_id": medicationId, "prn_reason": reason]
        if let result = result, !result.isEmpty { body["prn_result"] = result }
        if let notes = notes, !notes.isEmpty { body["notes"] = notes }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)
        try checkAuth(response, data: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Could not record the PRN administration"
            throw APIError.serverError(statusCode, errBody)
        }
    }

    private func addAuth(_ request: inout URLRequest) {
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            // Retry once after a brief pause — cancellations are often
            // transient (structured-task teardown, network path change).
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 s
            do {
                return try await URLSession.shared.data(for: request)
            } catch {
                throw APIError.networkError(error)
            }
        } catch is CancellationError {
            try? await Task.sleep(nanoseconds: 300_000_000)
            do {
                return try await URLSession.shared.data(for: request)
            } catch {
                throw APIError.networkError(error)
            }
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func checkAuth(_ response: URLResponse, data: Data) throws {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 401 {
            let errBody = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error ?? "Session expired"
            throw APIError.unauthorized(errBody)
        }
    }
}
