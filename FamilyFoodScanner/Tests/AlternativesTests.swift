import XCTest
@testable import NutriKin

final class AlternativesTests: XCTestCase {
    private func product(_ code: String, name: String = "P", sugar: Double, sodium: Double = 100,
                         satFat: Double = 1, ingredients: String? = "oats, water",
                         allergens: [String] = [], servingBasis: Bool = false) -> Product {
        let per100 = Nutrition(calories: 200, sugarG: sugar, carbsG: 30, sodiumMg: sodium,
                               satFatG: satFat, transFatG: 0, proteinG: 4, basis: "per 100 g")
        var p = Product(barcode: code, name: name, brand: "B", imageURL: nil, ingredientsText: ingredients,
                        allergenTags: allergens,
                        nutrition: servingBasis
                            ? Nutrition(calories: 40, sugarG: 1, carbsG: 6, sodiumMg: 20, satFatG: 0.2,
                                        transFatG: 0, proteinG: 1, basis: "per serving (20 g)")
                            : per100)
        p.per100g = per100
        p.categoryTags = ["en:snacks", "en:sweet-snacks", "en:biscuits"]
        return p
    }

    private let diabetic = Member(name: "Amma", conditions: [.diabetes], goals: Goals(dailySugarGrams: 25))

    func testSuggestsSaferProductsBestFirst() {
        let current = product("11111111", sugar: 55)
        let better = product("22222222", name: "Better", sugar: 2)
        let alright = product("33333333", name: "Alright", sugar: 12)
        let result = AlternativeRanker().rank(current: current, candidates: [alright, better], members: [diabetic])
        XCTAssertEqual(result.map(\.product.barcode), ["22222222", "33333333"])
    }

    func testNeverSuggestsTheSameProductOrAnAllergen() {
        let nutAllergy = Member(name: "Kid", conditions: [.allergy(.peanuts), .diabetes], goals: Goals(dailySugarGrams: 25))
        let current = product("11111111", sugar: 50)
        let same = product("11111111", sugar: 1)
        let peanut = product("22222222", name: "Nutty", sugar: 1, ingredients: "peanuts, sugar", allergens: ["en:peanuts"])
        let fine = product("33333333", name: "Fine", sugar: 1)
        let result = AlternativeRanker().rank(current: current, candidates: [same, peanut, fine], members: [nutAllergy])
        XCTAssertEqual(result.map(\.product.barcode), ["33333333"])
    }

    func testMissingDataIsNeverRecommended() {
        let current = product("11111111", sugar: 55)
        let noIngredients = product("22222222", name: "Blank", sugar: 0, ingredients: nil)
        var noNutrition = product("33333333", name: "Empty", sugar: 0)
        noNutrition.per100g = Nutrition(calories: 100, sugarG: nil, carbsG: nil, sodiumMg: nil,
                                        satFatG: nil, transFatG: nil, proteinG: nil, basis: "per 100 g")
        XCTAssertTrue(AlternativeRanker().rank(current: current, candidates: [noIngredients, noNutrition],
                                               members: [diabetic]).isEmpty)
    }

    func testComparesOnPer100gEvenWhenServingFiguresExist() {
        // Tiny serving looks harmless, but per 100 g it is very sugary.
        let current = product("11111111", sugar: 60, servingBasis: true)
        let similar = product("22222222", name: "Same", sugar: 58)
        XCTAssertTrue(AlternativeRanker().rank(current: current, candidates: [similar], members: [diabetic]).isEmpty)
    }

    func testRequiresAMeaningfulImprovementAndDeduplicates() {
        let current = product("11111111", sugar: 12)
        let barely = product("22222222", name: "Barely", sugar: 11.9)
        let good1 = product("33333333", name: "Good", sugar: 0.5)
        let good2 = product("44444444", name: "Good", sugar: 0.5)   // same brand+name
        let result = AlternativeRanker().rank(current: current, candidates: [barely, good1, good2], members: [diabetic])
        XCTAssertEqual(result.map(\.product.barcode), ["33333333"])
    }

    func testSlightlyLessBadIsNotGoodEnough() {
        // Both are poor for a diabetic; 40 beats 28, but neither is a decent choice.
        let current = product("11111111", sugar: 60)
        let meh = product("22222222", name: "Meh", sugar: 40)
        XCTAssertTrue(AlternativeRanker().rank(current: current, candidates: [meh], members: [diabetic]).isEmpty)
    }

    func testProductsFromUnrelatedCategoriesAreIgnored() {
        let current = product("11111111", sugar: 55)
        var sauce = product("22222222", name: "Chilli sauce", sugar: 0)
        sauce.categoryTags = ["en:sauces", "en:spreads"]
        XCTAssertTrue(AlternativeRanker().rank(current: current, candidates: [sauce], members: [diabetic]).isEmpty)
    }

    func testNoFamilyOrNoPer100gGivesNothing() {
        let current = product("11111111", sugar: 50)
        let good = product("22222222", sugar: 1)
        XCTAssertTrue(AlternativeRanker().rank(current: current, candidates: [good], members: []).isEmpty)
        var photo = current; photo.per100g = nil
        XCTAssertTrue(AlternativeRanker().rank(current: photo, candidates: [good], members: [diabetic]).isEmpty)
    }
}

final class ProductGradesTests: XCTestCase {
    func testDecodesGradesCategoriesAndPer100g() {
        let json = """
        {"products":[{"code":"3017620422003","product_name":"Nutella","brands":"Ferrero",
          "nutriscore_grade":"e","nova_group":4,
          "categories_tags":["en:spreads","en:sweet-spreads","en:Produits à tartiner","fr:Nutella"],
          "ingredients_text":"Sugar, palm oil","nutriments":{"energy-kcal_100g":539,"sugars_100g":56.3,
          "sodium_100g":0.04,"saturated-fat_100g":10.6,"energy-kcal_serving":81,"sugars_serving":8.4}},
          {"code":"abc","product_name":"Bad code"},
          {"code":"12345678","product_name":"Stringy","nova_group":"3","nutriscore_grade":"unknown"}]}
        """
        let products = ProductService.decodeProducts(Data(json.utf8))
        XCTAssertEqual(products.map(\.barcode), ["3017620422003", "12345678"])
        let nutella = products[0]
        XCTAssertEqual(nutella.nutriScore, "e")
        XCTAssertEqual(nutella.novaGroup, 4)
        XCTAssertEqual(nutella.nutrition.basis, "per serving")
        XCTAssertEqual(nutella.per100g?.sugarG, 56.3)
        XCTAssertEqual(nutella.per100g?.sodiumMg ?? 0, 40, accuracy: 0.001)
        XCTAssertEqual(products[1].novaGroup, 3)
        XCTAssertNil(products[1].nutriScore)
        XCTAssertNil(products[1].per100g)
    }

    func testOnlyCleanEnglishCategoriesAreSearchable() {
        let tags = ["en:spreads", "en:Produits à tartiner", "fr:Nutella", "en:sweet-spreads"]
        XCTAssertEqual(ProductService.searchableCategories(tags), ["en:spreads", "en:sweet-spreads"])
    }
}

final class SupplementTests: XCTestCase {
    private func product(tags: [String]) -> Product {
        var p = Product(barcode: "12345678", name: "Vitamin D3", brand: nil, imageURL: nil, ingredientsText: nil,
                        allergenTags: [], nutrition: Nutrition(calories: nil, sugarG: nil, carbsG: nil, sodiumMg: nil,
                                                              satFatG: nil, transFatG: nil, proteinG: nil, basis: "per 100 g"))
        p.categoryTags = tags
        return p
    }

    func testSupplementsAreDetectedFromCategories() {
        XCTAssertTrue(product(tags: ["en:dietary-supplements", "en:vitamins"]).isSupplement)
        XCTAssertTrue(product(tags: ["en:food-supplements"]).isSupplement)
        XCTAssertTrue(product(tags: ["en:vitamin-supplements"]).isSupplement)
    }

    func testOrdinaryFoodsAndVitaminWaterAreNotSupplements() {
        XCTAssertFalse(product(tags: ["en:spreads", "en:sweet-spreads"]).isSupplement)
        XCTAssertFalse(product(tags: ["en:beverages", "en:vitamin-waters"]).isSupplement)
        XCTAssertFalse(product(tags: []).isSupplement)
    }
}

final class AlternativeIdeasTests: XCTestCase {
    private let diabetic = Member(name: "Amma", conditions: [.diabetes], goals: Goals(dailySugarGrams: 25))
    private let nutAllergic = Member(name: "Arjun", conditions: [.allergy(.nuts), .allergy(.peanuts)])

    private func product(_ code: String, kcal: Double, sugar: Double) -> Product {
        let n = Nutrition(calories: kcal, sugarG: sugar, carbsG: 30, sodiumMg: 100, satFatG: 1, transFatG: 0, proteinG: 4, basis: "per 100 g")
        var p = Product(barcode: code, name: "P\(code)", brand: "B", imageURL: nil, ingredientsText: "oats", allergenTags: [], nutrition: n)
        p.per100g = n
        p.categoryTags = ["en:spreads", "en:sweet-spreads"]
        return p
    }

    func testARichFoodIsNotImprovedByAWateryProduct() {
        let current = product("11111111", kcal: 540, sugar: 56)
        let sauce = product("22222222", kcal: 40, sugar: 1)          // sugar-free but a different kind of food
        let butter = product("33333333", kcal: 600, sugar: 4)        // a similar spread, far less sugar
        let result = AlternativeRanker().rank(current: current, candidates: [sauce, butter], members: [diabetic])
        XCTAssertEqual(result.map(\.product.barcode), ["33333333"])
    }

    func testLightFoodsCompareFreely() {
        let cola = product("11111111", kcal: 42, sugar: 10.6)
        let zero = product("22222222", kcal: 0.3, sugar: 0)
        XCTAssertEqual(AlternativeRanker().rank(current: cola, candidates: [zero], members: [diabetic]).count, 1)
    }

    func testAIIdeasCanComeFromOtherCategories() {
        let current = product("11111111", kcal: 540, sugar: 56)
        var other = product("22222222", kcal: 600, sugar: 3)
        other.categoryTags = ["en:nut-butters"]
        XCTAssertTrue(AlternativeRanker().rank(current: current, candidates: [other], members: [diabetic]).isEmpty)
        XCTAssertEqual(AlternativeRanker().rank(current: current, candidates: [other], members: [diabetic],
                                                requireSimilarCategory: false).count, 1)
    }

    func testIdeaParserCapsAtThreeAndDropsAllergenSearches() throws {
        let reply = """
        {"ideas":[{"search":"almond butter","why":"Nuts"},{"search":"sunflower seed butter","why":"Nut-free and low sugar."},
                  {"search":"tahini","why":"x"},{"search":"oat spread","why":"y"},{"search":"","why":"z"}]}
        """
        let ideas = try AlternativeIdeasParser.parse(reply, members: [nutAllergic])
        XCTAssertEqual(ideas.map(\.search), ["sunflower seed butter", "tahini", "oat spread"])
        XCTAssertThrowsError(try AlternativeIdeasParser.parse("nope", members: []))
    }

    func testPromptCarriesFamilyProductAndAllergyRule() {
        let text = AlternativeIdeasService.systemPrompt(product: product("11111111", kcal: 540, sugar: 56), members: [nutAllergic])
        XCTAssertTrue(text.contains("Arjun"))
        XCTAssertTrue(text.contains("NEVER suggest anything containing an ingredient a family member is allergic to"))
    }
}
