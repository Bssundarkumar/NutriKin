import XCTest
@testable import NutriKin

final class FoodGradeTests: XCTestCase {
    private func entry(calories: Double, sugarG: Double = 0, sodiumMg: Double = 0, satFatG: Double = 0,
                        fiberG: Double = 0, proteinG: Double = 0) -> FoodEntry {
        FoodEntry(memberId: UUID(), label: "x", calories: calories, sugarG: sugarG, sodiumMg: sodiumMg,
                  satFatG: satFatG, proteinG: proteinG, fiberG: fiberG)
    }

    func testWholeFoodHighInFibreAndProteinGradesWell() {
        // Grilled chicken breast with vegetables, roughly: lean protein, fibre, little sugar/sat fat.
        let e = entry(calories: 300, sugarG: 2, sodiumMg: 200, satFatG: 2, fiberG: 6, proteinG: 35)
        XCTAssertEqual(FoodGrade.grade(for: e), .a)
    }

    func testSugaryLowNutrientSnackGradesPoorly() {
        // A candy bar: dense in sugar and saturated fat, no fibre or protein to speak of.
        let e = entry(calories: 250, sugarG: 30, sodiumMg: 80, satFatG: 10, fiberG: 0, proteinG: 2)
        XCTAssertEqual(FoodGrade.grade(for: e), .e)
    }

    func testZeroCalorieEntryHasNoGrade() {
        XCTAssertNil(FoodGrade.grade(for: entry(calories: 0)))
        XCTAssertNil(FoodGrade.score(for: entry(calories: 0)))
    }

    func testAverageIgnoresUngradeableEntriesAndRoundsToALetter() {
        let good = entry(calories: 300, sugarG: 2, sodiumMg: 200, satFatG: 2, fiberG: 6, proteinG: 35) // ~A
        let water = entry(calories: 0)
        let result = FoodGrade.average([good, water])
        XCTAssertEqual(result?.grade, .a)
        XCTAssertEqual(result?.percent, Int(FoodGrade.score(for: good)!.rounded()))
    }

    func testAverageOfNothingGradeableIsNil() {
        XCTAssertNil(FoodGrade.average([entry(calories: 0), entry(calories: 0)]))
        XCTAssertNil(FoodGrade.average([]))
    }

    func testScoreNeverGoesNegativeEvenAtExtremeDensities() {
        // Each penalty is individually capped (40 + 30 + 20 = 90 at most), so the floor from these three
        // alone is 10, not 0 — this pins that floor rather than assuming the whole score bottoms out.
        let extreme = entry(calories: 50, sugarG: 100, sodiumMg: 5000, satFatG: 50)
        XCTAssertEqual(FoodGrade.score(for: extreme), 10)
        XCTAssertEqual(FoodGrade.grade(for: extreme), .e)
    }
}
