import UserNotifications
import XCTest
@testable import NutriKin

final class MedicationRemindersTests: XCTestCase {
    private let amma = UUID()
    private func med(_ name: String, dose: String? = "1 tablet", times: [String] = ["08:00"], days: [Int] = Array(1...7), active: Bool = true) -> Medication {
        Medication(memberId: amma, name: name, dose: dose, times: times, daysOfWeek: days, active: active)
    }

    func testEveryDayMedicationsNeedOneRepeatingReminderPerTime() {
        let plans = MedicationReminders.plans(for: [med("A", times: ["08:00", "20:00"])], memberName: { _ in "Amma" }, hideNames: true)
        XCTAssertEqual(plans.count, 2)
        XCTAssertTrue(plans.allSatisfy { $0.weekday == nil })
        XCTAssertEqual(plans.map(\.hour), [8, 20])
        XCTAssertTrue(plans.allSatisfy { $0.identifier.hasPrefix(MedicationReminders.idPrefix) })
        XCTAssertEqual(Set(plans.map(\.identifier)).count, 2)
    }

    func testSomeDaysGetOneReminderPerWeekdayInFoundationNumbering() {
        let plans = MedicationReminders.plans(for: [med("A", days: [1, 3, 7])], memberName: { _ in "Amma" }, hideNames: true)
        XCTAssertEqual(plans.compactMap(\.weekday).sorted(), [1, 2, 4])     // Sun = 1, Mon = 2, Wed = 4
    }

    func testPausedMedicationsAndBadTimesGetNoReminders() {
        let plans = MedicationReminders.plans(for: [med("Paused", active: false), med("Bad", times: ["nope"])], memberName: { _ in nil }, hideNames: true)
        XCTAssertTrue(plans.isEmpty)
    }

    func testLockScreenTextHidesTheMedicineNameByDefault() {
        let hidden = MedicationReminders.plans(for: [med("Sensitive drug", dose: "500 mg")], memberName: { _ in "Amma" }, hideNames: true)[0]
        XCTAssertFalse(hidden.title.contains("Sensitive")); XCTAssertFalse(hidden.body.contains("Sensitive")); XCTAssertFalse(hidden.body.contains("500"))
        XCTAssertTrue(hidden.body.contains("Amma"))
        let shown = MedicationReminders.plans(for: [med("Sensitive drug", dose: "500 mg")], memberName: { _ in "Amma" }, hideNames: false)[0]
        XCTAssertEqual(shown.title, "Time for Sensitive drug")
        XCTAssertEqual(shown.body, "Amma \u{00B7} 500 mg")
    }

    func testNeverMoreThanTheSystemLimit() {
        let many = (0..<40).map { med("Med \($0)", times: ["06:00", "12:00", "18:00"], days: [1, 2, 3]) }     // 360 possible reminders
        XCTAssertEqual(MedicationReminders.plans(for: many, memberName: { _ in nil }, hideNames: true).count, MedicationReminders.maxPending)
    }

    func testRequestsRepeatAtTheRightTimeAndCarryTheActionsCategory() throws {
        let plan = MedicationReminders.plans(for: [med("A", days: [2])], memberName: { _ in "Amma" }, hideNames: true)[0]
        let request = MedicationReminders.request(for: plan)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.hour, 8); XCTAssertEqual(trigger.dateComponents.minute, 0)
        XCTAssertEqual(trigger.dateComponents.weekday, 3)      // ISO Tuesday = Foundation 3
        XCTAssertEqual(request.content.categoryIdentifier, MedicationReminders.categoryID)
        XCTAssertEqual(request.content.userInfo["medicationID"] as? String, plan.medicationID.uuidString)
        XCTAssertEqual(request.content.userInfo["memberID"] as? String, amma.uuidString)
    }
}
