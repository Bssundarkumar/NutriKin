import XCTest
@testable import NutriKin

final class DayCoachTests: XCTestCase {
    func testDayPromptIsTaggedDataWithNumbers() {
        let m = Member(name: "Amma", conditions: [.diabetes], age: 54)
        let budget = DayBudget(member: m, entries: [], workouts: [])
        let p = DayCoach.dayPrompt(member: m, budget: budget, steps: 4200, weekMinutes: 60)
        XCTAssertTrue(p.contains("<family_data>")); XCTAssertTrue(p.contains("<day_data>")); XCTAssertTrue(p.contains("Steps today: 4200"))
    }
    func testWorkoutPromptIncludesGoal() {
        var m = Member(name: "Sam", conditions: []); m.goals.weeklyWorkoutMinutes = 150
        XCTAssertTrue(DayCoach.workoutPrompt(member: m, weekMinutes: 30, steps: nil).contains("Weekly workout goal: 150"))
    }
    func testRulesStaySafe() {
        for r in [DayCoach.tipRules, DayCoach.workoutIdeaRules] {
            XCTAssertTrue(r.contains("no medical advice") || r.contains("No medical advice"))
            XCTAssertTrue(r.contains("weight"))
        }
    }
}
