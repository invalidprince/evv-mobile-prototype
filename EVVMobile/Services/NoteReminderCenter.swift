import Foundation
import UserNotifications

/// Schedules local push reminders for incomplete visit notes.
///
/// Business rule: a visit note is due the same agency-local day as the visit
/// (day boundary = midnight). Two reminders per incomplete note:
///   1. "Nearing end of day" nudge at 7:00 PM on the service day.
///   2. "Now late" alert at midnight, when the note crosses the day boundary.
/// Both are cancelled the moment the note is completed.
final class NoteReminderCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NoteReminderCenter()

    private let center = UNUserNotificationCenter.current()

    /// Hour of the "nearing end of day" nudge (7:00 PM).
    private let endOfDayReminderHour = 19

    private override init() {
        super.init()
    }

    /// Call once at app start: become delegate (so banners show in the
    /// foreground) and request permission.
    func activate() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - Scheduling

    /// Schedule the end-of-day nudge and the midnight "late" alert for an
    /// incomplete note. Triggers already in the past are skipped.
    func scheduleReminders(for visit: Visit) {
        cancelReminders(for: visit.id)
        let clientName = visit.client.name
        let cal = Calendar.current
        let now = Date()

        // 1. Nearing-end-of-day nudge (default 7:00 PM on the service day).
        if let nudgeTime = cal.date(bySettingHour: endOfDayReminderHour, minute: 0, second: 0, of: visit.serviceDay),
           nudgeTime > now {
            let content = UNMutableNotificationContent()
            content.title = "Visit note still open"
            content.body = "Your note for \(clientName) is due by midnight tonight. Finish it before the end of the day."
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: nudgeTime)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: Self.endOfDayIdentifier(for: visit.id),
                                             content: content, trigger: trigger))
        }

        // 2. Late alert at midnight (start of the day after the service day).
        if visit.noteDeadline > now {
            let content = UNMutableNotificationContent()
            content.title = "Note is now late"
            content.body = "Your note for \(clientName) is now late. Complete it as soon as possible — your supervisor can see late documentation."
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: visit.noteDeadline)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: Self.lateIdentifier(for: visit.id),
                                             content: content, trigger: trigger))
        }
    }

    /// Cancel all scheduled reminders for a visit (call when the note is completed).
    func cancelReminders(for visitId: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [
            Self.endOfDayIdentifier(for: visitId),
            Self.lateIdentifier(for: visitId)
        ])
    }

    // MARK: - Demo

    /// Demo affordance: fires a note reminder a few seconds from now so the
    /// notification can be shown instantly in the simulator.
    func sendTestReminder(clientName: String, late: Bool) {
        let content = UNMutableNotificationContent()
        if late {
            content.title = "Note is now late"
            content.body = "Your note for \(clientName) is now late. Complete it as soon as possible — your supervisor can see late documentation."
        } else {
            content.title = "Visit note still open"
            content.body = "Your note for \(clientName) is due by midnight tonight. Finish it before the end of the day."
        }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        center.add(UNNotificationRequest(identifier: "note-demo-\(UUID().uuidString)",
                                         content: content, trigger: trigger))
    }

    // MARK: - Identifiers

    private static func endOfDayIdentifier(for visitId: UUID) -> String { "note-eod-\(visitId.uuidString)" }
    private static func lateIdentifier(for visitId: UUID) -> String { "note-late-\(visitId.uuidString)" }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners even while the app is in the foreground (demo-friendly).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
