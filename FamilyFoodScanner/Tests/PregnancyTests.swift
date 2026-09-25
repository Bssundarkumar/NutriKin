import XCTest
@testable import NutriKin

final class PregnancyTests: XCTestCase {
    private let mum = Member(name: "Priya", conditions: [.pregnancy], age: 30, heightCm: 165, weightKg: 62, sex: .female)
    private let other = Member(name: "Dad", conditions: [.diabetes], age: 34, sex: .male)

    private func product(_ name: String, ingredients: String?, tags: [String] = [], categories: [String] = []) -> Product {
        var p = Product(barcode: "12345678", name: name, brand: nil, imageURL: nil, ingredientsText: ingredients, allergenTags: [],
                        nutrition: Nutrition(calories: 100, sugarG: 2, carbsG: 15, sodiumMg: 100, satFatG: 1, transFatG: 0, proteinG: 3, basis: "per 100 g"))
        p.ingredientTags = tags; p.categoryTags = categories
        return p
    }

    // MARK: stored so older versions still work

    func testPregnancyIsStoredAsATypedConditionThatOlderVersionsCanRead() throws {
        let data = try JSONEncoder().encode(mum.conditions)
        XCTAssertEqual(try JSONDecoder().decode([Condition].self, from: data), [.custom("Pregnancy")])
        XCTAssertTrue(mum.isPregnant); XCTAssertTrue(mum.has(.pregnancy))
        XCTAssertFalse(other.isPregnant); XCTAssertFalse(other.has(.pregnancy))
        XCTAssertTrue(Member(name: "X", conditions: [.custom("pregnant (2nd trimester)")]).isPregnant)
        XCTAssertEqual(mum.conditions.map(\.displayName), ["Pregnancy"])
    }

    func testPregnancyDoesNotShowUpAsAFreeTextCondition() {
        let m = Member(name: "Z", conditions: [.pregnancy, .custom("Celiac disease")])
        XCTAssertEqual(m.customConditionNames, ["Celiac disease"])
    }

    // MARK: scoring

    func testAlcoholIsAnAvoidForAPregnantPersonButNotForOthers() {
        let beer = product("Craft beer", ingredients: "water, barley malt, hops, alcohol")
        let result = ScoringEngine().score(beer, for: mum)
        XCTAssertLessThanOrEqual(result.score, 20)
        XCTAssertEqual(result.verdict, .avoid)
        XCTAssertTrue(result.reasons[0].contains("alcohol"))
        XCTAssertFalse(result.blockedByAllergy)
        XCTAssertGreaterThan(ScoringEngine().score(beer, for: other).score, 60)
    }

    func testRiskyFoodsAreCappedBySeverity() {
        let engine = ScoringEngine()
        XCTAssertEqual(engine.score(product("Salmon sushi", ingredients: "rice, raw fish"), for: mum).verdict, .avoid)
        XCTAssertEqual(engine.score(product("Soft cheese", ingredients: "unpasteurised milk, salt"), for: mum).verdict, .avoid)
        XCTAssertEqual(engine.score(product("Chicken liver pate", ingredients: "chicken liver, butter"), for: mum).verdict, .caution)
        XCTAssertLessThan(engine.score(product("Swordfish steak", ingredients: "swordfish"), for: mum).score, 56)
        XCTAssertLessThan(engine.score(product("Cold coffee", ingredients: "milk, coffee, sugar"), for: mum).score, 66)
        XCTAssertGreaterThan(engine.score(product("Plain rice", ingredients: "rice"), for: mum).score, 80)
    }

    func testProductsWithNoIngredientListCannotLookSafeInPregnancy() {
        let unknown = product("Mystery snack", ingredients: nil)
        let result = ScoringEngine().score(unknown, for: mum)
        XCTAssertLessThan(result.score, 70)
        XCTAssertEqual(result.verdict, .caution)
        XCTAssertGreaterThanOrEqual(ScoringEngine().score(unknown, for: other).score, 70)
    }

    func testMatchingLooksAtWholeWordsSoNothingFiresByAccident() {
        XCTAssertTrue(PregnancyGuidance.matches(text: "chicken liver").contains { $0.id == "preg-liver" })
        XCTAssertTrue(PregnancyGuidance.matches(text: "delivery pack, silver foil, brumby").isEmpty)
        XCTAssertTrue(PregnancyGuidance.matches(text: "Product name: wine vinegar").isEmpty)           // trace alcohol only
    }

    func testTagsAndCategoriesAreSearchedToo() {
        let p = product("Bottle", ingredients: "grapes", categories: ["en:alcoholic-beverages", "en:beers"])
        XCTAssertTrue(PregnancyGuidance.matches(in: p).contains { $0.id == "preg-alcohol" })
        XCTAssertLessThanOrEqual(ScoringEngine().score(p, for: mum).score, 20)
        XCTAssertTrue(PregnancyGuidance.matches(in: product("Cola", ingredients: "water, sugar, caffeine")).contains { $0.id == "preg-caffeine" })
    }

    // MARK: alerts, plans, meals

    func testIngredientAlertsAppearOnlyWhenSomeoneIsPregnant() {
        let beer = product("Beer", ingredients: "water, alcohol")
        let alerts = IngredientAnalyzer().alerts(for: beer, members: [mum, other])
        XCTAssertTrue(alerts.contains { $0.flag.id == "preg-alcohol" && $0.members == ["Priya"] })
        XCTAssertFalse(IngredientAnalyzer().alerts(for: beer, members: [other]).contains { $0.flag.id == "preg-alcohol" })
    }

    func testNoCalorieOrWeightPlanIsSuggestedDuringPregnancy() {
        if case .notDuringPregnancy = NutritionPlanner.plan(for: mum, activity: .light) {} else { XCTFail("expected no plan") }
    }

    func testNoWalkItOffIdeaForAPregnantPerson() {
        XCTAssertFalse(BurnItOff.isSuitable(mum))
    }

    func testMealPlansForAPregnantPersonDropRiskyDishesAndTheAIIsToldWhy() throws {
        let reply = #"{"meals":[{"name":"Dinner","dishes":[{"name":"Salmon sushi","kcal":300,"ingredients":["raw fish","rice"],"why":"x"},{"name":"Dal and rice","kcal":450,"ingredients":["lentils","rice"],"why":"Protein"}]}]}"#
        let ideas = try MealIdeasParser.parse(reply, for: mum)
        XCTAssertEqual(ideas.slots.flatMap(\.dishes).map(\.name), ["Dal and rice"])
        XCTAssertEqual(ideas.removedForAllergy, 1)
        XCTAssertEqual(try MealIdeasParser.parse(reply, for: other).slots.flatMap(\.dishes).count, 2)      // not pregnant: nothing removed
        let prompt = MealIdeasService.systemPrompt(member: mum, plan: nil, targetKcal: 2000, preferences: "")
        XCTAssertTrue(prompt.contains("pregnant")); XCTAssertTrue(prompt.contains("unpasteurised"))
        XCTAssertFalse(MealIdeasService.systemPrompt(member: other, plan: nil, targetKcal: 2000, preferences: "").contains("pregnant"))
    }

    func testPregnancyEmergenciesGetTheEmergencyReply() {
        for text in ["I have heavy bleeding", "my baby isn't moving today", "my waters have broken"] {
            if case .notice(let kind, _) = AIGuardrails.screen(text) { XCTAssertEqual(kind, .emergency, text) } else { XCTFail(text) }
        }
    }
}
