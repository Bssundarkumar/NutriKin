import Foundation
import UserNotifications

/// Local reminder notifications for medications, with Taken and Skip buttons. They fire on this iPhone only,
/// so they work without a connection, and they can fail (silent mode, notifications off, a flat battery).
/// The app says so, and treats them as a memory aid, never as a safety system.
enum MedicationReminders {
    static let categoryID = "NUTRIKIN_MEDICATION"
    static let takenAction = "NUTRIKIN_DOSE_TAKEN"
    static let skipAction = "NUTRIKIN_DOSE_SKIP"
    static let idPrefix = "med-"
    /// iOS keeps at most 64 pending local notifications for an app.
    static let maxPending = 60

    /// One reminder to schedule. Plain data, so what gets scheduled can be tested.
    struct Plan: Equatable {
        var identifier: String
        var hour: Int
        var minute: Int
        /// Foundation weekday (Sunday = 1), or nil for every day.
        var weekday: Int?
        var title: String
        var body: String
        var medicationID: UUID
        var memberID: UUID
    }

    static func plans(for medications: [Medication], memberName: (UUID) -> String?, hideNames: Bool) -> [Plan] {
        var out: [Plan] = []
        for med in medications where med.active {
            let who = memberName(med.memberId) ?? "your family"
            let title = hideNames ? "Medication reminder" : "Time for \(med.name)"
            let body = hideNames ? "It's time for \(who)'s medication." : [who, med.dose].compactMap { $0 }.joined(separator: " \u{00B7} ")
            for time in MedicationSchedule.normalized(med.times) {
                guard let t = MedicationSchedule.parseTime(time) else { continue }
                let stamp = MedicationSchedule.format(hour: t.hour, minute: t.minute).replacingOccurrences(of: ":", with: "")
                // Every day needs just one repeating reminder, which keeps well inside iOS's limit.
                let weekdays: [Int?] = med.isEveryDay ? [nil] : med.daysOfWeek.sorted().map { MedicationSchedule.calendarWeekday(fromISO: $0) }
                for weekday in weekdays {
                    out.append(Plan(identifier: "\(idPrefix)\(med.id.uuidString)-\(stamp)-\(weekday.map(String.init) ?? "all")",
                                    hour: t.hour, minute: t.minute, weekday: weekday, title: title, body: body,
                                    medicationID: med.id, memberID: med.memberId))
                }
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
        content.threadIdentifier = "medication-\(plan.memberID.uuidString)"
        content.userInfo = ["medicationID": plan.medicationID.uuidString, "memberID": plan.memberID.uuidString]
        var parts = DateComponents(hour: plan.hour, minute: plan.minute)
        parts.weekday = plan.weekday
        return UNNotificationRequest(identifier: plan.identifier, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true))
    }

    static func registerCategories() {
        let taken = UNNotificationAction(identifier: takenAction, title: "Taken", options: [.foreground])
        let skip = UNNotificationAction(identifier: skipAction, title: "Skip", options: [.foreground])
        let category = UNNotificationCategory(identifier: categoryID, actions: [taken, skip], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category, ActivityReminders.category])
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks the person for permission (only the first time does iOS show the question).
    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces this app's medication reminders with exactly these.
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
        center.removeAllDeliveredNotifications()
    }
}

/// A Taken or Skip tap on a reminder, waiting for the app to record it.
struct DoseAction: Equatable {
    var medicationID: UUID
    var memberID: UUID
    var dueAt: Date
    var status: DoseStatus
}

extension Notification.Name {
    static let nutrikinDoseAction = Notification.Name("nutrikin.doseAction")
}

/// Receives notification taps. Reminders repeat, so the due time is taken from when the notification was delivered.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    /// Taps that arrived before the app finished starting up.
    nonisolated(unsafe) static var pending: [DoseAction] = []
    nonisolated(unsafe) static var pendingActivity: [ActivityAction] = []

    static func activityAction(from response: UNNotificationResponse) -> ActivityAction? {
        guard response.actionIdentifier == ActivityReminders.wentAction else { return nil }
        let info = response.notification.request.content.userInfo
        guard let member = (info["memberID"] as? String).flatMap(UUID.init(uuidString:)), let kind = info["kind"] as? String else { return nil }
        return ActivityAction(memberID: member, kind: kind, minutes: (info["minutes"] as? Int) ?? 60, at: response.notification.date)
    }

    static func action(from response: UNNotificationResponse) -> DoseAction? {
        let status: DoseStatus
        switch response.actionIdentifier {
        case MedicationReminders.takenAction: status = .taken
        case MedicationReminders.skipAction: status = .skipped
        default: return nil
        }
        let info = response.notification.request.content.userInfo
        guard let med = (info["medicationID"] as? String).flatMap(UUID.init(uuidString:)),
              let member = (info["memberID"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
        let delivered = response.notification.date
        let due = Date(timeIntervalSince1970: (delivered.timeIntervalSince1970 / 60).rounded(.down) * 60)
        return DoseAction(medicationID: med, memberID: member, dueAt: due, status: status)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let went = Self.activityAction(from: response) {
            Self.pendingActivity.append(went)
            NotificationCenter.default.post(name: .nutrikinActivityAction, object: nil)
            return
        }
        guard let action = Self.action(from: response) else { return }
        Self.pending.append(action)
        NotificationCenter.default.post(name: .nutrikinDoseAction, object: nil)
    }
}
