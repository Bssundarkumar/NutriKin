import XCTest
import UserNotifications
@testable import NutriKin

final class ScheduleTests: XCTestCase {
    private let member = UUID()
    private func sched(days: [Int], time: String = "17:00", remind: Bool = true, active: Bool = true, kind: WorkoutKind = .swimming) -> ActivitySchedule {
        ActivitySchedule(memberId: member, kind: kind.rawValue, minutes: 45, time: time, daysOfWeek: days, remind: remind, active: active)
    }
    func testOccursOnTheRightWeekday() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let tuesday = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 12))!
        XCTAssertTrue(ScheduleMath.occurs(sched(days: [2, 4]), on: tuesday, calendar: cal))
        XCTAssertFalse(ScheduleMath.occurs(sched(days: [3]), on: tuesday, calendar: cal))
        XCTAssertFalse(ScheduleMath.occurs(sched(days: [2], active: false), on: tuesday, calendar: cal))
    }
    func testLoggedOnlyWhenSameKindThatDay() {
        let s = sched(days: [1])
        let swim = Workout(memberId: member, kind: WorkoutKind.swimming.rawValue, minutes: 30, caloriesBurned: 0)
        let walk = Workout(memberId: member, kind: WorkoutKind.walking.rawValue, minutes: 30, caloriesBurned: 0)
        XCTAssertTrue(ScheduleMath.isLogged(s, workouts: [swim], on: Date()))
        XCTAssertFalse(ScheduleMath.isLogged(s, workouts: [walk], on: Date()))
    }
    func testTextHelpers() {
        XCTAssertEqual(ScheduleMath.daysText([2, 4]), "Tue, Thu")
        XCTAssertEqual(ScheduleMath.daysText([1, 2, 3, 4, 5]), "Weekdays")
        XCTAssertEqual(ScheduleMath.daysText(Array(1...7)), "Every day")
    }
    func testReminderPlansOnePerDayAndSkipsOffOrPaused() {
        let plans = ActivityReminders.plans(for: [sched(days: [2, 4]), sched(days: [1], remind: false), sched(days: [1], active: false)]) { _ in "Arjun" }
        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(Set(plans.map(\.weekday)), [3, 5])   // Tue = 3, Thu = 5 in Foundation's Sunday-first numbering
        XCTAssertEqual(plans.first?.hour, 17)
        XCTAssertTrue(plans[0].identifier.hasPrefix(ActivityReminders.idPrefix))
        XCTAssertTrue(plans[0].body.contains("Arjun"))
    }
    func testRemindersNeverCollideWithMedicineReminderIDs() {
        XCTAssertNotEqual(ActivityReminders.idPrefix, MedicationReminders.idPrefix)
        XCTAssertFalse(ActivityReminders.idPrefix.hasPrefix(MedicationReminders.idPrefix))
    }
    func testDecodesFromSnakeCaseRow() throws {
        let json = #"{"id":"\#(UUID().uuidString)","member_id":"\#(UUID().uuidString)","kind":"swimming","minutes":45,"time":"17:00","days_of_week":[2,4],"remind":true,"active":true}"#
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let s = try dec.decode(ActivitySchedule.self, from: Data(json.utf8))
        XCTAssertEqual(s.daysOfWeek, [2, 4]); XCTAssertEqual(s.title, "Swimming")
    }
}
