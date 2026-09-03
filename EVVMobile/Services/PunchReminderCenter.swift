import Foundation
import UserNotifications

// ---------------------------------------------------------------------------
// PunchReminderCenter — LOCAL notifications for a forgotten clock-in / clock-out
// (build 60; server v0.4.430; Todoist 6hQfcR8RVvmvqFcq).
//
// Nick, #evv 2026-09-03: "I love the automatic reminder on the app saying hey
// your notes not done yet. Can we do something similar when somebody forgot to
// clock in/clock out just like the texts, but it being push notification?"
//
// "Something similar" = the NoteReminderCenter mechanism, deliberately: the
// same UNUserNotificationCenter local scheduling (no APNs, no device tokens,
// no server push service), the same "schedule when we know, cancel the moment
// the thing is done" contract, the same foreground-banner delegate (already
// installed by NoteReminderCenter.activate()).
//
// "Same triggers as the texts" = the server's missed-punch SMS definitions
// (punch-alerts.js, v0.4.366), which GET /api/me/shifts now publishes as
// `punchReminders`:
//   • missed CLOCK-IN  — a scheduled shift's start + clockInAfterMin has passed
//                        and the staff member has not clocked in.
//   • missed CLOCK-OUT — a running visit's scheduled end + clockOutAfterMin has
//                        passed and it is still open.
// The minutes are the STAFF legs of Settings → Punch Alerts, so the phone buzzes
// at exactly the moment the staff text would go out. `appEnabled` is that
// page's "Phone reminders" switch (default on; independent of the SMS master
// switch and the per-service texting opt-in — a phone reminder is free).
//
// Where this differs from the server engine, and why:
//   • It can only remind about shifts the app has SEEN. A shift added on the
//     web after the last refresh cannot be scheduled until the app refreshes.
//     That is the inherent limit of local notifications; the SMS engine covers
//     the gap server-side, and a server-push (APNs) upgrade is a separate card.
//   • It never fires for a manual-time service (requiresClockIn == false) or a
//     pending shift request — there is no punch to miss.
//   • Identifiers are keyed on the SERVER ids (shift id for clock-in, visit id
//     for clock-out), never on `Visit.id`, which is a fresh UUID on every
//     refresh (the build 57 lesson) — a reminder keyed on it could never be
//     cancelled.
//   • Every refresh RECONCILES: all pending punch reminders are replaced by the
//     plan computed from the fresh Today list, so a shift that was punched,
//     cancelled, re-timed or deleted on any device loses its reminder on the
//     next refresh, and a reminder is never duplicated.
//
// The planner is a PURE function (PunchReminderPlanner.plan) so it can be
// exercised without a simulator — see docs/punch-reminder-check in the
// evv-poc repo.
// ---------------------------------------------------------------------------

/// The phone's reminder policy as published by GET /api/me/shifts
/// (`punchReminders`, server v0.4.430). Older servers omit the key → nil →
/// no punch reminders are scheduled.
struct PunchReminderPolicy: Decodable, Equatable {
    /// Settings → Punch Alerts → "Phone reminders" switch.
    let appEnabled: Bool?
    /// Minutes after the scheduled START with no punch; nil = that reminder is off.
    let clockInAfterMin: Int?
    /// Minutes after the scheduled END with the visit still open; nil = off.
    let clockOutAfterMin: Int?

    var isEnabled: Bool { appEnabled ?? false }
}

/// One row of what the planner needs to know about a Today entry. Built from
/// `Visit` by `PunchReminderInput.init(visit:)`; kept as its own struct so the
/// planner can be compiled and tested without the whole model layer.
struct PunchReminderInput: Equatable {
    let serverShiftId: Int?
    let serverVisitId: String?
    let isScheduled: Bool
    let isInProgress: Bool
    let requiresClockIn: Bool
    let isPendingApproval: Bool
    let scheduledStart: Date
    let scheduledEnd: Date
    let clientName: String

    init(serverShiftId: Int?, serverVisitId: String?, isScheduled: Bool, isInProgress: Bool,
         requiresClockIn: Bool, isPendingApproval: Bool, scheduledStart: Date, scheduledEnd: Date,
         clientName: String) {
        self.serverShiftId = serverShiftId
        self.serverVisitId = serverVisitId
        self.isScheduled = isScheduled
        self.isInProgress = isInProgress
        self.requiresClockIn = requiresClockIn
        self.isPendingApproval = isPendingApproval
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
        self.clientName = clientName
    }
}

/// A notification the planner wants pending. Equatable so a test can compare
/// whole plans.
struct PlannedPunchReminder: Equatable {
    enum Kind: String {
        case clockIn = "punch-in"
        case clockOut = "punch-out"
    }
    let identifier: String
    let kind: Kind
    let fireAt: Date
    let title: String
    let body: String
}

enum PunchReminderPlanner {
    /// Every punch-reminder identifier starts with this, so a reconcile can
    /// find and drop exactly its own requests and never touch a note reminder
    /// ("note-eod-…" / "note-late-…") or anything else.
    static let identifierPrefix = "punch-"

    static func clockInIdentifier(shiftId: Int) -> String { "punch-in-shift-\(shiftId)" }
    static func clockOutIdentifier(visitId: String) -> String { "punch-out-visit-\(visitId)" }
    /// A visit that was clocked in OFFLINE has no server visit id yet; its
    /// clock-out reminder is keyed on the shift until the queue replays.
    static func clockOutIdentifier(shiftId: Int) -> String { "punch-out-shift-\(shiftId)" }

    /// The pure plan: which reminders should be pending, given what Today
    /// shows right now. Triggers already in the past are skipped (a calendar
    /// trigger in the past would fire immediately — the NoteReminderCenter
    /// guard).
    static func plan(inputs: [PunchReminderInput], policy: PunchReminderPolicy?, now: Date = Date()) -> [PlannedPunchReminder] {
        guard let policy = policy, policy.isEnabled else { return [] }
        var out: [PlannedPunchReminder] = []
        var seen = Set<String>()
        let timeFmt = DateFormatter()
        timeFmt.dateStyle = .none
        timeFmt.timeStyle = .short

        for row in inputs {
            // Structural exemptions — the server's, mirrored: no punch to miss.
            guard row.requiresClockIn, !row.isPendingApproval else { continue }

            if row.isScheduled, let shiftId = row.serverShiftId, let mins = policy.clockInAfterMin, mins > 0 {
                let fireAt = row.scheduledStart.addingTimeInterval(TimeInterval(mins) * 60)
                let id = clockInIdentifier(shiftId: shiftId)
                if fireAt > now, !seen.contains(id) {
                    seen.insert(id)
                    out.append(PlannedPunchReminder(
                        identifier: id, kind: .clockIn, fireAt: fireAt,
                        title: "Forgot to clock in?",
                        body: "Your \(timeFmt.string(from: row.scheduledStart)) shift with \(row.clientName) has started and you haven't clocked in. Open the app to punch in."))
                }
            }

            if row.isInProgress, let mins = policy.clockOutAfterMin, mins > 0 {
                // A scheduled end at or before the start is an overnight shift
                // (12 AM → 12 AM is a full day) — the end is the next day.
                var end = row.scheduledEnd
                if end <= row.scheduledStart { end = end.addingTimeInterval(86_400) }
                let fireAt = end.addingTimeInterval(TimeInterval(mins) * 60)
                let id: String
                if let vid = row.serverVisitId, !vid.isEmpty {
                    id = clockOutIdentifier(visitId: vid)
                } else if let shiftId = row.serverShiftId {
                    id = clockOutIdentifier(shiftId: shiftId)
                } else {
                    continue
                }
                if fireAt > now, !seen.contains(id) {
                    seen.insert(id)
                    out.append(PlannedPunchReminder(
                        identifier: id, kind: .clockOut, fireAt: fireAt,
                        title: "Still clocked in?",
                        body: "Your visit with \(row.clientName) was scheduled to end at \(timeFmt.string(from: end)) and you're still clocked in. Open the app to clock out."))
                }
            }
        }
        return out.sorted { $0.fireAt < $1.fireAt }
    }
}

/// Schedules / reconciles / cancels the local punch reminders.
final class PunchReminderCenter {
    static let shared = PunchReminderCenter()

    private let center = UNUserNotificationCenter.current()
    /// The policy from the most recent shifts refresh — kept so a punch made
    /// between refreshes can re-plan without another network call.
    private(set) var lastPolicy: PunchReminderPolicy?

    private init() {}

    // MARK: - Reconcile (called after every successful shifts refresh)

    /// Replace every pending punch reminder with the plan for `inputs`. Note
    /// reminders and anything else pending are untouched.
    func sync(inputs: [PunchReminderInput], policy: PunchReminderPolicy?) {
        lastPolicy = policy
        let plan = PunchReminderPlanner.plan(inputs: inputs, policy: policy)
        center.getPendingNotificationRequests { [center] pending in
            let mine = pending.map(\.identifier).filter { $0.hasPrefix(PunchReminderPlanner.identifierPrefix) }
            if !mine.isEmpty { center.removePendingNotificationRequests(withIdentifiers: mine) }
            for item in plan {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireAt)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
            }
            DiagnosticLogger.shared.logOffline("Punch reminders reconciled: \(plan.count) pending (\(plan.filter { $0.kind == .clockIn }.count) clock-in, \(plan.filter { $0.kind == .clockOut }.count) clock-out); enabled=\(policy?.isEnabled ?? false)")
        }
    }

    // MARK: - Cancellation (the moment the punch is recorded)

    /// The staff member clocked in (live or queued offline) — the reminder is moot.
    func punchedIn(shiftId: Int) {
        center.removePendingNotificationRequests(withIdentifiers: [PunchReminderPlanner.clockInIdentifier(shiftId: shiftId)])
    }

    /// The staff member clocked out — drop the clock-out reminder under either key.
    func punchedOut(visitIds: [String], shiftId: Int?) {
        var ids = visitIds.filter { !$0.isEmpty }.map { PunchReminderPlanner.clockOutIdentifier(visitId: $0) }
        if let s = shiftId { ids.append(PunchReminderPlanner.clockOutIdentifier(shiftId: s)) }
        if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
    }

    /// Sign-out: nothing about a former session may buzz this phone.
    func cancelAll() {
        lastPolicy = nil
        center.getPendingNotificationRequests { [center] pending in
            let mine = pending.map(\.identifier).filter { $0.hasPrefix(PunchReminderPlanner.identifierPrefix) }
            if !mine.isEmpty { center.removePendingNotificationRequests(withIdentifiers: mine) }
        }
    }
}

extension PunchReminderInput {
    /// Adapter from the app model. Kept here (not in Models.swift) so the model
    /// file stays free of reminder concerns.
    init(visit v: Visit) {
        self.init(serverShiftId: v.serverShiftId,
                  serverVisitId: v.serverVisitId ?? v.serverVisitIds.first,
                  isScheduled: v.status == .scheduled,
                  isInProgress: v.status == .inProgress,
                  requiresClockIn: v.requiresClockIn,
                  isPendingApproval: v.isPendingApproval,
                  scheduledStart: v.scheduledStart,
                  scheduledEnd: v.scheduledEnd,
                  clientName: v.clients.first?.name ?? v.unlistedIndividualName ?? "your individual")
    }
}
