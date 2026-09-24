import XCTest
@testable import NutriKin

final class AIContextTests: XCTestCase {
    private let amma = Member(name: "Amma", conditions: [.diabetes, .allergy(.peanuts), .customAllergy("mango")],
                              goals: Goals(dailySugarGrams: 25), age: 54, heightCm: 158, weightKg: 72, sex: .female)

    func testFamilySummaryIncludesConditionsAllergiesAndGoals() {
        let text = AIContext.family([amma, Member(name: "Sam", conditions: [])])
        XCTAssertTrue(text.contains("Amma"))
        XCTAssertTrue(text.contains("54 years old"))
        XCTAssertTrue(text.contains("BMI 28.8"))
        XCTAssertTrue(text.contains("ALLERGIES: Peanuts, mango") || text.lowercased().contains("allergies: peanut"))
        XCTAssertTrue(text.lowercased().contains("diabetes"))
        XCTAssertTrue(text.contains("sugar under 25 g"))
        XCTAssertTrue(text.contains("- Sam"))
    }

    func testProductSummaryCarriesFactsScoresAndGaps() {
        var p = Product(barcode: "1", name: "Choc Spread", brand: "Acme", imageURL: nil,
                        ingredientsText: "sugar, palm oil, hazelnuts", allergenTags: ["en:nuts"],
                        nutrition: Nutrition(calories: 539, sugarG: 56.3, carbsG: nil, sodiumMg: 40, satFatG: 10.6,
                                             transFatG: nil, proteinG: nil, basis: "per 100 g"))
        p.nutriScore = "e"; p.novaGroup = 4
        let text = AIContext.product(p, members: [amma])
        XCTAssertTrue(text.contains("Choc Spread by Acme"))
        XCTAssertTrue(text.contains("sugar 56.3 g"))
        XCTAssertTrue(text.contains("Nutri-Score E"))
        XCTAssertTrue(text.contains("Amma:"))
        var noData = p; noData.ingredientsText = nil; noData.ingredientTags = []
        XCTAssertTrue(AIContext.product(noData, members: [amma]).contains("Ingredients: not available."))
    }

    func testSupplementsDoNotSendGrades() {
        var p = Product(barcode: "1", name: "Vit D", brand: nil, imageURL: nil, ingredientsText: "cholecalciferol",
                        allergenTags: [], nutrition: Nutrition(calories: nil, sugarG: nil, carbsG: nil, sodiumMg: nil,
                                                              satFatG: nil, transFatG: nil, proteinG: nil, basis: "per 100 g"))
        p.categoryTags = ["en:dietary-supplements"]; p.novaGroup = 4
        XCTAssertFalse(AIContext.product(p, members: []).contains("NOVA"))
    }

    func testSystemPromptHasSafetyRulesAndNoSecrets() {
        let prompt = AskAI.systemPrompt(family: [amma], product: nil)
        XCTAssertTrue(prompt.contains("not a doctor"))
        XCTAssertTrue(prompt.contains("Never say a food is safe for an allergy"))
        XCTAssertFalse(prompt.contains("sk-ant"))
    }
}

final class MealIdeasTests: XCTestCase {
    private let kid = Member(name: "Arjun", conditions: [.allergy(.milk), .customAllergy("mango")])

    private let reply = """
    Sure!
    {"meals":[
      {"name":"Dinner","dishes":[{"name":"Dal with rice","kcal":450,"ingredients":["lentils","rice"],"why":"Protein and fibre."}]},
      {"name":"Breakfast","dishes":[
         {"name":"Paneer paratha","kcal":380,"ingredients":["whole wheat","paneer"],"why":"x"},
         {"name":"Vegetable upma","kcal":300,"ingredients":["vegetables","oil"],"why":"Slow energy."},
         {"name":"Mango smoothie","kcal":200,"ingredients":["mango","water"],"why":"x"}]},
      {"name":"Snacks","dishes":[{"name":"Roasted chana","kcal":150,"ingredients":["chickpeas"],"why":"Fibre."}]},
      {"name":"Midnight feast","dishes":[{"name":"Cake","kcal":900,"ingredients":["flour"],"why":"x"}]}
    ],"tips":["Drink water before meals."]}
    """

    func testDishesWithTheMembersAllergensAreRemovedByTheApp() throws {
        let ideas = try MealIdeasParser.parse(reply, for: kid)
        let names = ideas.slots.flatMap(\.dishes).map(\.name)
        XCTAssertFalse(names.contains("Paneer paratha"))      // paneer = milk
        XCTAssertFalse(names.contains("Mango smoothie"))      // custom allergy
        XCTAssertEqual(ideas.removedForAllergy, 2)
        XCTAssertTrue(names.contains("Vegetable upma"))
    }

    func testSlotsAreOrderedAndUnknownMealsIgnored() throws {
        let ideas = try MealIdeasParser.parse(reply, for: kid)
        XCTAssertEqual(ideas.slots.map(\.name), ["Breakfast", "Dinner", "Snacks"])
        XCTAssertEqual(ideas.totalKcal, 300 + 450 + 150)
        XCTAssertEqual(ideas.tips, ["Drink water before meals."])
    }

    func testRotiAndCheeseAreCaughtByTheKeywordLists() {
        let celiac = Member(name: "C", conditions: [.allergy(.gluten)])
        XCTAssertFalse(MealSafety.allergenHits(name: "Roti with sabzi", ingredients: [], for: celiac).isEmpty)
        let dairy = Member(name: "D", conditions: [.allergy(.milk)])
        XCTAssertFalse(MealSafety.allergenHits(name: "Cheese toast", ingredients: ["bread"], for: dairy).isEmpty)
        XCTAssertFalse(MealSafety.allergenHits(name: "Khichdi", ingredients: ["rice", "ghee"], for: dairy).isEmpty)
        XCTAssertTrue(MealSafety.allergenHits(name: "Rice and dal", ingredients: ["lentils"], for: dairy).isEmpty)
    }

    func testClampsAndRejectsGarbage() throws {
        let big = #"{"meals":[{"name":"Lunch","dishes":[{"name":"Feast","kcal":99999,"ingredients":[],"why":""}]}]}"#
        XCTAssertEqual(try MealIdeasParser.parse(big, for: kid).slots[0].dishes[0].kcal, 1500)
        XCTAssertThrowsError(try MealIdeasParser.parse("I cannot do that.", for: kid))
    }

    func testPromptMentionsAllergiesTargetAndPreferences() {
        let prompt = MealIdeasService.systemPrompt(member: kid, plan: nil, targetKcal: 1800, preferences: "vegetarian")
        XCTAssertTrue(prompt.contains("ALLERGIES"))
        XCTAssertTrue(prompt.contains("1800 kcal"))
        XCTAssertTrue(prompt.contains("vegetarian"))
        XCTAssertTrue(prompt.contains("NEVER include an ingredient the person is allergic to"))
    }
}
