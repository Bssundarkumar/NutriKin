import Foundation
import UserNotifications

/// Local reminders for scheduled activities, with a "Went" button that logs the activity. Like the medicine reminders,
/// they fire on this iPhone only and are a memory aid.
enum ActivityReminders {
    static let categoryID = "NUTRIKIN_ACTIVITY"
    static let wentAction = "NUTRIKIN_ACTIVITY_WENT"
    static let idPrefix = "act-"
    static let maxPending = 40

    struct Plan: Equatable {
        var identifier: String
        var hour: Int
        var minute: Int
        /// Foundation weekday (Sunday = 1).
        var weekday: Int
        var title: String
        var body: String
        var scheduleID: UUID
        var memberID: UUID
        var kind: String
        var minutes: Int
    }

    static func plans(for schedules: [ActivitySchedule], memberName: (UUID) -> String?) -> [Plan] {
        var out: [Plan] = []
        for s in schedules where s.active && s.remind {
            guard let t = MedicationSchedule.parseTime(s.time) else { continue }
            let who = memberName(s.memberId) ?? "your family"
            for iso in Set(s.daysOfWeek.filter { (1...7).contains($0) }).sorted() {
                let weekday = MedicationSchedule.calendarWeekday(fromISO: iso)
                out.append(Plan(identifier: "\(idPrefix)\(s.id.uuidString)-\(weekday)", hour: t.hour, minute: t.minute, weekday: weekday,
                                title: "\(s.title) time", body: "\(who) \u{00B7} \(s.minutes) min", scheduleID: s.id, memberID: s.memberId,
                                kind: s.kind, minutes: s.minutes))
            }
        }
        return Array(out.prefix(maxPending))
    }

    static func request(for plan: Plan) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.threadIdentifier = "activity-\(plan.memberID.uuidString)"
        content.userInfo = ["scheduleID": plan.scheduleID.uuidString, "memberID": plan.memberID.uuidString,
                            "kind": plan.kind, "minutes": plan.minutes]
        return UNNotificationRequest(identifier: plan.identifier, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: plan.hour, minute: plan.minute, weekday: plan.weekday), repeats: true))
    }

    static var category: UNNotificationCategory {
        UNNotificationCategory(identifier: categoryID, actions: [UNNotificationAction(identifier: wentAction, title: "Went", options: [.foreground])],
                               intentIdentifiers: [], options: [])
    }

    static func reschedule(_ plans: [Plan]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for plan in plans { try? await center.add(request(for: plan)) }
    }

    static func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
    }
}

/// A "Went" tap on an activity reminder, waiting for the app to log it.
struct ActivityAction: Equatable {
    var memberID: UUID
    var kind: String
    var minutes: Int
    var at: Date
}

extension Notification.Name {
    static let nutrikinActivityAction = Notification.Name("nutrikin.activityAction")
}
