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

    // MARK: Honey (infant botulism)

    private let honeyProduct = Product(
        barcode: "0000000000002", name: "Wildflower Honey",
        brand: nil, imageURL: nil, ingredientsText: "100% honey", allergenTags: [],
        nutrition: Nutrition(calories: 60, sugarG: 17, carbsG: 17, sodiumMg: 0, satFatG: 0, transFatG: 0, proteinG: 0, basis: "per serving")
    )

    func testHoneyIsHardBlockedUnderAgeOne() {
        let baby = Member(name: "Baby", conditions: [], age: 0)
        let result = engine.score(honeyProduct, for: baby)
        XCTAssertEqual(result.verdict, .avoid)
        XCTAssertEqual(result.score, 0)
        XCTAssertTrue(result.reasons[0].localizedCaseInsensitiveContains("honey"))
    }

    func testHoneyIsFineForAnOlderChildAndAnAdult() {
        let toddler = Member(name: "Arjun", conditions: [], age: 3)
        XCTAssertEqual(engine.score(honeyProduct, for: toddler).verdict, .okay)
        let adult = Member(name: "Amma", conditions: [], age: 40)
        XCTAssertEqual(engine.score(honeyProduct, for: adult).verdict, .okay)
    }

    // MARK: Caffeine and mercury fish for children (not just pregnancy)

    private let energyDrink = Product(
        barcode: "0000000000003", name: "Energy Drink",
        brand: nil, imageURL: nil, ingredientsText: "carbonated water, sugar, caffeine, taurine", allergenTags: [],
        nutrition: Nutrition(calories: 110, sugarG: 27, carbsG: 28, sodiumMg: 100, satFatG: 0, transFatG: 0, proteinG: 0, basis: "per can")
    )

    func testCaffeineIsCappedForAChildNotJustInPregnancy() {
        let kid = Member(name: "Arjun", conditions: [], age: 10)
        let result = engine.score(energyDrink, for: kid)
        XCTAssertNotEqual(result.verdict, .okay)
        XCTAssertTrue(result.reasons.contains { $0.localizedCaseInsensitiveContains("caffeine") })
    }

    func testCaffeineIsUnaffectedForAnAdultWithNoOtherConditions() {
        let adult = Member(name: "Amma", conditions: [], age: 40)
        XCTAssertEqual(engine.score(energyDrink, for: adult).verdict, .okay)
    }

    private let swordfish = Product(
        barcode: "0000000000004", name: "Swordfish Steak",
        brand: nil, imageURL: nil, ingredientsText: "swordfish", allergenTags: [],
        nutrition: Nutrition(calories: 150, sugarG: 0, carbsG: 0, sodiumMg: 90, satFatG: 1, transFatG: 0, proteinG: 20, basis: "per serving")
    )

    func testHighMercuryFishIsCappedForAChild() {
        let kid = Member(name: "Arjun", conditions: [], age: 8)
        XCTAssertNotEqual(engine.score(swordfish, for: kid).verdict, .okay)
    }

    // MARK: Choking hazards (young children only)

    private let wholeGrapes = Product(
        barcode: "0000000000005", name: "Whole Grapes",
        brand: nil, imageURL: nil, ingredientsText: "grapes", allergenTags: [],
        nutrition: Nutrition(calories: 60, sugarG: 15, carbsG: 16, sodiumMg: 0, satFatG: 0, transFatG: 0, proteinG: 0, basis: "per serving")
    )

    func testChokingHazardIsCappedForAToddler() {
        let toddler = Member(name: "Baby", conditions: [], age: 2)
        XCTAssertNotEqual(engine.score(wholeGrapes, for: toddler).verdict, .okay)
    }

    func testChokingHazardDoesNotApplyToAnOlderChild() {
        let olderKid = Member(name: "Arjun", conditions: [], age: 10)
        XCTAssertEqual(engine.score(wholeGrapes, for: olderKid).verdict, .okay)
    }

    // MARK: Supplements for children

    private let ironSupplement: Product = {
        var p = Product(
            barcode: "0000000000006", name: "Iron Supplement Tablets",
            brand: nil, imageURL: nil, ingredientsText: "ferrous sulfate (iron), gelatin capsule", allergenTags: [],
            nutrition: Nutrition(calories: 5, sugarG: 0, carbsG: 1, sodiumMg: 0, satFatG: 0, transFatG: 0, proteinG: 0, basis: "per tablet")
        )
        p.categoryTags = ["en:dietary-supplements"]
        return p
    }()

    func testIronSupplementIsCappedForAChild() {
        let kid = Member(name: "Arjun", conditions: [], age: 8)
        let result = engine.score(ironSupplement, for: kid)
        XCTAssertNotEqual(result.verdict, .okay)
        XCTAssertTrue(result.reasons.contains { $0.localizedCaseInsensitiveContains("iron") })
    }

    func testSupplementIsUnaffectedForAnAdult() {
        let adult = Member(name: "Amma", conditions: [], age: 40)
        XCTAssertEqual(engine.score(ironSupplement, for: adult).verdict, .okay)
    }
}
