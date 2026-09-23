import XCTest
@testable import NutriKin

final class IngredientAnalyzerTests: XCTestCase {
    private let analyzer = IngredientAnalyzer()

    private func product(text: String? = nil, ingredientTags: [String] = [], additives: [String] = []) -> Product {
        Product(barcode: "1", name: "Test", brand: nil, imageURL: nil,
                ingredientsText: text, allergenTags: [],
                nutrition: Nutrition(basis: "per 100 g"),
                ingredientTags: ingredientTags, additivesTags: additives)
    }

    private let priya = Member(name: "Priya", conditions: [])
    private let amma = Member(name: "Amma", conditions: [.diabetes])
    private let appa = Member(name: "Appa", conditions: [.hypertension])
    private let kid = Member(name: "Arjun", conditions: [], age: 7)

    private func ids(_ alerts: [IngredientAlert]) -> Set<String> { Set(alerts.map(\.id)) }

    func testPartiallyHydrogenatedOilIsAWarningForEveryone() {
        let a = analyzer.alerts(for: product(text: "flour, partially hydrogenated soybean oil, salt"), members: [priya])
        XCTAssertEqual(ids(a), ["trans-fat"])
        XCTAssertEqual(a.first?.flag.severity, .warning)
        XCTAssertEqual(a.first?.members, [])          // relevant to everyone
    }

    func testFullyHydrogenatedIsNotFlaggedAsTransFat() {
        XCTAssertTrue(analyzer.alerts(for: product(text: "fully hydrogenated palm oil"), members: [priya]).isEmpty)
    }

    func testAddedSugarOnlyShowsForDiabetes() {
        let p = product(text: "wheat flour, sugar, cocoa")
        XCTAssertTrue(analyzer.alerts(for: p, members: [priya, appa]).isEmpty)
        let a = analyzer.alerts(for: p, members: [priya, amma])
        XCTAssertEqual(ids(a), ["added-sugar"])
        XCTAssertEqual(a.first?.members, ["Amma"])
    }

    func testMatchesEnglishTagsWhenLabelTextIsFrench() {
        // Real shape of the Nutella lookup: French text, English canonical tags.
        let p = product(text: "Sucre, huile de palme, NOISETTES 13%, cacao",
                        ingredientTags: ["en:sugar", "en:palm-oil", "en:hazelnut"])
        let cholesterol = Member(name: "Dad", conditions: [.highCholesterol])
        XCTAssertEqual(ids(analyzer.alerts(for: p, members: [amma, cholesterol])),
                       ["added-sugar", "saturated-fat-oils"])
    }

    func testENumbersFromTextAndTags() {
        XCTAssertEqual(ids(analyzer.alerts(for: product(text: "ham, preservative (E 250)"), members: [priya])),
                       ["processed-meat-nitrite"])
        XCTAssertEqual(ids(analyzer.alerts(for: product(additives: ["en:e171"]), members: [priya])),
                       ["titanium-dioxide"])
    }

    func testChildrenColoursOnlyShowForChildren() {
        let p = product(text: "sugar, colour (tartrazine)")
        XCTAssertTrue(analyzer.alerts(for: p, members: [priya]).isEmpty)
        let a = analyzer.alerts(for: p, members: [priya, kid])
        XCTAssertEqual(ids(a), ["artificial-colour-children"])
        XCTAssertEqual(a.first?.members, ["Arjun"])
    }

    func testWholeWordMatchingAvoidsFalsePositives() {
        // "bha" inside another word, "sugar" inside "sugarcane" shouldn't fire on their own
        XCTAssertTrue(analyzer.alerts(for: product(text: "bhaji masala"), members: [priya]).isEmpty)
        XCTAssertTrue(analyzer.alerts(for: product(text: "sugarcane vinegar"), members: [amma]).isEmpty)
    }

    func testWarningsSortBeforeNotes() {
        let a = analyzer.alerts(for: product(text: "aspartame, partially hydrogenated oil"), members: [priya])
        XCTAssertEqual(a.map(\.id), ["trans-fat", "artificial-sweetener"])
    }

    func testCleanProductHasNoAlerts() {
        XCTAssertTrue(analyzer.alerts(for: product(text: "oats, water, salt"), members: [priya, amma, appa, kid]).isEmpty)
    }
}
