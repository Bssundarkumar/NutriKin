import XCTest
@testable import NutriKin

final class ProductPhotoReaderTests: XCTestCase {
    private let reply = """
    ```json
    {"name":" Oat Biscuits ","brand":"Acme","barcode_digits":"8 901234 567890","ingredients":"Wheat flour (48%), sugar, palm oil, milk powder",
     "allergens_statement":"Contains: wheat, milk. May contain: nuts.","serving_size":"30 g","nutrition_basis":"per serving",
     "nutrition":{"calories":135,"sugar_g":6.6,"carbs_g":19.5,"sodium_mg":96,"sat_fat_g":1.8,"protein_g":2.1},"notes":"Bottom of the table is cut off."}
    ```
    """

    func testParsesEveryFieldAndAppendsTheAllergenStatement() throws {
        let r = try ProductPhotoReader.parse(reply)
        XCTAssertEqual(r.name, "Oat Biscuits")
        XCTAssertEqual(r.brand, "Acme")
        XCTAssertEqual(r.barcode, "8901234567890")
        XCTAssertTrue(r.ingredientsText?.contains("Wheat flour (48%)") == true)
        XCTAssertTrue(r.ingredientsText?.contains("May contain: nuts.") == true)     // so allergy checks see it
        XCTAssertEqual(r.nutrition.basis, "per serving (30 g)")
        XCTAssertEqual(r.nutrition.sugarG, 6.6)
        XCTAssertEqual(r.notes, "Bottom of the table is cut off.")
        XCTAssertTrue(r.foundAnything)
    }

    func testNullsAndJunkBecomeNilAndValuesAreClamped() throws {
        let r = try ProductPhotoReader.parse(#"{"name":null,"brand":"null","barcode_digits":"123","ingredients":"","nutrition_basis":"per 100 g","nutrition":{"calories":999999,"sugar_g":-4,"sodium_mg":null}}"#)
        XCTAssertNil(r.name); XCTAssertNil(r.brand); XCTAssertNil(r.barcode); XCTAssertNil(r.ingredientsText)
        XCTAssertEqual(r.nutrition.calories, 3000)
        XCTAssertEqual(r.nutrition.sugarG, 0)
        XCTAssertNil(r.nutrition.sodiumMg)
        XCTAssertEqual(r.nutrition.basis, "per 100 g")
        XCTAssertTrue(r.foundAnything)          // calories were read
        XCTAssertThrowsError(try ProductPhotoReader.parse("I can't read that image."))
    }

    func testAIValuesWinAndOnDeviceReadingFillsTheGaps() throws {
        var ai = try ProductPhotoReader.parse(#"{"name":"X","nutrition_basis":"per 100 g","nutrition":{"calories":100}}"#)
        ai.ingredientsText = nil
        let ocr = ParsedLabel(ingredientsText: "oats, water",
                              nutrition: Nutrition(calories: 999, sugarG: 3, carbsG: nil, sodiumMg: nil, satFatG: nil,
                                                   transFatG: nil, proteinG: nil, basis: "per 100 g"))
        let merged = ProductPhotoReader.merge(ai: ai, ocr: ocr)
        XCTAssertEqual(merged.nutrition.calories, 100)      // AI wins
        XCTAssertEqual(merged.nutrition.sugarG, 3)          // gap filled from the on-device read
        XCTAssertEqual(merged.ingredientsText, "oats, water")
    }

    func testPromptForbidsGuessingAndExplainsSalt() {
        XCTAssertTrue(ProductPhotoReader.systemPrompt.contains("never guess"))
        XCTAssertTrue(ProductPhotoReader.systemPrompt.contains("salt in g x 400"))
    }
}
