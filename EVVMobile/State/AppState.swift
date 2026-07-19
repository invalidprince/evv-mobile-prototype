import SwiftUI
import Combine

final class AppState: ObservableObject {
    // MARK: - Auth
    @Published var isLoggedIn = false
    @Published var currentStaff = MockData.currentStaff

    // MARK: - Visits
    @Published var todayVisits: [Visit] = MockData.todaysVisits()
    @Published var pastVisits: [Visit] = MockData.pastVisits()
    @Published var openShifts: [OpenShift] = MockData.openShifts()

    // MARK: - Notes (drafts keyed by visit id)
    @Published var noteDrafts: [UUID: VisitNote] = [:]

    // MARK: - Demo settings
    @Published var simulateGPSUnavailable = false

    // MARK: - Sync
    @Published var pendingSyncCount = 2
    @Published var lastSync = Date().addingTimeInterval(-14 * 60)
    @Published var isSyncing = false

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
    }

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
        todayVisits[idx].actualStart = Date()
        todayVisits[idx].status = .inProgress
        if let loc = manualLocation {
            todayVisits[idx].manualLocation = loc
            todayVisits[idx].manualLocationFlagged = true
        }
        startTimerIfNeeded()
        haptic(.success)
    }

    @discardableResult
    func clockOut() -> Visit? {
        guard let idx = todayVisits.firstIndex(where: { $0.status == .inProgress }) else { return nil }
        todayVisits[idx].actualEnd = Date()
        todayVisits[idx].status = .completed
        todayVisits[idx].syncState = .pending
        pendingSyncCount += 1
        let finished = todayVisits[idx]
        startTimerIfNeeded()
        haptic(.success)
        // Note is now owed for this visit — queue the same-day reminders.
        NoteReminderCenter.shared.scheduleReminders(for: finished)
        return finished
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
        }
    }

    func requestDelete(visitId: UUID) {
        if let idx = pastVisits.firstIndex(where: { $0.id == visitId }) {
            pastVisits[idx].deleteRequestStatus = .pending
        }
        if let idx = todayVisits.firstIndex(where: { $0.id == visitId }) {
            todayVisits[idx].deleteRequestStatus = .pending
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
    }

    func isDocComplete(visitId: UUID) -> Bool {
        if let v = todayVisits.first(where: { $0.id == visitId }) { return v.docComplete }
        if let v = pastVisits.first(where: { $0.id == visitId }) { return v.docComplete }
        return false
    }

    func syncNow() {
        isSyncing = true
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

    func signOut() {
        isLoggedIn = false
    }

    func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
