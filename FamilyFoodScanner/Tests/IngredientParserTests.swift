import XCTest
@testable import NutriKin

final class IngredientParserTests: XCTestCase {
    // Real label text, as returned by Open Food Facts.
    func testNutellaKeepsDecimalCommasAndCalmsShouting() {
        let text = "Sucre, huile de palme, NOISETTES 13%, cacao maigre 7,4%, LAIT écrémé en poudre 6,6%, LACTOSERUM en poudre, émulsifiants: lécithines [SOJA), vanilline. Sans gluten."
        XCTAssertEqual(IngredientParser.items(from: text), [
            "Sucre", "Huile de palme", "Noisettes 13%", "Cacao maigre 7,4%",
            "Lait écrémé en poudre 6,6%", "Lactoserum en poudre",
            "Émulsifiants: lécithines [SOJA)", "Vanilline", "Sans gluten",
        ])
    }

    func testNestedBracketsStayInOneItem() {
        let text = "Jambon frais de porc, Sel, Dextrose, Bouillon (eau, sel, couenne de porc, oignon, ail), Antioxydant : isoascorbate de sodium, Conservateur : nitrite de sodium."
        let items = IngredientParser.items(from: text)
        XCTAssertEqual(items.count, 6)   // the bracketed broth counts as one
        XCTAssertEqual(items[3], "Bouillon (eau, sel, couenne de porc, oignon, ail)")
        XCTAssertEqual(items.last, "Conservateur : nitrite de sodium")
    }

    func testENumbersSurviveAndMarkupIsRemoved() {
        let items = IngredientParser.items(from: "Agua carbonatada, azúcar, colorante (E-150d), _leche_ entera*")
        XCTAssertEqual(items, ["Agua carbonatada", "Azúcar", "Colorante (E-150d)", "Leche entera"])
    }

    func testHeadingAndJunkAreDropped() {
        XCTAssertEqual(IngredientParser.items(from: "Ingredients: oats, water, salt."), ["Oats", "Water", "Salt"])
        XCTAssertEqual(IngredientParser.items(from: ",, ; 12 ; ."), [])
        XCTAssertEqual(IngredientParser.items(from: ""), [])
    }

    func testFlagsForIndividualIngredients() {
        let analyzer = IngredientAnalyzer()
        let diabetic = Member(name: "Amma", conditions: [.diabetes])
        let product = Product(barcode: "1", name: "X", brand: nil, imageURL: nil,
                              ingredientsText: "Sucre, cacao", allergenTags: [], nutrition: Nutrition(basis: "per 100 g"),
                              ingredientTags: ["en:sugar", "en:cocoa"])
        let alerts = analyzer.alerts(for: product, members: [diabetic])
        XCTAssertNotNil(analyzer.flag(for: "Sucre", among: alerts))      // French word still recognised
        XCTAssertNil(analyzer.flag(for: "Cacao", among: alerts))
    }

    // The allergen text fallback must catch non-English labels, not just English.
    func testAllergenWordsAreRecognisedInOtherLanguages() {
        func hit(_ allergen: Allergen, _ text: String) -> Bool {
            let p = Product(barcode: "1", name: "X", brand: nil, imageURL: nil, ingredientsText: text,
                            allergenTags: [], nutrition: Nutrition(basis: "per 100 g"))
            return p.contains(allergen)      // no allergen tags: relies on the text
        }
        XCTAssertTrue(hit(.milk, "Sucre, LAIT écrémé en poudre"))
        XCTAssertTrue(hit(.soybeans, "émulsifiants: lécithines [SOJA)"))
        XCTAssertTrue(hit(.eggs, "harina, huevo, sal"))
        XCTAssertTrue(hit(.gluten, "Weizenmehl, Zucker"))
        XCTAssertTrue(hit(.peanuts, "cacahuètes grillées"))
        XCTAssertTrue(hit(.nuts, "Noisettes 13%"))
        XCTAssertTrue(hit(.fish, "filetto di merluzzo"))
        XCTAssertFalse(hit(.milk, "Sucre, cacao, vanilline"))
    }
}
