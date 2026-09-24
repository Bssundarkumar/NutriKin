import XCTest
@testable import NutriKin

final class MissingDataTests: XCTestCase {
    private let engine = ScoringEngine()
    private let nut = Nutrition(calories: 100, sugarG: 2, carbsG: 15, sodiumMg: 50, satFatG: 1,
                                transFatG: 0, proteinG: 3, basis: "per 100 g")

    private func product(ingredients: String?, tags: [String] = [], allergenTags: [String] = [],
                         traces: [String] = [], nutrition: Nutrition? = nil) -> Product {
        var p = Product(barcode: "12345678", name: "P", brand: nil, imageURL: nil, ingredientsText: ingredients,
                        allergenTags: allergenTags, nutrition: nutrition ?? nut)
        p.ingredientTags = tags
        p.tracesTags = traces
        return p
    }

    func testUnknownIngredientsCanNeverBeOkayForAnAllergicMember() {
        let kid = Member(name: "Arjun", conditions: [.allergy(.peanuts)])
        let result = engine.score(product(ingredients: nil), for: kid)
        XCTAssertEqual(result.verdict, .caution)
        XCTAssertFalse(result.blockedByAllergy)                 // not a false hard block
        XCTAssertTrue(result.reasons[0].contains("can't be ruled out"))
    }

    func testUnknownIngredientsDoNotAffectPeopleWithoutAllergies() {
        let mom = Member(name: "Priya", conditions: [])
        XCTAssertEqual(engine.score(product(ingredients: nil), for: mom).verdict, .okay)
    }

    func testKnownIngredientsStillScoreNormallyForAllergicMember() {
        let kid = Member(name: "Arjun", conditions: [.allergy(.peanuts)])
        XCTAssertEqual(engine.score(product(ingredients: "oats, water"), for: kid).verdict, .okay)
    }

    func testTracesOfTheMembersAllergenGiveACautionNotABlock() {
        let kid = Member(name: "Arjun", conditions: [.allergy(.peanuts)])
        let result = engine.score(product(ingredients: "oats", traces: ["en:peanuts"]), for: kid)
        XCTAssertEqual(result.verdict, .caution)
        XCTAssertFalse(result.blockedByAllergy)
        XCTAssertTrue(result.reasons[0].contains("traces of peanuts"))
        let other = Member(name: "Dad", conditions: [.allergy(.fish)])
        XCTAssertEqual(engine.score(product(ingredients: "oats", traces: ["en:peanuts"]), for: other).verdict, .okay)
    }

    func testMissingKeyFigureStopsAnOkayForThatCondition() {
        let diabetic = Member(name: "Amma", conditions: [.diabetes])
        var n = nut; n.sugarG = nil
        let result = engine.score(product(ingredients: "oats", nutrition: n), for: diabetic)
        XCTAssertLessThan(result.score, 70)
        XCTAssertEqual(result.verdict, .caution)
        XCTAssertTrue(result.reasons[0].contains("No sugar"))
    }

    func testDataWarningsDescribeTheGaps() {
        var empty = Nutrition(calories: nil, sugarG: nil, carbsG: nil, sodiumMg: nil, satFatG: nil,
                              transFatG: nil, proteinG: nil, basis: "per 100 g")
        empty.basis = "per 100 g"
        XCTAssertEqual(product(ingredients: nil, nutrition: empty).dataWarnings.count, 2)
        XCTAssertTrue(product(ingredients: "oats").dataWarnings.isEmpty)
        XCTAssertTrue(product(ingredients: nil, tags: ["en:oat"]).hasIngredientInfo)
    }
}
