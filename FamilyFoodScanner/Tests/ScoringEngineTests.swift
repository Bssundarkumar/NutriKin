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

    // A real report: scanning a beer scored "good" for everyone, including children - low calories,
    // sugar and sodium looked "fine" by the numbers, because nothing checked for alcohol at all.
    private let beer = Product(
        barcode: "0000000000001",
        name: "Lager Beer",
        brand: nil, imageURL: nil,
        ingredientsText: "water, malted barley, hops, yeast",
        allergenTags: [],
        nutrition: Nutrition(calories: 150, sugarG: 0, carbsG: 11, sodiumMg: 10,
                             satFatG: 0, transFatG: 0, proteinG: 1.6, basis: "per serving")
    )

    func testAlcoholIsHardBlockedForChildren() {
        let kid = Member(name: "Arjun", conditions: [], age: 10)
        let result = engine.score(beer, for: kid)
        XCTAssertEqual(result.verdict, .avoid)
        XCTAssertEqual(result.score, 0)
    }

    func testAlcoholIsHardBlockedForAParentManagedMemberWithNoAgeEntered() {
        let kid = Member(name: "Arjun", conditions: [], isManagedByParent: true)
        XCTAssertEqual(engine.score(beer, for: kid).verdict, .avoid)
    }

    func testAlcoholIsNeverScoredOkayForAnAdultEither() {
        let adult = Member(name: "Amma", conditions: [], age: 40)
        let result = engine.score(beer, for: adult)
        XCTAssertNotEqual(result.verdict, .okay)
        XCTAssertTrue(result.reasons.contains { $0.localizedCaseInsensitiveContains("alcohol") })
    }

    func testAlcoholDetectedByCategoryTagEvenWithoutTheWordInTheNameOrIngredients() {
        var product = beer
        product.name = "Golden Brew"
        product.ingredientsText = "water, grain, hops, yeast"
        product.categoryTags = ["en:beers"]
        let adult = Member(name: "Amma", conditions: [], age: 40)
        XCTAssertNotEqual(engine.score(product, for: adult).verdict, .okay)
    }
}
