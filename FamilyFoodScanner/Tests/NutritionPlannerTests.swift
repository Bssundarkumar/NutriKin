import XCTest
@testable import NutriKin

final class NutritionPlannerTests: XCTestCase {
    private func plan(_ member: Member, _ activity: ActivityLevel = .sedentary) -> NutritionPlan? {
        if case .plan(let p) = NutritionPlanner.plan(for: member, activity: activity) { return p }
        return nil
    }

    func testOverweightManGetsAHalfKiloAWeekDeficit() throws {
        let man = Member(name: "Ravi", conditions: [], age: 30, heightCm: 180, weightKg: 90, sex: .male)
        let p = try XCTUnwrap(plan(man))
        XCTAssertEqual(p.bmi, 27.78, accuracy: 0.01)
        XCTAssertEqual(p.category, .overweight)
        XCTAssertEqual(p.bmr, 1880)                      // 10*90 + 6.25*180 - 5*30 + 5
        XCTAssertEqual(p.maintenanceKcal, 2256)          // x 1.2
        XCTAssertEqual(p.direction, .lose)
        XCTAssertEqual(p.targetKg, 71.28, accuracy: 0.01) // BMI 22 at 1.80 m
        XCTAssertEqual(p.dailyKcal, 1706)                // 550 kcal a day less
        XCTAssertEqual(p.weeklyChangeKg, -0.5, accuracy: 0.01)
        XCTAssertEqual(p.weeksToTarget, 38)
    }

    func testHealthyWeightMaintains() throws {
        let woman = Member(name: "Priya", conditions: [], age: 30, heightCm: 165, weightKg: 60, sex: .female)
        let p = try XCTUnwrap(plan(woman, .light))
        XCTAssertEqual(p.category, .healthy)
        XCTAssertEqual(p.direction, .maintain)
        XCTAssertEqual(p.targetKg, 60)
        XCTAssertEqual(p.dailyKcal, p.maintenanceKcal)
        XCTAssertNil(p.weeksToTarget)
        XCTAssertEqual(p.dailyKcal, 1815)
    }

    func testUnderweightGetsASurplus() throws {
        let man = Member(name: "Kiran", conditions: [], age: 25, heightCm: 180, weightKg: 55, sex: .male)
        let p = try XCTUnwrap(plan(man))
        XCTAssertEqual(p.category, .underweight)
        XCTAssertEqual(p.direction, .gain)
        XCTAssertEqual(p.dailyKcal, p.maintenanceKcal + 300)
        XCTAssertTrue(p.notes[0].contains("see a doctor"))
    }

    func testNeverPlansBelowTheSafeFloor() throws {
        let woman = Member(name: "Lakshmi", conditions: [], age: 70, heightCm: 150, weightKg: 70, sex: .female)
        let p = try XCTUnwrap(plan(woman))
        XCTAssertEqual(p.direction, .lose)
        XCTAssertGreaterThanOrEqual(p.dailyKcal, 1200)
        XCTAssertEqual(p.dailyKcal, 1200)
        XCTAssertTrue(p.notes.contains { $0.contains("lowest safe") })
    }

    func testMacrosAddBackUpToTheCalorieTarget() throws {
        let man = Member(name: "Ravi", conditions: [], age: 30, heightCm: 180, weightKg: 90, sex: .male)
        let p = try XCTUnwrap(plan(man))
        let kcal = p.proteinG * 4 + p.carbsG * 4 + p.fatG * 9
        XCTAssertEqual(Double(kcal), Double(p.dailyKcal), accuracy: 15)
        XCTAssertEqual(p.meals.map(\.kcal).reduce(0, +), p.dailyKcal, accuracy: 15)
    }

    func testConditionsAdjustLimits() throws {
        let dad = Member(name: "Dad", conditions: [.hypertension, .highCholesterol, .diabetes],
                         age: 50, heightCm: 175, weightKg: 85, sex: .male)
        let p = try XCTUnwrap(plan(dad))
        XCTAssertEqual(p.sodiumLimitMg, 1500)
        XCTAssertLessThan(Double(p.satFatLimitG), 0.08 * Double(p.dailyKcal) / 9 + 1)   // 7% of calories
        XCTAssertTrue(p.notes.contains { $0.contains("diabetes") })
        let well = Member(name: "Sam", conditions: [], age: 50, heightCm: 175, weightKg: 85, sex: .male)
        XCTAssertEqual(try XCTUnwrap(plan(well)).sodiumLimitMg, 2300)
    }

    func testChildrenAndMissingDetailsAreHandledSafely() {
        let child = Member(name: "Arjun", conditions: [], age: 8, heightCm: 130, weightKg: 26)
        if case .notForChildren = NutritionPlanner.plan(for: child, activity: .light) {} else { XCTFail("expected notForChildren") }
        let partial = Member(name: "Amma", conditions: [], age: 54)
        if case .needsInfo(let missing) = NutritionPlanner.plan(for: partial, activity: .light) {
            XCTAssertEqual(missing, ["height", "weight"])
        } else { XCTFail("expected needsInfo") }
        let typo = Member(name: "Oops", conditions: [], age: 30, heightCm: 5, weightKg: 70)
        if case .needsInfo = NutritionPlanner.plan(for: typo, activity: .light) {} else { XCTFail("expected needsInfo") }
    }

    func testHigherActivityMeansMoreCalories() throws {
        let m = Member(name: "Sam", conditions: [], age: 40, heightCm: 170, weightKg: 68, sex: .female)
        XCTAssertLessThan(try XCTUnwrap(plan(m, .sedentary)).maintenanceKcal, try XCTUnwrap(plan(m, .active)).maintenanceKcal)
    }
}
