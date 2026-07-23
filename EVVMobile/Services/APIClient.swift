import Foundation

// MARK: - API Response Types (Codable)

struct LoginRequest: Encodable {
    let email: String
}

struct GoogleLoginRequest: Encodable {
    let idToken: String
}

struct LoginResponse: Decodable {
    let token: String
    let staff: ServerStaff
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
}

struct ServerShiftVisitInfo: Decodable {
    let id: String
    let clientId: String?
    let clockIn: String?
    let clockOut: String?
    let status: String?
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
}

struct ShiftsResponse: Decodable {
    let shifts: [ServerShift]
    let openShifts: [ServerShift]?
}

struct ClockInRequest: Encodable {
    let lat: Double?
    let lng: Double?
    let accuracy: Double?
}

struct ClockOutRequest: Encodable {
    let lat: Double?
    let lng: Double?
    let accuracy: Double?
    let signatureSkipReason: String?
}

struct ClockInResponse: Decodable {
    let visit: ServerVisitInfo
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

struct ServerIndividualOption: Decodable, Identifiable {
    let id: String
    let name: String
    let services: [String]?
    let serviceCodes: [String]?
}

struct IndividualsResponse: Decodable {
    let individuals: [ServerIndividualOption]
}

// MARK: - Unscheduled visit creation

struct UnscheduledVisitRequest: Encodable {
    let clientIds: [String]
    let service: String?
    let lat: Double?
    let lng: Double?
    let accuracy: Double?
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

// MARK: - API Errors

enum APIError: LocalizedError {
    case unauthorized(String)
    case conflict(String)
    case forbidden(String)
    case networkError(Error)
    case serverError(Int, String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized(let msg): return msg
        case .conflict(let msg): return msg
        case .forbidden(let msg): return msg
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        case .decodingError(let err): return "Data error: \(err.localizedDescription)"
        }
    }

    var isNetworkError: Bool {
        if case .networkError = self { return true }
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
    let createdAt: Date
    // Note fields (for offline note queuing)
    let noteText: String?
    // Non-billable fields (for offline queuing)
    let nbCategory: String?
    let nbMinutes: Int?
    let nbNote: String?
    let nbDate: String?

    enum ActionType: String, Codable {
        case clockIn
        case clockOut
        case addNote
        case nonBillable
    }
}

// MARK: - API Client

actor APIClient {
    static let shared = APIClient()

    let baseURL: String

    private var token: String?

    init(baseURL: String = "https://evv-poc-production.up.railway.app/api") {
        self.baseURL = baseURL
    }

    func setToken(_ token: String?) {
        self.token = token
    }

    func getToken() -> String? {
        return token
    }

    // MARK: - Login

    func login(email: String) async throws -> LoginResponse {
        let url = URL(string: "\(baseURL)/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LoginRequest(email: email))
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

    func clockIn(shiftId: Int, lat: Double? = nil, lng: Double? = nil, accuracy: Double? = nil) async throws -> ServerVisitInfo {
        let url = URL(string: "\(baseURL)/shifts/\(shiftId)/clock-in")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        request.httpBody = try JSONEncoder().encode(ClockInRequest(lat: lat, lng: lng, accuracy: accuracy))
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
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Clock Out

    func clockOut(visitId: String, lat: Double? = nil, lng: Double? = nil, accuracy: Double? = nil, signatureSkipReason: String? = nil) async throws -> ServerVisitInfo {
        let url = URL(string: "\(baseURL)/visits/\(visitId)/clock-out")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        request.httpBody = try JSONEncoder().encode(ClockOutRequest(lat: lat, lng: lng, accuracy: accuracy, signatureSkipReason: signatureSkipReason))
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

    func createUnscheduledVisit(clientIds: [String], service: String?, lat: Double? = nil, lng: Double? = nil, accuracy: Double? = nil) async throws -> UnscheduledVisitResponse {
        let url = URL(string: "\(baseURL)/shifts/unscheduled")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&request)
        request.httpBody = try JSONEncoder().encode(
            UnscheduledVisitRequest(clientIds: clientIds, service: service, lat: lat, lng: lng, accuracy: accuracy)
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
            throw APIError.decodingError(error)
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

    // MARK: - Helpers

    private func addAuth(_ request: inout URLRequest) {
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
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
