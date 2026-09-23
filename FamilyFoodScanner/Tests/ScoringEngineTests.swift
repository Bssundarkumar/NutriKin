import XCTest
@testable import NutriKin

final class ScoringEngineTests: XCTestCase {
    private let engine = ScoringEngine()

    private let granolaBar = Product(
        barcode: "0000000000000",
        name: "Peanut Oat Granola Bar",
        brand: nil, imageURL: nil,
        ingredientsText: "rolled oats, peanuts, honey, brown rice syrup, palm oil, salt",
        allergenTags: ["en:peanuts"],
        nutrition: Nutrition(calories: 190, sugarG: 12, carbsG: 29, sodiumMg: 140,
                             satFatG: 2.5, transFatG: 0, proteinG: 5, basis: "per serving")
    )

    func testAllergyIsHardBlock() {
        let kid = Member(name: "Arjun", conditions: [.allergy(.peanuts)])
        let result = engine.score(granolaBar, for: kid)
        XCTAssertEqual(result.verdict, .avoid)
        XCTAssertEqual(result.score, 0)
        XCTAssertTrue(result.blockedByAllergy)
    }

    func testAllergyFallsBackToIngredientText() {
        var product = granolaBar
        product.allergenTags = []
        let kid = Member(name: "Arjun", conditions: [.allergy(.peanuts)])
        XCTAssertTrue(engine.score(product, for: kid).blockedByAllergy)
    }

    func testDiabetesGetsCaution() {
        let mom = Member(name: "Amma", conditions: [.diabetes], goals: Goals(dailySugarGrams: 25))
        XCTAssertEqual(engine.score(granolaBar, for: mom).verdict, .caution)
    }

    func testHealthyMemberIsOkay() {
        let priya = Member(name: "Priya", conditions: [], goals: Goals(dailyCalories: 1800))
        let result = engine.score(granolaBar, for: priya)
        XCTAssertEqual(result.verdict, .okay)
        XCTAssertFalse(result.reasons.isEmpty)
    }

    func testFamilySortedMostAtRiskFirst() {
        let members = [
            Member(name: "Priya", conditions: []),
            Member(name: "Arjun", conditions: [.allergy(.peanuts)]),
        ]
        let results = engine.scoreFamily(granolaBar, members: members)
        XCTAssertEqual(results.first?.member.name, "Arjun")
    }
}
