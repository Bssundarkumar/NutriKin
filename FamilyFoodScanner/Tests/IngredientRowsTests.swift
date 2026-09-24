import XCTest
@testable import NutriKin

final class IngredientRowsTests: XCTestCase {
    // Real Open Food Facts data for Nutella.
    private func nutella() -> Product {
        func a(_ id: String, _ text: String, _ pct: Double?, stated: Bool = false) -> IngredientAmount {
            .init(id: id, text: text, percent: pct, isStated: stated)
        }
        return Product(barcode: "3017620422003", name: "Nutella", brand: nil, imageURL: nil,
                       ingredientsText: "Sucre, huile de palme, NOISETTES 13%", allergenTags: [],
                       nutrition: Nutrition(basis: "per 100 g"),
                       ingredientTags: ["en:sugar", "en:palm-oil"],
                       ingredientAmounts: [
                        a("en:sugar", "Sucre", 52.16), a("en:palm-oil", "huile de palme", 18.28),
                        a("en:hazelnut", "NOISETTES", 13, stated: true), a("en:fat-reduced-cocoa", "cacao maigre", 7.4, stated: true),
                        a("en:skimmed-milk-powder", "LAIT écrémé en poudre", 6.6, stated: true),
                        a("en:vanillin", "vanilline", 0),
                       ])
    }
    private let amma = Member(name: "Amma", conditions: [.diabetes])
    private let arjun = Member(name: "Arjun", conditions: [.allergy(.milk)], age: 7)

    private func rows(_ members: [Member]) -> [IngredientRow] {
        let alerts = IngredientAnalyzer().alerts(for: nutella(), members: members)
        return IngredientRows.make(product: nutella(), alerts: alerts, members: members)
    }

    func testKeepsLabelOrderAndCleansNames() {
        XCTAssertEqual(rows([]).map(\.text), ["Sucre", "Huile de palme", "Noisettes", "Cacao maigre", "Lait écrémé en poudre", "Vanilline"])
    }

    func testAmountLabelsDistinguishStatedFromEstimated() {
        let r = rows([])
        XCTAssertEqual(r[0].amountLabel, "~52%")          // estimate
        XCTAssertEqual(r[2].amountLabel, "13%")           // printed on the label
        XCTAssertEqual(r[3].amountLabel, "7.4%")
        XCTAssertEqual(r[5].amountLabel, "<1%")           // trace estimate
    }

    func testSugarIsFlaggedOnlyForADiabeticAndExplainsWhy() {
        XCTAssertEqual(rows([]).first?.kind, .plain)
        let r = rows([amma])
        XCTAssertEqual(r[0].kind, .limit)
        XCTAssertTrue(r[0].note?.contains("Added sugars") == true)
    }

    func testAllergenRowsNameWhoIsAffected() {
        let r = rows([amma, arjun])
        let milk = r.first { $0.text.hasPrefix("Lait") }
        XCTAssertEqual(milk?.kind, .allergen)
        XCTAssertEqual(milk?.note, "An allergen for Arjun.")
    }

    func testFlaggedShareAddsUpTheWorrisomeAmounts() {
        let share = IngredientRows.flaggedShare(rows([amma, arjun]))
        XCTAssertEqual(share ?? 0, 52.16 + 6.6, accuracy: 0.01)   // sugar (diabetes) + milk (allergy)
        XCTAssertNil(IngredientRows.flaggedShare(rows([])) .flatMap { $0 == 0 ? nil : $0 })
    }

    func testFallsBackToLabelTextWhenThereIsNoBreakdown() {
        var p = nutella(); p.ingredientAmounts = []
        let r = IngredientRows.make(product: p, alerts: [], members: [])
        XCTAssertEqual(r.map(\.text), ["Sucre", "Huile de palme", "Noisettes 13%"])
        XCTAssertNil(r[0].percent)
        XCTAssertNil(IngredientRows.flaggedShare(r))
    }

    // MARK: decoding Open Food Facts' response

    func testDecodesIngredientEntriesIncludingOddOnes() throws {
        let json = #"""
        [{"id":"en:sugar","text":"Sucre","percent_estimate":52.16},
         {"id":"en:hazelnut","text":"NOISETTES","percent":13,"percent_estimate":13.3},
         {"id":"en:salt","text":"Sel","percent":"1.5"},
         {"id":"en:x","text":"  "},
         {"text":"Mystery"}]
        """#
        let items = try JSONDecoder().decode([OFFIngredient].self, from: Data(json.utf8)).compactMap(\.asAmount)
        // A blank label with a known id is kept (the row later shows the id's English name).
        XCTAssertEqual(items.map(\.text), ["Sucre", "NOISETTES", "Sel", "", "Mystery"])
        XCTAssertEqual(items[0].percent, 52.16); XCTAssertFalse(items[0].isStated)
        XCTAssertEqual(items[1].percent, 13);    XCTAssertTrue(items[1].isStated)     // label value wins over the estimate
        XCTAssertEqual(items[2].percent, 1.5);   XCTAssertTrue(items[2].isStated)     // number sent as a string
    }

    func testBlankLabelFallsBackToTheEnglishNameFromTheId() {
        let p = Product(barcode: "1", name: "X", brand: nil, imageURL: nil, ingredientsText: nil, allergenTags: [],
                        nutrition: Nutrition(basis: "per 100 g"),
                        ingredientAmounts: [.init(id: "en:palm-oil", text: "", percent: 20, isStated: false)])
        XCTAssertEqual(IngredientRows.make(product: p, alerts: [], members: []).map(\.text), ["Palm oil"])
    }

    func testEnglishWordsFromTheCanonicalId() {
        XCTAssertEqual(IngredientAmount(id: "en:skimmed-milk-powder", text: "x", percent: nil, isStated: false).englishWords, "skimmed milk powder")
        XCTAssertEqual(IngredientAmount(id: "fr:jambon-de-porc-frais", text: "x", percent: nil, isStated: false).englishWords, "jambon de porc frais")
    }
}
