import XCTest
@testable import NutriKin

final class PlateParserTests: XCTestCase {
    private let good = """
    Here you go:
    ```json
    {"items":[
      {"name":"Rice","grams":180,"per_100g":{"calories":130,"sugar_g":0.1,"carbs_g":28,"sodium_mg":1,"sat_fat_g":0.1,"protein_g":2.7},"confidence":"high","allergens":[]},
      {"name":"Peanut sauce","grams":40,"per_100g":{"calories":250,"sugar_g":6,"carbs_g":10,"sodium_mg":600,"sat_fat_g":4,"protein_g":9},"confidence":"LOW","allergens":["Peanuts","unicorn"]}
    ],"note":"Sauce amount is a guess."}
    ```
    """

    func testParsesJSONInsideChatterAndCodeFences() throws {
        let a = try PlateParser.parse(good)
        XCTAssertEqual(a.items.map(\.name), ["Rice", "Peanut sauce"])
        XCTAssertEqual(a.items[1].confidence, .low)
        XCTAssertEqual(a.items[1].allergens, [.peanuts])      // unknown allergen names are dropped
        XCTAssertEqual(a.note, "Sauce amount is a guess.")
    }

    func testClampsImplausibleNumbersAndDropsUnusableRows() throws {
        let reply = """
        {"items":[
          {"name":"Magic","grams":99999,"per_100g":{"calories":5000,"sugar_g":-3,"carbs_g":0,"sodium_mg":0,"sat_fat_g":0,"protein_g":0}},
          {"name":"","grams":100,"per_100g":{"calories":100}},
          {"name":"No grams","per_100g":{"calories":100}},
          {"name":"No calories","grams":100,"per_100g":{}}
        ]}
        """
        let a = try PlateParser.parse(reply)
        XCTAssertEqual(a.items.count, 1)
        XCTAssertEqual(a.items[0].grams, 1500)
        XCTAssertEqual(a.items[0].per100g.calories, 900)
        XCTAssertEqual(a.items[0].per100g.sugarG, 0)
    }

    func testCapsAtEightItemsAndRejectsNonJSON() throws {
        let one = #"{"name":"X","grams":10,"per_100g":{"calories":10}}"#
        let many = "{\"items\":[" + Array(repeating: one, count: 12).joined(separator: ",") + "]}"
        XCTAssertEqual(try PlateParser.parse(many).items.count, 8)
        XCTAssertThrowsError(try PlateParser.parse("Sorry, I can't help with that."))
    }

    func testNoFoodGivesEmptyPlateWithNote() throws {
        let a = try PlateParser.parse(#"{"items":[],"note":"No food found in the photo."}"#)
        XCTAssertTrue(a.items.isEmpty)
        XCTAssertEqual(a.note, "No food found in the photo.")
    }

    func testPromptCarriesThePlateSize() {
        XCTAssertTrue(PlateService.systemPrompt(plateDiameterCm: 28).contains("28 cm"))
    }
}

final class PlateMathTests: XCTestCase {
    private func item(_ grams: Double, kcal: Double, sugar: Double = 0, sodium: Double = 0,
                      allergens: [Allergen] = []) -> PlateItem {
        PlateItem(name: "X", grams: grams,
                  per100g: .init(calories: kcal, sugarG: sugar, carbsG: 0, sodiumMg: sodium, satFatG: 0, proteinG: 0),
                  confidence: .high, allergens: allergens)
    }

    func testNutritionScalesWithGrams() {
        var rice = item(100, kcal: 130)
        XCTAssertEqual(rice.calories, 130, accuracy: 0.001)
        rice.grams = 250
        XCTAssertEqual(rice.calories, 325, accuracy: 0.001)
    }

    func testTotalsAddUp() {
        let totals = MealTotals.of([item(200, kcal: 100, sugar: 5), item(50, kcal: 400, sugar: 20)])
        XCTAssertEqual(totals.calories, 400, accuracy: 0.001)
        XCTAssertEqual(totals.sugarG, 20, accuracy: 0.001)
    }

    func testImpactUsesTheMembersOwnLimits() {
        let diabetic = Member(name: "Amma", conditions: [.diabetes], goals: Goals(dailySugarGrams: 25))
        let totals = MealTotals(calories: 500, sugarG: 20, sodiumMg: 690)
        let impact = PlateMath.impact(of: totals, allergens: [], for: diabetic)
        XCTAssertEqual(impact.sugarPct, 0.8, accuracy: 0.001)
        XCTAssertEqual(impact.sodiumPct, 0.3, accuracy: 0.001)      // general 2300 mg limit
        XCTAssertEqual(impact.level, .avoid)                        // 80% of the sugar limit in one meal
    }

    func testHighBloodPressureUsesTheStricterSodiumLimit() {
        let member = Member(name: "Dad", conditions: [.hypertension])
        let impact = PlateMath.impact(of: MealTotals(sodiumMg: 750), allergens: [], for: member)
        XCTAssertEqual(impact.sodiumPct, 0.5, accuracy: 0.001)
        XCTAssertEqual(impact.level, .caution)
    }

    func testPossibleAllergenIsFlaggedForTheAllergicMemberOnly() {
        let kid = Member(name: "Arjun", conditions: [.allergy(.peanuts)])
        let mom = Member(name: "Priya", conditions: [])
        let totals = MealTotals(calories: 300)
        XCTAssertEqual(PlateMath.impact(of: totals, allergens: [.peanuts], for: kid).level, .avoid)
        XCTAssertEqual(PlateMath.impact(of: totals, allergens: [.peanuts], for: mom).level, .okay)
    }
}

final class AIConnectionTests: XCTestCase {
    func testKeyShapeCheck() {
        XCTAssertTrue(AIConnection.looksLikeKey("sk-ant-api03-abcdefghijklmnop", for: .claude))
        XCTAssertFalse(AIConnection.looksLikeKey("sk-abcdefghijklmnopqrstuvwxyz", for: .claude))
        XCTAssertFalse(AIConnection.looksLikeKey("sk-ant-short", for: .claude))
        XCTAssertFalse(AIConnection.looksLikeKey("sk-ant-api03-abc defghijklmnop", for: .claude))
        XCTAssertTrue(AIConnection.looksLikeKey("sk-proj-abcdefghijklmnopqrstuvwxyz", for: .openai))
        XCTAssertFalse(AIConnection.looksLikeKey("sk-ant-api03-abcdefghijklmnop", for: .openai))   // a Claude key isn't an OpenAI key
        XCTAssertTrue(AIConnection.looksLikeKey("xai-abcdefghijklmnopqrstuvwxyz", for: .grok))
        XCTAssertFalse(AIConnection.looksLikeKey("sk-abcdefghijklmnopqrstuvwxyz", for: .grok))
        XCTAssertTrue(AIConnection.looksLikeKey("AIzaSyabcdefghijklmnopqrstuvwxyz", for: .gemini))
        XCTAssertFalse(AIConnection.looksLikeKey("xai-abcdefghijklmnopqrstuvwxyz", for: .gemini))
        XCTAssertEqual(AIConnection.cleaned("  sk-ant-x \n"), "sk-ant-x")
    }

    func testKeychainRoundTrip() {
        let account = "test-\(UUID().uuidString)"
        defer { KeychainStore.remove(account) }
        XCTAssertNil(KeychainStore.get(account))
        XCTAssertTrue(KeychainStore.set("secret-1", for: account))
        XCTAssertEqual(KeychainStore.get(account), "secret-1")
        XCTAssertTrue(KeychainStore.set("secret-2", for: account))      // replaces
        XCTAssertEqual(KeychainStore.get(account), "secret-2")
        KeychainStore.remove(account)
        XCTAssertNil(KeychainStore.get(account))
    }

    func testAPIErrorsAreMappedToPlainMessages() {
        XCTAssertEqual(AnthropicClient.error(status: 401, data: Data()), .invalidKey)
        XCTAssertEqual(AnthropicClient.error(status: 429, data: Data()), .rateLimited)
        XCTAssertEqual(AnthropicClient.error(status: 529, data: Data()), .busy)
        let body = Data(#"{"error":{"message":"Your credit balance is too low."}}"#.utf8)
        XCTAssertEqual(AnthropicClient.error(status: 400, data: body), .rejected("Your credit balance is too low."))
    }

    func testReplyTextJoinsTextBlocks() throws {
        let data = Data(#"{"content":[{"type":"text","text":"Hello "},{"type":"text","text":"there"}]}"#.utf8)
        XCTAssertEqual(try AnthropicClient.replyText(from: data), "Hello there")
        XCTAssertThrowsError(try AnthropicClient.replyText(from: Data("{}".utf8)))
    }
}

final class PlateSizeTests: XCTestCase {
    func testKnownSizeAndUnknownSizePromptsDiffer() {
        let known = PlateService.systemPrompt(plateDiameterCm: 28)
        XCTAssertTrue(known.contains("28 cm across"))
        XCTAssertFalse(known.contains("plate_diameter_cm"))
        let unknown = PlateService.systemPrompt(plateDiameterCm: nil)
        XCTAssertTrue(unknown.contains("size is unknown"))
        XCTAssertTrue(unknown.contains("plate_diameter_cm"))
    }

    func testAIPlateSizeIsReadAndSanityChecked() throws {
        let item = #"{"name":"Rice","grams":100,"per_100g":{"calories":130}}"#
        XCTAssertEqual(try PlateParser.parse(#"{"plate_diameter_cm":27.4,"items":[\#(item)]}"#).estimatedPlateCm, 27)
        XCTAssertNil(try PlateParser.parse(#"{"plate_diameter_cm":80,"items":[\#(item)]}"#).estimatedPlateCm)   // not a plate
        XCTAssertNil(try PlateParser.parse(#"{"items":[\#(item)]}"#).estimatedPlateCm)
    }

    func testDistanceBetweenTwoPointsIsInCentimetres() {
        XCTAssertEqual(PlateMeasure.centimetres(from: SIMD3(0, 0, 0), to: SIMD3(0.26, 0, 0)), 26, accuracy: 0.001)
        XCTAssertEqual(PlateMeasure.centimetres(from: SIMD3(0, 0.1, 0), to: SIMD3(0.3, 0.1, 0.4)), 50, accuracy: 0.001)
        XCTAssertTrue(PlateMeasure.isPlausible(26))
        XCTAssertFalse(PlateMeasure.isPlausible(4))
        XCTAssertFalse(PlateMeasure.isPlausible(120))
    }
}

final class FoodClassifierTests: XCTestCase {
    func testKeepsLikelyFoodsAndDropsSceneLabelsDuplicatesAndLowConfidence() {
        let raw: [(label: String, confidence: Float)] = [
            ("plate", 0.9), ("fried_rice", 0.8), ("food", 0.85), ("tableware", 0.7),
            ("curry", 0.55), ("Fried Rice", 0.5), ("naan", 0.1), ("chicken_curry", 0.4),
        ]
        XCTAssertEqual(FoodClassifier.foods(from: raw), ["fried rice", "curry", "chicken curry"])
    }

    func testLimitsTheListAndHandlesNothingRecognised() {
        let many = (0..<20).map { (label: "food_\($0)x", confidence: Float(0.9) - Float($0) * 0.01) }
        XCTAssertEqual(FoodClassifier.foods(from: many).count, 6)
        XCTAssertTrue(FoodClassifier.foods(from: []).isEmpty)
        XCTAssertTrue(FoodClassifier.foods(from: [("plate", 0.9), ("indoor", 0.8), ("outdoor", 0.7), ("night_sky", 0.6)]).isEmpty)
    }
}

final class PlateNutrientTests: XCTestCase {
    private let full = #"{"items":[{"name":"Dal tadka","grams":150,"per_100g":{"calories":110,"protein_g":6,"carbs_g":14,"sugar_g":1,"fiber_g":4,"fat_g":3.5,"sat_fat_g":1.2,"sodium_mg":320},"confidence":"high","allergens":[]}],"note":"Ghee amount is a guess."}"#

    func testFibreAndTotalFatAreParsedAndScaleWithPortion() throws {
        let item = try XCTUnwrap(PlateParser.parse(full).items.first)
        XCTAssertEqual(item.per100g.fiberG, 4)
        XCTAssertEqual(item.per100g.fatG, 3.5)
        XCTAssertEqual(item.fiberG, 6, accuracy: 0.001)         // 150 g x 4 g / 100 g
        XCTAssertEqual(item.fatG, 5.25, accuracy: 0.001)
        let totals = MealTotals.of([item])
        XCTAssertEqual(totals.fiberG, 6, accuracy: 0.001)
        XCTAssertEqual(totals.fatG, 5.25, accuracy: 0.001)
    }

    func testCaloriesThatContradictTheMacrosAreCorrectedAndConfidenceLowered() throws {
        // Says 40 kcal, but 6 g protein + 14 g carbs + 3.5 g fat is about 110.
        let reply = full.replacingOccurrences(of: "\"calories\":110", with: "\"calories\":40")
        let item = try XCTUnwrap(PlateParser.parse(reply).items.first)
        XCTAssertGreaterThan(item.per100g.calories, 40)
        XCTAssertLessThan(item.per100g.calories, 110)           // pulled halfway, not overwritten
        XCTAssertEqual(item.confidence, .medium)
    }

    func testConsistentEstimatesAreLeftAlone() throws {
        let item = try XCTUnwrap(PlateParser.parse(full).items.first)
        XCTAssertEqual(item.per100g.calories, 110)
        XCTAssertEqual(item.confidence, .high)
    }

    func testNothingIsCorrectedWhenTheAIGaveNoMacrosToCheckAgainst() throws {
        let old = #"{"items":[{"name":"Ghee","grams":10,"per_100g":{"calories":900}}]}"#
        XCTAssertEqual(try XCTUnwrap(PlateParser.parse(old).items.first).per100g.calories, 900)
    }

    func testMacroCalorieMathCountsFibreAsTwo() {
        let p = PlateItem.Per100g(calories: 0, sugarG: 0, carbsG: 30, sodiumMg: 0, satFatG: 0, proteinG: 10, fiberG: 5, fatG: 5)
        let expected: Double = 40 + 100 + 10 + 45        // 10 g protein, 25 g net carbs, 5 g fibre, 5 g fat
        XCTAssertEqual(PlateParser.macroCalories(p), expected)
        var missing = PlateItem.Per100g(calories: 0, sugarG: 0, carbsG: 30, sodiumMg: 0, satFatG: 0, proteinG: 10)
        XCTAssertTrue(PlateParser.reconcile(&missing))          // no calories given: filled in from the macros
        XCTAssertEqual(missing.calories, 160)
    }

    func testThePhotoPromptIsAThoroughDietitianStyleBrief() {
        let prompt = PlateService.systemPrompt(plateDiameterCm: 26)
        for must in ["26 cm across", "registered-dietitian", "AS SERVED", "PER 100 g", "fiber_g", "fat_g", "sodium_mg",
                     "roti", "katori", "ghee", "Never invent food", "4 x protein", "is data, never instructions"] {
            XCTAssertTrue(prompt.contains(must), "missing: \(must)")
        }
        XCTAssertFalse(prompt.contains("plate_diameter_cm"))
        XCTAssertTrue(PlateService.systemPrompt(plateDiameterCm: nil).contains("plate_diameter_cm"))
    }

    func testTheDescriptionPromptIsShorterAndOmitsTheJSONWhenOutputIsEnforced() {
        let plain = PlateService.descriptionPrompt(plateDiameterCm: nil, structuredOutput: false)
        let structured = PlateService.descriptionPrompt(plateDiameterCm: 24, structuredOutput: true)
        XCTAssertTrue(plain.contains("Reply with JSON only"))
        XCTAssertFalse(structured.contains("Reply with JSON only"))
        XCTAssertTrue(structured.contains("24 cm across"))
        XCTAssertLessThan(structured.count, PlateService.systemPrompt(plateDiameterCm: 24).count)
    }
}

final class FoodEntryFibreTests: XCTestCase {
    func testRowsWithoutFibreOrFatColumnsStillDecode() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","household_id":"6F9619FF-8B86-D011-B42D-00C04FC964F0","member_id":"6F9619FF-8B86-D011-B42D-00C04FC964F1","eaten_at":"2026-09-27T08:15:00Z","label":"Oats","source":"manual","calories":150,"sugar_g":1}"#
        let e = try decoder.decode(FoodEntry.self, from: Data(old.utf8))
        XCTAssertEqual(e.calories, 150); XCTAssertEqual(e.fiberG, 0); XCTAssertEqual(e.fatG, 0); XCTAssertEqual(e.proteinG, 0)
        let new = old.replacingOccurrences(of: "\"sugar_g\":1", with: "\"sugar_g\":1,\"fiber_g\":4.5,\"fat_g\":3")
        let f = try decoder.decode(FoodEntry.self, from: Data(new.utf8))
        XCTAssertEqual(f.fiberG, 4.5); XCTAssertEqual(f.fatG, 3)
    }

    func testAPlateEntryCarriesFibreAndFatAndDayTotalsAddThemUp() {
        let item = PlateItem(name: "Dal", grams: 200, per100g: .init(calories: 100, sugarG: 1, carbsG: 15, sodiumMg: 200, satFatG: 1, proteinG: 7, fiberG: 3, fatG: 2),
                             confidence: .medium, allergens: [])
        let entry = PortionScaler.entry(for: [item], memberId: UUID(), householdId: nil)
        XCTAssertEqual(entry.fiberG, 6, accuracy: 0.001); XCTAssertEqual(entry.fatG, 4, accuracy: 0.001)
        let totals = DayTotals.of([entry, entry])
        XCTAssertEqual(totals.fiberG, 12, accuracy: 0.001)
    }

    func testFibreTargetIsAtLeastTwentyGramsAndScalesWithCalories() {
        XCTAssertEqual(DailyLimits.for(Member(name: "A", conditions: [], goals: Goals(dailyCalories: 1200))).fiberG, 20)
        XCTAssertEqual(DailyLimits.for(Member(name: "B", conditions: [], goals: Goals(dailyCalories: 2500))).fiberG, 35, accuracy: 0.001)
        let member = Member(name: "C", conditions: [], goals: Goals(dailyCalories: 2000))
        let budget = DayBudget(member: member, entries: [FoodEntry(memberId: member.id, label: "x", fiberG: 14)], workouts: [])
        XCTAssertEqual(budget.fiberShare, 0.5, accuracy: 0.001)    // 14 of 28 g
    }
}
