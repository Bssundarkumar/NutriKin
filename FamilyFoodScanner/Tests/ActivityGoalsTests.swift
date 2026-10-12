import XCTest
@testable import NutriKin

final class ActivityGoalsTests: XCTestCase {
    func testSuggestionsByAge() {
        XCTAssertEqual(ActivityGoals.suggested(for: Member(name: "K", conditions: [], age: 8)).weeklyMinutes, 420)
        XCTAssertEqual(ActivityGoals.suggested(for: Member(name: "A", conditions: [], age: 35)).steps, 8_000)
        XCTAssertEqual(ActivityGoals.suggested(for: Member(name: "G", conditions: [], age: 70)).steps, 6_000)
        XCTAssertEqual(ActivityGoals.suggested(for: Member(name: "C", conditions: [], isManagedByParent: true)).steps, 10_000)
    }
    func testWeekStartIsMonday() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let wed = cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 15))!
        let start = ActivityGoals.weekStart(wed, calendar: cal)
        XCTAssertEqual(cal.component(.weekday, from: start), 2)
        XCTAssertEqual(cal.component(.day, from: start), 21)
    }
    func testFractionAndMinutes() {
        XCTAssertEqual(ActivityGoals.fraction(done: 75, goal: 150), 0.5)
        XCTAssertEqual(ActivityGoals.fraction(done: 500, goal: 150), 1)
        XCTAssertNil(ActivityGoals.fraction(done: 5, goal: nil))
        let old = Workout(memberId: UUID(), doneAt: Date(timeIntervalSince1970: 0), kind: "walking", minutes: 60, caloriesBurned: 1)
        let now = Workout(memberId: UUID(), kind: "walking", minutes: 30, caloriesBurned: 1)
        XCTAssertEqual(ActivityGoals.weeklyMinutes([old, now], since: ActivityGoals.weekStart()), 30)
    }
    func testOldGoalsJSONStillDecodes() throws {
        let g = try JSONDecoder().decode(Goals.self, from: Data(#"{"dailyCalories":2000}"#.utf8))
        XCTAssertNil(g.dailySteps); XCTAssertNil(g.weeklyWorkoutMinutes)
    }
}
