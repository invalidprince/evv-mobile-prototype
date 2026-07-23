import SwiftUI
import Combine
import Network

final class AppState: ObservableObject {
    // MARK: - Auth
    @Published var isLoggedIn = false
    @Published var currentStaff = MockData.currentStaff

    /// True when the user entered via "Demo Login" (TestFlight review mode).
    /// All screens show the orange "DEMO MODE" banner. No real API calls.
    @Published var isDemoMode = false

    // MARK: - Mode
    @Published var mode: AppMode = .mock
    @Published var serverStaff: ServerStaff?  // populated after server login
    @Published var serverToken: String?

    // MARK: - Server loading / errors
    @Published var isLoadingShifts = false
    @Published var serverError: String?
    @Published var showServerError = false
    @Published var claimingShiftId: Int?  // tracks which open shift is being claimed

    // MARK: - Server open shifts (7-day window unassigned shifts)
    @Published var serverOpenShifts: [ServerShift] = []

    // MARK: - Server individuals (for unscheduled visit selection)
    @Published var serverIndividuals: [ServerIndividualOption] = []
    @Published var isLoadingIndividuals = false

    // MARK: - History (server mode)
    @Published var historyVisits: [Visit] = []           // from GET /me/visits
    @Published var serverExceptions: [ServerException] = [] // from GET /me/requests
    @Published var isLoadingHistory = false

    // MARK: - Visits
    @Published var todayVisits: [Visit] = MockData.todaysVisits()
    @Published var pastVisits: [Visit] = MockData.pastVisits()
    @Published var openShifts: [OpenShift] = MockData.openShifts()

    // MARK: - Notes (drafts keyed by visit id)
    @Published var noteDrafts: [UUID: VisitNote] = [:]

    // MARK: - Offline queue (server mode)
    @Published var offlineQueue: [QueuedAction] = []

    // MARK: - Demo settings
    @Published var simulateGPSUnavailable = false
    /// When on, the app pretends it has no network regardless of the real
    /// NWPathMonitor status.  Flipping it off counts as an offline→online
    /// transition and will auto-sync any pending items.
    @Published var simulateOffline = false

    // MARK: - Connectivity
    @Published var isOnline = true
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "connectivity-monitor")

    /// Effective connectivity: hardware online AND not in simulated-offline mode.
    var effectivelyOnline: Bool { isOnline && !simulateOffline }

    // MARK: - Sync
    @Published var pendingSyncCount = 2
    @Published var lastSync = Date().addingTimeInterval(-14 * 60)
    @Published var isSyncing = false

    /// Fires whenever a new pending item is created; debounced into a single
    /// syncNow() call so rapid clock-out / note / request bursts coalesce.
    private let syncTrigger = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Timer
    @Published var elapsed: TimeInterval = 0
    private var timer: Timer?

    var activeVisit: Visit? {
        todayVisits.first { $0.status == .inProgress }
    }

    /// Shifts scheduled for today only (server mode: filters the 7-day window
    /// to just today's date; mock mode: returns all todayVisits).
    var todayOnlyVisits: [Visit] {
        guard mode == .server else { return todayVisits }
        return todayVisits.filter { Calendar.current.isDateInToday($0.scheduledStart) }
    }

    /// All scheduled visits grouped by date for the Schedule tab (server mode).
    /// Returns an array of (date, label, visits) sorted by date.
    /// Excludes in-progress and completed visits (Schedule = upcoming only).
    var groupedScheduleVisits: [(date: Date, label: String, visits: [Visit])] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!

        var groups: [Date: [Visit]] = [:]
        for visit in todayVisits where visit.status == .scheduled {
            let day = cal.startOfDay(for: visit.scheduledStart)
            groups[day, default: []].append(visit)
        }

        return groups.keys.sorted().map { date in
            let label: String
            if cal.isDate(date, inSameDayAs: today) {
                label = "Today"
            } else if cal.isDate(date, inSameDayAs: tomorrow) {
                label = "Tomorrow"
            } else {
                let f = DateFormatter()
                f.dateFormat = "EEEE, MMM d"
                label = f.string(from: date)
            }
            let sorted = groups[date]!.sorted { $0.scheduledStart < $1.scheduledStart }
            return (date, label, sorted)
        }
    }

    /// Completed visits (today or past) whose note still needs finishing.
    var incompleteNoteVisits: [Visit] {
        let today = todayVisits.filter { $0.status == .completed && !$0.docComplete }
        let past = pastVisits.filter { $0.status == .completed && !$0.docComplete }
        return (today + past).sorted { $0.scheduledStart > $1.scheduledStart }
    }

    init() {
        startTimerIfNeeded()
        refreshLateDocumentationFlags()
        // Notifications: ask permission at app start and make sure every
        // incomplete note has its end-of-day + midnight-late reminders queued.
        NoteReminderCenter.shared.activate()
        for visit in incompleteNoteVisits {
            NoteReminderCenter.shared.scheduleReminders(for: visit)
        }
        setupConnectivityMonitor()
        setupAutoSyncPipeline()
    }

    // MARK: - Connectivity monitor

    private func setupConnectivityMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let wasEffectivelyOnline = self.effectivelyOnline
                self.isOnline = (path.status == .satisfied)
                let nowEffectivelyOnline = self.effectivelyOnline
                // offline → online transition: auto-sync if items are pending
                if !wasEffectivelyOnline && nowEffectivelyOnline && self.pendingSyncCount > 0 {
                    self.syncNow()
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    // MARK: - Auto-sync pipeline (debounced)

    private func setupAutoSyncPipeline() {
        syncTrigger
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }
                guard self.effectivelyOnline, self.pendingSyncCount > 0, !self.isSyncing else { return }
                self.syncNow()
            }
            .store(in: &cancellables)

        // Watch the simulateOffline toggle: flipping from true → false
        // is equivalent to an offline → online transition.
        $simulateOffline
            .removeDuplicates()
            .dropFirst()          // skip the initial value
            .sink { [weak self] nowSimulated in
                guard let self = self else { return }
                if !nowSimulated && self.isOnline && self.pendingSyncCount > 0 {
                    self.syncNow()
                }
            }
            .store(in: &cancellables)
    }

    /// Call when a new pending item is created; if online, schedules a
    /// debounced auto-sync (~2 s).  If offline the item stays queued and
    /// will sync on the next connectivity or foreground event.
    private func scheduleAutoSync() {
        syncTrigger.send()
    }

    /// Call from the app's scenePhase handler when the app comes to the
    /// foreground.
    func handleSceneActive() {
        guard effectivelyOnline, pendingSyncCount > 0, !isSyncing else { return }
        syncNow()
    }

    // MARK: - Late-documentation rule

    /// Same-day note rule: an incomplete note that crosses midnight becomes
    /// late. Stamp the manager-visible flag on anything already past due.
    func refreshLateDocumentationFlags() {
        for i in todayVisits.indices where todayVisits[i].noteIsLate {
            todayVisits[i].lateDocumentation = true
        }
        for i in pastVisits.indices where pastVisits[i].noteIsLate {
            pastVisits[i].lateDocumentation = true
        }
    }

    var elapsedText: String {
        let total = Int(elapsed)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    func startTimerIfNeeded() {
        timer?.invalidate()
        guard let visit = activeVisit, let start = visit.actualStart else {
            elapsed = 0
            return
        }
        elapsed = Date().timeIntervalSince(start)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, let v = self.activeVisit, let s = v.actualStart else { return }
            self.elapsed = Date().timeIntervalSince(s)
        }
    }

    // MARK: - Punch actions
    func clockIn(visitId: UUID, manualLocation: ManualLocation? = nil) {
        guard activeVisit == nil else { return }
        guard let idx = todayVisits.firstIndex(where: { $0.id == visitId }) else { return }

        if mode == .server, let shiftId = todayVisits[idx].serverShiftId {
            // Server mode: optimistic update + API call
            todayVisits[idx].status = .inProgress
            todayVisits[idx].actualStart = Date()
            startTimerIfNeeded()
            haptic(.success)

            if !effectivelyOnline {
                // Offline: queue and keep the optimistic update
                todayVisits[idx].syncState = .pending
                enqueueOfflineAction(.clockIn, shiftId: shiftId, visitId: nil, localVisitId: visitId)
                DiagnosticLogger.shared.logOffline("Clock-in queued offline for shift \(shiftId)")
                scheduleAutoSync()
                return
            }

            Task { @MainActor in
                do {
                    // Pass GPS coordinates if available
                    let coords = LocationManager.shared.currentCoordinates
                    let visitInfo = try await APIClient.shared.clockIn(
                        shiftId: shiftId,
                        lat: coords?.lat,
                        lng: coords?.lng,
                        accuracy: coords?.accuracy
                    )
                    if let i = self.todayVisits.firstIndex(where: { $0.id == visitId }) {
                        self.todayVisits[i].serverVisitId = visitInfo.id
                        self.todayVisits[i].syncState = .synced
                    }
                    await self.refreshServerShifts()
                } catch let error as APIError {
                    if error.isNetworkError {
                        // Keep the optimistic update, queue for later
                        if let i = self.todayVisits.firstIndex(where: { $0.id == visitId }) {
                            self.todayVisits[i].syncState = .pending
                        }
                        self.enqueueOfflineAction(.clockIn, shiftId: shiftId, visitId: nil, localVisitId: visitId)
                        DiagnosticLogger.shared.logOffline("Clock-in queued (network error) for shift \(shiftId)")
                        self.scheduleAutoSync()
                    } else {
                        self.surfaceServerError(error)
                        DiagnosticLogger.shared.logAPI("Clock-in failed: \(error.localizedDescription)")
                        if let i = self.todayVisits.firstIndex(where: { $0.id == visitId }) {
                            self.todayVisits[i].status = .scheduled
                            self.todayVisits[i].actualStart = nil
                        }
                        self.startTimerIfNeeded()
                        await self.refreshServerShifts()
                    }
                } catch {
                    self.surfaceServerError(APIError.networkError(error))
                }
            }
        } else {
            // Mock mode
            todayVisits[idx].actualStart = Date()
            todayVisits[idx].status = .inProgress
            if let loc = manualLocation {
                todayVisits[idx].manualLocation = loc
                todayVisits[idx].manualLocationFlagged = true
            }
            startTimerIfNeeded()
            haptic(.success)
        }
    }

    @discardableResult
    func clockOut(signatureSkipReason: String? = nil) -> Visit? {
        guard let idx = todayVisits.firstIndex(where: { $0.status == .inProgress }) else { return nil }
        let visitId = todayVisits[idx].id

        if mode == .server {
            let serverVisitId = todayVisits[idx].serverVisitId
            // Collect all visit IDs to clock out (1:2 has multiple)
            let allVisitIds: [String]
            if let svid = serverVisitId {
                allVisitIds = todayVisits[idx].serverVisitIds.isEmpty ? [svid] : todayVisits[idx].serverVisitIds
            } else {
                allVisitIds = []
            }

            // Server mode: optimistic update + API call
            todayVisits[idx].actualEnd = Date()
            todayVisits[idx].status = .completed
            todayVisits[idx].syncState = .pending
            let finished = todayVisits[idx]
            startTimerIfNeeded()
            haptic(.success)
            NoteReminderCenter.shared.scheduleReminders(for: finished)

            // If offline or no server visit ID yet (offline clock-in), queue immediately
            if !effectivelyOnline || allVisitIds.isEmpty {
                for vid in allVisitIds {
                    enqueueOfflineAction(.clockOut, shiftId: nil, visitId: vid)
                }
                if allVisitIds.isEmpty {
                    // Visit was created offline, mark pending
                    DiagnosticLogger.shared.logOffline("Clock-out queued (no server visit ID yet)")
                }
                scheduleAutoSync()
                return finished
            }

            Task { @MainActor in
                do {
                    // Clock out all visits (1:2 creates one visit per individual)
                    for vid in allVisitIds {
                        _ = try await APIClient.shared.clockOut(visitId: vid, signatureSkipReason: signatureSkipReason)
                    }
                    if let i = self.todayVisits.firstIndex(where: { $0.id == visitId }) {
                        self.todayVisits[i].syncState = .synced
                    }
                    await self.refreshServerShifts()
                } catch let error as APIError {
                    if error.isNetworkError {
                        // Enqueue each visit for offline sync
                        for vid in allVisitIds {
                            self.enqueueOfflineAction(.clockOut, shiftId: nil, visitId: vid)
                        }
                        self.scheduleAutoSync()
                        DiagnosticLogger.shared.logOffline("Clock-out queued (network error)")
                    } else {
                        self.surfaceServerError(error)
                        DiagnosticLogger.shared.logAPI("Clock-out failed: \(error.localizedDescription)")
                        if let i = self.todayVisits.firstIndex(where: { $0.id == visitId }) {
                            self.todayVisits[i].actualEnd = nil
                            self.todayVisits[i].status = .inProgress
                            self.todayVisits[i].syncState = .synced
                        }
                        self.startTimerIfNeeded()
                    }
                } catch {
                    self.surfaceServerError(APIError.networkError(error))
                }
            }

            return finished
        } else {
            // Mock mode
            todayVisits[idx].actualEnd = Date()
            todayVisits[idx].status = .completed
            todayVisits[idx].syncState = .pending
            pendingSyncCount += 1
            let finished = todayVisits[idx]
            startTimerIfNeeded()
            haptic(.success)
            NoteReminderCenter.shared.scheduleReminders(for: finished)
            scheduleAutoSync()
            return finished
        }
    }

    func startUnscheduledVisit(clients: [Client], service: ServiceType, serviceName: String? = nil, unlistedName: String? = nil, noService: Bool = false) {
        guard activeVisit == nil else { return }

        if mode == .server {
            // Server mode: POST to server, then refresh
            let now = Date()
            let localVisitId = UUID()
            var visit = Visit(id: localVisitId, clients: clients, service: service,
                              scheduledStart: now, scheduledEnd: now.addingTimeInterval(2 * 3600),
                              actualStart: now, actualEnd: nil,
                              status: .inProgress, isGroup: clients.count > 1)
            visit.unlistedIndividualName = unlistedName
            todayVisits.append(visit)
            startTimerIfNeeded()
            haptic(.success)

            // Collect all server individual IDs (stored in address field); empty for unlisted
            let serverClientIds = clients.map { $0.address }.filter { !$0.isEmpty }
            // Use the original service description if provided (matches what the API expects)
            let apiServiceName: String? = noService ? nil : (serviceName ?? service.rawValue)

            if !effectivelyOnline {
                // Offline: keep local visit, queue for later sync
                if let i = todayVisits.firstIndex(where: { $0.id == localVisitId }) {
                    todayVisits[i].syncState = .pending
                }
                enqueueOfflineAction(.unscheduledVisit, shiftId: nil, visitId: nil,
                                     unschedClientIds: serverClientIds.isEmpty ? nil : serverClientIds,
                                     unschedService: apiServiceName,
                                     unschedClientName: unlistedName,
                                     localVisitId: localVisitId)
                DiagnosticLogger.shared.logOffline("Unscheduled visit queued offline")
                scheduleAutoSync()
                return
            }

            Task { @MainActor in
                do {
                    let coords = LocationManager.shared.currentCoordinates
                    let response = try await APIClient.shared.createUnscheduledVisit(
                        clientIds: serverClientIds,
                        service: apiServiceName,
                        lat: coords?.lat,
                        lng: coords?.lng,
                        accuracy: coords?.accuracy,
                        unlistedName: unlistedName
                    )
                    // Update the local visit with server IDs so clock-out works
                    if let i = self.todayVisits.firstIndex(where: { $0.id == localVisitId }) {
                        self.todayVisits[i].serverVisitId = response.visit.id
                        // Store all visit IDs for 1:2 clock-out
                        if let allVisits = response.visits, allVisits.count > 1 {
                            self.todayVisits[i].serverVisitIds = allVisits.map { $0.id }
                        } else {
                            self.todayVisits[i].serverVisitIds = [response.visit.id]
                        }
                        if let shift = response.shift {
                            self.todayVisits[i].serverShiftId = shift.id
                        }
                        self.todayVisits[i].syncState = .synced
                    }
                } catch let error as APIError {
                    if error.isNetworkError {
                        // Keep local visit, queue for later
                        if let i = self.todayVisits.firstIndex(where: { $0.id == localVisitId }) {
                            self.todayVisits[i].syncState = .pending
                        }
                        self.enqueueOfflineAction(.unscheduledVisit, shiftId: nil, visitId: nil,
                                                  unschedClientIds: serverClientIds.isEmpty ? nil : serverClientIds,
                                                  unschedService: apiServiceName,
                                                  unschedClientName: unlistedName,
                                                  localVisitId: localVisitId)
                        DiagnosticLogger.shared.logOffline("Unscheduled visit queued (network error)")
                        self.scheduleAutoSync()
                    } else {
                        self.surfaceServerError(error)
                        DiagnosticLogger.shared.logAPI("Unscheduled visit failed: \(error.localizedDescription)")
                        self.todayVisits.removeAll { $0.id == localVisitId }
                        self.startTimerIfNeeded()
                    }
                } catch {
                    self.surfaceServerError(APIError.networkError(error))
                    self.todayVisits.removeAll { $0.id == localVisitId }
                    self.startTimerIfNeeded()
                }
            }
        } else {
            // Mock mode
            let now = Date()
            let visit = Visit(id: UUID(), clients: clients, service: service,
                              scheduledStart: now, scheduledEnd: now.addingTimeInterval(2 * 3600),
                              actualStart: now, actualEnd: nil,
                              status: .inProgress, isGroup: clients.count > 1)
            todayVisits.append(visit)
            startTimerIfNeeded()
            haptic(.success)
        }
    }

    func startUnscheduledVisitWithoutService(clients: [Client]) {
        guard activeVisit == nil else { return }
        // Reuse the same offline-capable flow but with noService=true
        startUnscheduledVisit(clients: clients, service: .inHomeSupport, serviceName: nil, unlistedName: nil, noService: true)
    }

    func acceptOpenShift(_ shift: OpenShift) {
        openShifts.removeAll { $0.id == shift.id }
        let visit = Visit(id: UUID(), clients: [shift.client], service: shift.service,
                          scheduledStart: shift.start, scheduledEnd: shift.end,
                          actualStart: nil, actualEnd: nil, status: .scheduled)
        todayVisits.append(visit)
    }

    func declineOpenShift(_ shift: OpenShift) {
        openShifts.removeAll { $0.id == shift.id }
    }

    func markDocComplete(visitId: UUID) {
        let now = Date()
        if let idx = todayVisits.firstIndex(where: { $0.id == visitId }) {
            if now >= todayVisits[idx].noteDeadline {
                todayVisits[idx].lateDocumentation = true   // completed late — permanent
            }
            todayVisits[idx].docComplete = true
        }
        if let idx = pastVisits.firstIndex(where: { $0.id == visitId }) {
            if now >= pastVisits[idx].noteDeadline {
                pastVisits[idx].lateDocumentation = true    // completed late — permanent
            }
            pastVisits[idx].docComplete = true
        }
        // Note is done — no more reminders needed.
        NoteReminderCenter.shared.cancelReminders(for: visitId)
    }

    /// Demo affordance (More tab): fire a note reminder notification now.
    func sendTestNoteReminder(late: Bool) {
        let clientName = incompleteNoteVisits.first?.client.name ?? MockData.clients[0].name
        NoteReminderCenter.shared.sendTestReminder(clientName: clientName, late: late)
    }

    func requestTimeFix(visitId: UUID) {
        if let idx = pastVisits.firstIndex(where: { $0.id == visitId }) {
            pastVisits[idx].timeFixStatus = .pending
            pendingSyncCount += 1
            scheduleAutoSync()
        }
    }

    func requestDelete(visitId: UUID) {
        if let idx = pastVisits.firstIndex(where: { $0.id == visitId }) {
            pastVisits[idx].deleteRequestStatus = .pending
            pendingSyncCount += 1
            scheduleAutoSync()
        }
        if let idx = todayVisits.firstIndex(where: { $0.id == visitId }) {
            todayVisits[idx].deleteRequestStatus = .pending
            // Only bump pending once even though both arrays may match
            if pastVisits.first(where: { $0.id == visitId }) == nil {
                pendingSyncCount += 1
                scheduleAutoSync()
            }
        }
    }

    // MARK: - Notes
    func noteDraft(for visitId: UUID) -> VisitNote {
        noteDrafts[visitId] ?? VisitNote()
    }

    func saveNoteDraft(visitId: UUID, note: VisitNote) {
        noteDrafts[visitId] = note
    }

    func submitNote(visitId: UUID, note: VisitNote) {
        noteDrafts[visitId] = note
        markDocComplete(visitId: visitId)
        pendingSyncCount += 1
        scheduleAutoSync()
    }

    func isDocComplete(visitId: UUID) -> Bool {
        if let v = todayVisits.first(where: { $0.id == visitId }) { return v.docComplete }
        if let v = pastVisits.first(where: { $0.id == visitId }) { return v.docComplete }
        return false
    }

    func syncNow() {
        guard !isSyncing else { return }
        isSyncing = true

        if mode == .server {
            Task { @MainActor in
                await self.replayOfflineQueue()
                await self.refreshServerShifts()
                self.isSyncing = false
                self.pendingSyncCount = offlineQueue.count
                self.lastSync = Date()
                for i in self.todayVisits.indices where self.todayVisits[i].syncState == .pending {
                    self.todayVisits[i].syncState = .synced
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self else { return }
                self.isSyncing = false
                self.pendingSyncCount = 0
                self.lastSync = Date()
                for i in self.todayVisits.indices where self.todayVisits[i].syncState == .pending {
                    self.todayVisits[i].syncState = .synced
                }
                for i in self.pastVisits.indices where self.pastVisits[i].syncState == .pending {
                    self.pastVisits[i].syncState = .synced
                }
            }
        }
    }

    func signOut() {
        isLoggedIn = false
        isDemoMode = false
        mode = .mock
        serverStaff = nil
        serverToken = nil
        offlineQueue.removeAll()
        Task { await APIClient.shared.setToken(nil) }
        currentStaff = MockData.currentStaff
        todayVisits = []
        pastVisits = []
        openShifts = []
        historyVisits = []
        serverExceptions = []
        serverOpenShifts = []
    }

    // MARK: - Demo login (TestFlight review)

    func loginAsDemo() {
        isDemoMode = true
        mode = .mock
        currentStaff = Staff(id: UUID(), name: "Demo Reviewer", role: "Direct Support Professional")
        todayVisits = MockData.todaysVisits()
        pastVisits = MockData.pastVisits()
        openShifts = MockData.openShifts()
        pendingSyncCount = 0
        isLoggedIn = true
        startTimerIfNeeded()
    }

    // MARK: - Server login

    func loginWithGoogle(idToken: String) async throws {
        let response = try await APIClient.shared.loginWithGoogle(idToken: idToken)
        await MainActor.run {
            self.serverStaff = response.staff
            self.serverToken = response.token
            self.mode = .server
            self.currentStaff = Staff(
                id: UUID(),
                name: response.staff.name,
                role: response.staff.departmentName
            )
            self.todayVisits = []
            self.pastVisits = []
            self.openShifts = []
            self.serverOpenShifts = []
            self.pendingSyncCount = 0
            self.isLoggedIn = true
        }
        await refreshServerShifts()
        LocationManager.shared.requestPermission()
    }

    func loginWithServer(email: String) async throws {
        let response = try await APIClient.shared.login(email: email)
        await MainActor.run {
            self.serverStaff = response.staff
            self.serverToken = response.token
            self.mode = .server
            self.currentStaff = Staff(
                id: UUID(),
                name: response.staff.name,
                role: response.staff.departmentName
            )
            self.todayVisits = []
            self.pastVisits = []
            self.openShifts = []
            self.serverOpenShifts = []
            self.pendingSyncCount = 0
            self.isLoggedIn = true
        }
        await refreshServerShifts()
        LocationManager.shared.requestPermission()
    }

    // MARK: - Server individuals fetch

    @MainActor
    func refreshIndividuals() async {
        guard mode == .server else { return }
        isLoadingIndividuals = true
        defer { isLoadingIndividuals = false }
        do {
            serverIndividuals = try await APIClient.shared.fetchIndividuals()
        } catch {
            surfaceServerError(error as? APIError ?? .networkError(error))
        }
    }

    // MARK: - Server shift fetch & mapping

    @MainActor
    func refreshServerShifts() async {
        guard mode == .server else { return }
        isLoadingShifts = true
        defer { isLoadingShifts = false }

        do {
            let response = try await APIClient.shared.fetchShiftsResponse()
            scheduleLoadError = nil  // clear any previous error
            let mapped = response.shifts.compactMap { mapServerShift($0) }

            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            var newToday: [Visit] = []
            var newPast: [Visit] = []

            for visit in mapped {
                if cal.isDate(visit.scheduledStart, inSameDayAs: today) ||
                   visit.scheduledStart >= today {
                    newToday.append(visit)
                } else {
                    newPast.append(visit)
                }
            }

            // Preserve note-draft / doc-complete state and precise actualStart for in-progress visits
            for i in newToday.indices {
                if let existing = todayVisits.first(where: { $0.serverShiftId == newToday[i].serverShiftId }) {
                    newToday[i].docComplete = existing.docComplete
                    newToday[i].lateDocumentation = existing.lateDocumentation
                    // Preserve the precise actualStart from the optimistic update;
                    // the server only stores minute-precision times ("H:MM AM/PM")
                    // so re-parsing would lose the seconds component.
                    if existing.status == .inProgress, let existingStart = existing.actualStart,
                       newToday[i].status == .inProgress {
                        newToday[i].actualStart = existingStart
                    }
                }
            }

            todayVisits = newToday
            pastVisits = newPast
            serverOpenShifts = response.openShifts ?? []
            lastSync = Date()
            startTimerIfNeeded()
        } catch {
            let apiErr = error as? APIError ?? .networkError(error)
            scheduleLoadError = apiErr.localizedDescription
            surfaceServerError(apiErr)
        }
    }

    private func mapServerShift(_ s: ServerShift) -> Visit? {
        guard let startDate = parseShiftDateTime(dateStr: s.date, timeStr: s.start),
              let endDate = parseShiftDateTime(dateStr: s.date, timeStr: s.end) else {
            return nil
        }

        let client = Client(
            id: UUID(),
            name: s.individual.name,
            address: s.location ?? "",
            city: ""
        )

        let serviceType = mapServiceType(s.service ?? "")

        var status: VisitStatus = .scheduled
        var actualStart: Date? = nil
        var actualEnd: Date? = nil
        var serverVisitId: String? = nil

        if let myVisit = s.myVisit {
            serverVisitId = myVisit.id
            // Clock times from the API are "H:MM AM/PM" format, not ISO 8601
            actualStart = parseShiftDateTime(dateStr: s.date, timeStr: myVisit.clockIn)
                ?? parseISO8601(myVisit.clockIn)  // fallback for ISO format
            if let co = myVisit.clockOut {
                actualEnd = parseShiftDateTime(dateStr: s.date, timeStr: co)
                    ?? parseISO8601(co)
                status = .completed
            } else {
                status = .inProgress
            }
        }

        let partners = (s.partners ?? []).map { PartnerInfo(staffId: $0.staffId, name: $0.name) }
        let is21 = s.ratio == "2:1"

        var teamStaff: Staff? = nil
        if is21, let first = partners.first {
            teamStaff = Staff(id: UUID(), name: first.name, role: "Partner")
        }

        var visit = Visit(
            id: UUID(),
            clients: [client],
            service: serviceType,
            scheduledStart: startDate,
            scheduledEnd: endDate,
            actualStart: actualStart,
            actualEnd: actualEnd,
            status: status,
            teamStaff: teamStaff
        )
        visit.serverShiftId = s.id
        visit.serverVisitId = serverVisitId
        visit.ratio = s.ratio
        visit.partners = partners
        visit.serverLocation = s.location

        // Populate all visit IDs for 1:2 clock-out
        if let myVisits = s.myVisits, myVisits.count > 1 {
            visit.serverVisitIds = myVisits.map { $0.id }
        } else if let vid = serverVisitId {
            visit.serverVisitIds = [vid]
        }

        return visit
    }

    private func mapServiceType(_ service: String) -> ServiceType {
        let lower = service.lowercased()
        if lower.contains("home") || lower.contains("in-home") { return .inHomeSupport }
        if lower.contains("community") { return .communityParticipation }
        if lower.contains("companion") { return .companion }
        if lower.contains("respite") { return .respite }
        return .inHomeSupport
    }

    /// Today's date string in "yyyy-MM-dd" format (ET timezone)
    private func todayET() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func parseShiftDateTime(dateStr: String, timeStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd h:mm a"
        if let d = formatter.date(from: "\(dateStr) \(timeStr)") { return d }
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        if let d = formatter.date(from: "\(dateStr) \(timeStr)") { return d }
        return nil
    }

    private func parseISO8601(_ str: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: str) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: str)
    }

    // MARK: - Claim open shift (server mode)

    @MainActor
    func claimOpenShift(shiftId: Int) async {
        claimingShiftId = shiftId
        defer { claimingShiftId = nil }

        do {
            _ = try await APIClient.shared.claimShift(shiftId: shiftId)
            await refreshServerShifts()
        } catch let error as APIError {
            if case .conflict = error {
                serverError = "Shift no longer available"
                showServerError = true
            } else {
                surfaceServerError(error)
            }
            await refreshServerShifts()
        } catch {
            surfaceServerError(.networkError(error))
            await refreshServerShifts()
        }
    }

    // MARK: - Offline queue

    private func enqueueOfflineAction(_ type: QueuedAction.ActionType, shiftId: Int?, visitId: String?,
                                        noteText: String? = nil,
                                        nbCategory: String? = nil, nbMinutes: Int? = nil,
                                        nbNote: String? = nil, nbDate: String? = nil,
                                        unschedClientIds: [String]? = nil, unschedService: String? = nil,
                                        unschedClientName: String? = nil, localVisitId: UUID? = nil) {
        let coords = LocationManager.shared.currentCoordinates
        let action = QueuedAction(
            id: UUID(),
            type: type,
            shiftId: shiftId,
            visitId: visitId,
            lat: coords?.lat,
            lng: coords?.lng,
            accuracy: coords?.accuracy,
            createdAt: Date(),
            noteText: noteText,
            nbCategory: nbCategory,
            nbMinutes: nbMinutes,
            nbNote: nbNote,
            nbDate: nbDate,
            unschedClientIds: unschedClientIds,
            unschedService: unschedService,
            unschedClientName: unschedClientName,
            localVisitId: localVisitId
        )
        offlineQueue.append(action)
        pendingSyncCount = offlineQueue.count
        DiagnosticLogger.shared.logOffline("Queued \(type.rawValue) action (queue size: \(offlineQueue.count))")
    }

    @MainActor
    private func replayOfflineQueue() async {
        guard !offlineQueue.isEmpty else { return }
        var remaining: [QueuedAction] = []
        DiagnosticLogger.shared.logSync("Replaying \(offlineQueue.count) offline action(s)")

        for action in offlineQueue {
            do {
                switch action.type {
                case .clockIn:
                    if let shiftId = action.shiftId {
                        let visitInfo = try await APIClient.shared.clockIn(shiftId: shiftId, lat: action.lat, lng: action.lng, accuracy: action.accuracy)
                        // Update local visit with server visit ID
                        if let localId = action.localVisitId,
                           let i = todayVisits.firstIndex(where: { $0.id == localId }) {
                            todayVisits[i].serverVisitId = visitInfo.id
                            todayVisits[i].syncState = .synced
                        }
                    }
                case .clockOut:
                    if let visitId = action.visitId {
                        _ = try await APIClient.shared.clockOut(visitId: visitId, lat: action.lat, lng: action.lng, accuracy: action.accuracy)
                    }
                case .addNote:
                    if let visitId = action.visitId, let text = action.noteText {
                        let resp = try await APIClient.shared.addNote(visitId: visitId, text: text)
                        if let ds = resp.docStatus {
                            if let i = historyVisits.firstIndex(where: { $0.serverVisitId == visitId }) {
                                historyVisits[i].hasNote = true
                                historyVisits[i].serverDocStatus = ds
                                if ds.lowercased() == "complete" { historyVisits[i].docComplete = true }
                            }
                        }
                    }
                case .nonBillable:
                    if let cat = action.nbCategory, let mins = action.nbMinutes {
                        _ = try await APIClient.shared.createNonBillable(
                            date: action.nbDate, category: cat, minutes: mins, note: action.nbNote ?? "")
                    }
                case .unscheduledVisit:
                    if let clientIds = action.unschedClientIds {
                        let response = try await APIClient.shared.createUnscheduledVisit(
                            clientIds: clientIds, service: action.unschedService,
                            lat: action.lat, lng: action.lng, accuracy: action.accuracy,
                            unlistedName: action.unschedClientName)
                        // Update local visit with real server IDs
                        if let localId = action.localVisitId,
                           let i = todayVisits.firstIndex(where: { $0.id == localId }) {
                            todayVisits[i].serverVisitId = response.visit.id
                            if let allVisits = response.visits, allVisits.count > 1 {
                                todayVisits[i].serverVisitIds = allVisits.map { $0.id }
                            } else {
                                todayVisits[i].serverVisitIds = [response.visit.id]
                            }
                            if let shift = response.shift {
                                todayVisits[i].serverShiftId = shift.id
                            }
                            todayVisits[i].syncState = .synced
                        }
                    }
                }
            } catch let error as APIError {
                if error.isNetworkError {
                    remaining.append(action)
                } else {
                    DiagnosticLogger.shared.logSync("Replay failed for \(action.type.rawValue): \(error.localizedDescription)")
                    surfaceServerError(error)
                }
            } catch {
                remaining.append(action)
            }
        }

        let synced = offlineQueue.count - remaining.count
        if synced > 0 {
            DiagnosticLogger.shared.logSync("\(synced) action(s) synced successfully")
        }
        if !remaining.isEmpty && synced > 0 {
            serverError = "\(synced) action(s) synced late"
            showServerError = true
        }

        offlineQueue = remaining
        pendingSyncCount = remaining.count
    }

    // MARK: - Server History Fetch

    @MainActor
    func refreshHistory() async {
        guard mode == .server else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            async let visitsTask = APIClient.shared.fetchHistoryVisits(days: 14)
            async let requestsTask = APIClient.shared.fetchRequests()
            let (serverVisits, exceptions) = try await (visitsTask, requestsTask)

            serverExceptions = exceptions
            historyVisits = serverVisits.compactMap { mapHistoryVisit($0, exceptions: exceptions) }
        } catch {
            surfaceServerError(error as? APIError ?? .networkError(error))
        }
    }

    private func mapHistoryVisit(_ sv: ServerHistoryVisit, exceptions: [ServerException]) -> Visit? {
        let client = Client(
            id: UUID(),
            name: sv.individual?.name ?? "Unknown",
            address: "",
            city: ""
        )
        let serviceType = mapServiceType(sv.service ?? "")

        var actualStart: Date? = nil
        var actualEnd: Date? = nil
        let histDate = sv.date ?? todayET()
        if let ci = sv.clockIn {
            actualStart = parseShiftDateTime(dateStr: histDate, timeStr: ci)
                ?? parseISO8601(ci)
        }
        if let co = sv.clockOut {
            actualEnd = parseShiftDateTime(dateStr: histDate, timeStr: co)
                ?? parseISO8601(co)
        }

        let visitStatus: VisitStatus
        switch sv.status?.lowercased() {
        case "completed", "verified", "edited": visitStatus = .completed
        case "in_progress", "in-progress", "in progress", "active": visitStatus = .inProgress
        case "missed", "voided": visitStatus = .missed
        default: visitStatus = actualEnd != nil ? .completed : (actualStart != nil ? .inProgress : .scheduled)
        }

        // Map pending exceptions for this visit
        let visitExceptions = exceptions.filter { $0.visitId == sv.id }
        var tfStatus: TimeFixStatus = .none
        var drStatus: DeleteRequestStatus = .none
        for exc in visitExceptions {
            let resolved = exc.status?.lowercased() == "resolved"
            let resolution = exc.resolution?.lowercased()
            let typeLower = exc.type?.lowercased() ?? ""
            if typeLower.contains("time") && (typeLower.contains("change") || typeLower.contains("fix")) {
                if resolved {
                    tfStatus = resolution == "approved" ? .approved : .denied
                } else {
                    tfStatus = .pending
                }
            }
            if typeLower.contains("delete") {
                if resolved {
                    drStatus = resolution == "approved" ? .approved : .denied
                } else {
                    drStatus = .pending
                }
            }
        }

        var visit = Visit(
            id: UUID(),
            clients: [client],
            service: serviceType,
            scheduledStart: actualStart ?? Date(),
            scheduledEnd: actualEnd ?? (actualStart ?? Date()).addingTimeInterval(3600),
            actualStart: actualStart,
            actualEnd: actualEnd,
            status: visitStatus
        )
        visit.serverVisitId = sv.id
        visit.serverShiftId = sv.shiftId
        visit.timeFixStatus = tfStatus
        visit.deleteRequestStatus = drStatus
        visit.hasNote = sv.hasNote ?? false
        visit.serverDocStatus = sv.docStatus
        if let dur = sv.duration {
            // Use duration from server (minutes) to compute end if missing
            if actualEnd == nil, let start = actualStart {
                visit.actualEnd = start.addingTimeInterval(Double(dur) * 60)
                visit.scheduledEnd = visit.actualEnd!
            }
        }

        return visit
    }

    // MARK: - Server Note Submission

    func submitServerNote(visitId: UUID, serverVisitId: String, text: String) async {
        if !effectivelyOnline {
            // Queue for offline replay
            enqueueOfflineAction(.addNote, shiftId: nil, visitId: serverVisitId, noteText: text)
            pendingSyncCount = offlineQueue.count
            scheduleAutoSync()
            // Optimistically mark note as present locally
            await MainActor.run {
                if let i = historyVisits.firstIndex(where: { $0.serverVisitId == serverVisitId }) {
                    historyVisits[i].hasNote = true
                    historyVisits[i].serverDocStatus = "complete"
                    historyVisits[i].docComplete = true
                }
                if let i = todayVisits.firstIndex(where: { $0.serverVisitId == serverVisitId }) {
                    todayVisits[i].hasNote = true
                    todayVisits[i].docComplete = true
                }
                markDocComplete(visitId: visitId)
            }
            return
        }

        do {
            let response = try await APIClient.shared.addNote(visitId: serverVisitId, text: text)
            await MainActor.run {
                let docStatus = response.docStatus ?? "complete"
                let isComplete = docStatus.lowercased() == "complete"
                // Update hasNote + docStatus on matching visits (B1 fix)
                if let i = historyVisits.firstIndex(where: { $0.serverVisitId == serverVisitId }) {
                    historyVisits[i].hasNote = true
                    historyVisits[i].serverDocStatus = docStatus
                    if isComplete { historyVisits[i].docComplete = true }
                }
                if let i = todayVisits.firstIndex(where: { $0.serverVisitId == serverVisitId }) {
                    todayVisits[i].hasNote = true
                    if isComplete { todayVisits[i].docComplete = true }
                }
                if isComplete {
                    markDocComplete(visitId: visitId)
                }
            }
        } catch let error as APIError {
            if error.isNetworkError {
                enqueueOfflineAction(.addNote, shiftId: nil, visitId: serverVisitId, noteText: text)
                await MainActor.run {
                    pendingSyncCount = offlineQueue.count
                    scheduleAutoSync()
                }
            } else {
                await MainActor.run { surfaceServerError(error) }
                DiagnosticLogger.shared.logAPI("Note submission failed: \(error.localizedDescription)")
            }
        } catch {
            await MainActor.run { surfaceServerError(.networkError(error)) }
        }
    }

    // MARK: - Server Non-Billable

    func submitServerNonBillable(category: String, minutes: Int, note: String, date: String?) async -> Bool {
        if !effectivelyOnline {
            enqueueOfflineAction(.nonBillable, shiftId: nil, visitId: nil,
                                 nbCategory: category, nbMinutes: minutes, nbNote: note, nbDate: date)
            await MainActor.run {
                pendingSyncCount = offlineQueue.count
                scheduleAutoSync()
            }
            return true
        }

        do {
            _ = try await APIClient.shared.createNonBillable(date: date, category: category, minutes: minutes, note: note)
            return true
        } catch let error as APIError {
            if error.isNetworkError {
                enqueueOfflineAction(.nonBillable, shiftId: nil, visitId: nil,
                                     nbCategory: category, nbMinutes: minutes, nbNote: note, nbDate: date)
                await MainActor.run {
                    pendingSyncCount = offlineQueue.count
                    scheduleAutoSync()
                }
                return true
            } else {
                await MainActor.run { surfaceServerError(error) }
                return false
            }
        } catch {
            await MainActor.run { surfaceServerError(.networkError(error)) }
            return false
        }
    }

    // MARK: - Server Time Fix

    /// Returns nil on success, or an error message on failure.
    func submitServerTimeFix(visitId: UUID, serverVisitId: String, newIn: String?, newOut: String?, reason: String) async -> String? {
        do {
            _ = try await APIClient.shared.requestTimeFix(visitId: serverVisitId, newIn: newIn, newOut: newOut, reason: reason)
            await MainActor.run {
                if let i = historyVisits.firstIndex(where: { $0.serverVisitId == serverVisitId }) {
                    historyVisits[i].timeFixStatus = .pending
                }
            }
            return nil
        } catch let error as APIError {
            return error.localizedDescription
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Server Delete Request

    /// Returns nil on success, or an error message on failure.
    func submitServerDeleteRequest(visitId: UUID, serverVisitId: String, reason: String) async -> String? {
        do {
            _ = try await APIClient.shared.requestDelete(visitId: serverVisitId, reason: reason)
            await MainActor.run {
                if let i = historyVisits.firstIndex(where: { $0.serverVisitId == serverVisitId }) {
                    historyVisits[i].deleteRequestStatus = .pending
                }
            }
            return nil
        } catch let error as APIError {
            return error.localizedDescription
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Diagnostic log submission (F3)

    func submitDiagnosticLog() async -> Bool {
        let entries = DiagnosticLogger.shared.exportEntries()
        guard !entries.isEmpty else { return false }

        do {
            try await APIClient.shared.submitLogs(entries: entries)
            DiagnosticLogger.shared.clear()
            return true
        } catch {
            DiagnosticLogger.shared.logAPI("Log submission failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Error surfacing

    /// Schedule-specific error (for inline display in ScheduleView)
    @Published var scheduleLoadError: String?

    func surfaceServerError(_ error: APIError) {
        serverError = error.localizedDescription
        showServerError = true
        DiagnosticLogger.shared.logAPI(error.localizedDescription)
    }

    func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    // MARK: - Formatted sync status

    /// Human-readable relative text for the last sync time, e.g. "just now",
    /// "2m ago", "1h ago".
    var lastSyncRelativeText: String {
        let seconds = Int(Date().timeIntervalSince(lastSync))
        if seconds < 15 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: lastSync)
    }
}
