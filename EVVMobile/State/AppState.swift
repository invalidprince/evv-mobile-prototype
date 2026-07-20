import SwiftUI
import Combine
import Network

final class AppState: ObservableObject {
    // MARK: - Auth
    @Published var isLoggedIn = false
    @Published var currentStaff = MockData.currentStaff

    // MARK: - Mode
    @Published var mode: AppMode = .mock
    @Published var serverStaff: ServerStaff?  // populated after server login
    @Published var serverToken: String?

    // MARK: - Server loading / errors
    @Published var isLoadingShifts = false
    @Published var serverError: String?
    @Published var showServerError = false

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

            Task { @MainActor in
                do {
                    let visitInfo = try await APIClient.shared.clockIn(shiftId: shiftId)
                    if let i = self.todayVisits.firstIndex(where: { $0.id == visitId }) {
                        self.todayVisits[i].serverVisitId = visitInfo.id
                    }
                    await self.refreshServerShifts()
                } catch let error as APIError {
                    if error.isNetworkError {
                        self.enqueueOfflineAction(.clockIn, shiftId: shiftId, visitId: nil)
                    } else {
                        self.surfaceServerError(error)
                        if let i = self.todayVisits.firstIndex(where: { $0.id == visitId }) {
                            self.todayVisits[i].status = .scheduled
                            self.todayVisits[i].actualStart = nil
                        }
                        self.startTimerIfNeeded()
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
    func clockOut() -> Visit? {
        guard let idx = todayVisits.firstIndex(where: { $0.status == .inProgress }) else { return nil }
        let visitId = todayVisits[idx].id

        if mode == .server, let serverVisitId = todayVisits[idx].serverVisitId {
            // Server mode: optimistic update + API call
            todayVisits[idx].actualEnd = Date()
            todayVisits[idx].status = .completed
            todayVisits[idx].syncState = .pending
            let finished = todayVisits[idx]
            startTimerIfNeeded()
            haptic(.success)
            NoteReminderCenter.shared.scheduleReminders(for: finished)

            Task { @MainActor in
                do {
                    _ = try await APIClient.shared.clockOut(visitId: serverVisitId)
                    if let i = self.todayVisits.firstIndex(where: { $0.id == visitId }) {
                        self.todayVisits[i].syncState = .synced
                    }
                    await self.refreshServerShifts()
                } catch let error as APIError {
                    if error.isNetworkError {
                        self.enqueueOfflineAction(.clockOut, shiftId: nil, visitId: serverVisitId)
                        self.pendingSyncCount += 1
                        self.scheduleAutoSync()
                    } else {
                        self.surfaceServerError(error)
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

    func startUnscheduledVisit(clients: [Client], service: ServiceType) {
        guard activeVisit == nil else { return }
        let now = Date()
        let visit = Visit(id: UUID(), clients: clients, service: service,
                          scheduledStart: now, scheduledEnd: now.addingTimeInterval(2 * 3600),
                          actualStart: now, actualEnd: nil,
                          status: .inProgress, isGroup: clients.count > 1)
        todayVisits.append(visit)
        startTimerIfNeeded()
        haptic(.success)
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
        mode = .mock
        serverStaff = nil
        serverToken = nil
        offlineQueue.removeAll()
        Task { await APIClient.shared.setToken(nil) }
        currentStaff = MockData.currentStaff
        todayVisits = MockData.todaysVisits()
        pastVisits = MockData.pastVisits()
        openShifts = MockData.openShifts()
    }

    // MARK: - Server login

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
            self.pendingSyncCount = 0
            self.isLoggedIn = true
        }
        await refreshServerShifts()
    }

    // MARK: - Server shift fetch & mapping

    @MainActor
    func refreshServerShifts() async {
        guard mode == .server else { return }
        isLoadingShifts = true
        defer { isLoadingShifts = false }

        do {
            let serverShifts = try await APIClient.shared.fetchShifts()
            let mapped = serverShifts.compactMap { mapServerShift($0) }

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

            // Preserve note-draft / doc-complete state
            for i in newToday.indices {
                if let existing = todayVisits.first(where: { $0.serverShiftId == newToday[i].serverShiftId }) {
                    newToday[i].docComplete = existing.docComplete
                    newToday[i].lateDocumentation = existing.lateDocumentation
                }
            }

            todayVisits = newToday
            pastVisits = newPast
            lastSync = Date()
            startTimerIfNeeded()
        } catch {
            surfaceServerError(error as? APIError ?? .networkError(error))
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

        let serviceType = mapServiceType(s.service)

        var status: VisitStatus = .scheduled
        var actualStart: Date? = nil
        var actualEnd: Date? = nil
        var serverVisitId: String? = nil

        if let myVisit = s.myVisit {
            serverVisitId = myVisit.id
            actualStart = parseISO8601(myVisit.clockIn)
            if let co = myVisit.clockOut {
                actualEnd = parseISO8601(co)
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

    private func parseShiftDateTime(dateStr: String, timeStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
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

    // MARK: - Offline queue

    private func enqueueOfflineAction(_ type: QueuedAction.ActionType, shiftId: Int?, visitId: String?) {
        let action = QueuedAction(
            id: UUID(),
            type: type,
            shiftId: shiftId,
            visitId: visitId,
            lat: nil,
            lng: nil,
            accuracy: nil,
            createdAt: Date()
        )
        offlineQueue.append(action)
        pendingSyncCount = offlineQueue.count
    }

    @MainActor
    private func replayOfflineQueue() async {
        guard !offlineQueue.isEmpty else { return }
        var remaining: [QueuedAction] = []

        for action in offlineQueue {
            do {
                switch action.type {
                case .clockIn:
                    if let shiftId = action.shiftId {
                        _ = try await APIClient.shared.clockIn(shiftId: shiftId)
                    }
                case .clockOut:
                    if let visitId = action.visitId {
                        _ = try await APIClient.shared.clockOut(visitId: visitId)
                    }
                }
            } catch let error as APIError {
                if error.isNetworkError {
                    remaining.append(action)
                } else {
                    surfaceServerError(error)
                }
            } catch {
                remaining.append(action)
            }
        }

        if !remaining.isEmpty && offlineQueue.count != remaining.count {
            serverError = "\(offlineQueue.count - remaining.count) action(s) synced late"
            showServerError = true
        }

        offlineQueue = remaining
        pendingSyncCount = remaining.count
    }

    // MARK: - Error surfacing

    func surfaceServerError(_ error: APIError) {
        serverError = error.localizedDescription
        showServerError = true
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
