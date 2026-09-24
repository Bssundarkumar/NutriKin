import XCTest
@testable import NutriKin

final class LabelParserTests: XCTestCase {
    func testEnglishLabel() {
        let p = LabelParser.parse([
            "NUTRITION FACTS", "Per 100 g", "Energy 539 kcal", "Total Fat 30.9 g", "of which saturates 10.6 g",
            "Carbohydrate 57.5 g", "of which sugars 56.3 g", "Protein 6.3 g", "Salt 0.107 g",
        ])
        XCTAssertEqual(p.nutrition.basis, "per 100 g")
        XCTAssertEqual(p.nutrition.calories, 539)
        XCTAssertEqual(p.nutrition.satFatG, 10.6)
        XCTAssertEqual(p.nutrition.carbsG, 57.5)
        XCTAssertEqual(p.nutrition.sugarG, 56.3)
        XCTAssertEqual(p.nutrition.proteinG, 6.3)
        XCTAssertEqual(p.nutrition.sodiumMg ?? 0, 42.8, accuracy: 0.1)     // 0.107 g salt x 400
    }

    func testIngredientsStopAtTheNutritionTableAndKeepAllergenAdvice() {
        let p = LabelParser.parse([
            "INGREDIENTS: Sugar, palm oil, hazelnuts (13%),", "skimmed milk powder, lecithins", "(soy), vanillin.",
            "Contains: hazelnuts, milk, soy.", "Nutrition per 100 g", "Energy 539 kcal",
        ])
        XCTAssertEqual(p.ingredientsText, "Sugar, palm oil, hazelnuts (13%), skimmed milk powder, lecithins (soy), vanillin. Contains: hazelnuts, milk, soy")
    }

    func testFrenchLabelWithDecimalCommas() {
        let p = LabelParser.parse([
            "Ingrédients : Sucre, huile de palme, NOISETTES 13%, cacao maigre 7,4%,", "LAIT écrémé en poudre 6,6%.",
            "Valeurs nutritionnelles pour 100 g", "Énergie 2252 kJ / 539 kcal", "Matières grasses 30,9 g", "dont acides gras saturés 10,6 g",
            "Glucides 57,5 g", "dont sucres 56,3 g", "Protéines 6,3 g", "Sel 0,107 g",
        ])
        XCTAssertTrue(p.ingredientsText?.hasPrefix("Sucre, huile de palme, NOISETTES 13%, cacao maigre 7,4%, LAIT") == true)
        XCTAssertEqual(p.nutrition.calories, 539)
        XCTAssertEqual(p.nutrition.sugarG, 56.3)
        XCTAssertEqual(p.nutrition.satFatG, 10.6)
    }

    func testIndianStyleLabelWithSodiumAndKilojouleOnly() {
        let p = LabelParser.parse([
            "INGREDIENTS: Refined wheat flour (Maida), palm oil, sugar, iodised salt, raising agents (INS 500(ii)).",
            "Nutritional Information (Approx.) Per 100g", "Energy 1975 kJ", "Protein 7.1 g", "Total Carbohydrate 66 g",
            "Total Sugars 4.5 g", "Added Sugars 4.0 g", "Total Fat 25 g", "Saturated Fat 12 g", "Trans Fat 0 g", "Sodium 480 mg",
            "Best before 6 months from manufacture", "FSSAI Lic. No. 1001",
        ])
        XCTAssertEqual(p.ingredientsText, "Refined wheat flour (Maida), palm oil, sugar, iodised salt, raising agents (INS 500(ii))")
        XCTAssertEqual(p.nutrition.calories, 472)                      // 1975 kJ / 4.184
        XCTAssertEqual(p.nutrition.sugarG, 4.5)                        // total sugars, not added
        XCTAssertEqual(p.nutrition.carbsG, 66)
        XCTAssertEqual(p.nutrition.satFatG, 12)
        XCTAssertEqual(p.nutrition.transFatG, 0)
        XCTAssertEqual(p.nutrition.sodiumMg, 480)
    }

    func testSodiumInGramsAndPerServing() {
        let p = LabelParser.parse(["Serving size 30 g", "Energy 120 kcal", "Sodium 0.2 g"])
        XCTAssertEqual(p.nutrition.basis, "per serving")
        XCTAssertEqual(p.nutrition.sodiumMg, 200)
    }

    func testNothingUsefulIsReportedAsSuch() {
        let p = LabelParser.parse(["Fresh Farm", "Since 1975", "www.example.com"])
        XCTAssertFalse(p.foundAnything)
        XCTAssertNil(p.ingredientsText)
    }

    func testHeaderWithoutIngredientsDoesNotSwallowTheTable() {
        let p = LabelParser.parse(["Composition per 100 g", "Energy 100 kcal"])
        XCTAssertNil(p.ingredientsText)
        XCTAssertEqual(p.nutrition.calories, 100)
    }
}
