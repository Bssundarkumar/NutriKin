import UIKit
import XCTest
@testable import NutriKin

final class ProductSearchTests: XCTestCase {
    private func piece(_ text: String, y: CGFloat, h: CGFloat, x: CGFloat = 0.1) -> LabelReader.Piece {
        .init(text: text, minX: x, midY: y, height: h)
    }

    // MARK: guessing the name from the front of a pack

    func testBiggestLetteringBecomesTheFirstGuess() {
        let guesses = ProductNameGuesser.guesses(from: [
            piece("NUTELLA", y: 0.70, h: 0.10), piece("Ferrero", y: 0.60, h: 0.06),
            piece("Hazelnut spread with cocoa", y: 0.45, h: 0.03), piece("NET WT 400 g", y: 0.10, h: 0.03),
            piece("www.nutella.com", y: 0.05, h: 0.02), piece("MRP Rs. 350", y: 0.08, h: 0.025),
        ])
        XCTAssertEqual(guesses.first, "Nutella Ferrero")            // brand then product, top to bottom, calmed from CAPS
        XCTAssertTrue(guesses.contains("Nutella"))
        XCTAssertFalse(guesses.joined().lowercased().contains("net wt"))
        XCTAssertFalse(guesses.joined().lowercased().contains("mrp"))
        XCTAssertFalse(guesses.joined().lowercased().contains("www"))
    }

    func testNumbersAndJunkAreNotNames() {
        XCTAssertFalse(ProductNameGuesser.isNameLike("250 g"))
        XCTAssertFalse(ProductNameGuesser.isNameLike("1800 123 4567"))
        XCTAssertFalse(ProductNameGuesser.isNameLike("Best before 6 months"))
        XCTAssertFalse(ProductNameGuesser.isNameLike("ab"))
        XCTAssertTrue(ProductNameGuesser.isNameLike("Parle-G"))
    }

    func testCleaningCalmsShoutingButKeepsMixedCase() {
        XCTAssertEqual(ProductNameGuesser.clean("  NUTELLA  "), "Nutella")
        XCTAssertEqual(ProductNameGuesser.clean("PARLE G BISCUITS"), "Parle G Biscuits")
        XCTAssertEqual(ProductNameGuesser.clean("Oreo Golden"), "Oreo Golden")
    }

    func testNoTextMeansNoGuesses() {
        XCTAssertEqual(ProductNameGuesser.guesses(from: []), [])
        XCTAssertEqual(ProductNameGuesser.guesses(from: [piece("12345", y: 0.5, h: 0.1)]), [])
    }

    // MARK: search results from Open Food Facts

    func testDecodesRealSearchResultsAndDropsUnusableRows() throws {
        let json = #"""
        {"count":268,"products":[
          {"code":"3017620422003","product_name":"Nutella","brands":"Nutella, Ferrero","quantity":"400 g e","image_front_small_url":"https://images.openfoodfacts.org/x.jpg"},
          {"code":"8901719134852","product_name":"Parle G biscuit","brands":"Parle","quantity":""},
          {"code":"123","product_name":"Too short a code"},
          {"code":"3017620425035","product_name":"   "},
          {"code":"not-a-number","product_name":"Bad code"},
          {"product_name":"No code at all"}
        ]}
        """#
        let items = try ProductService.decodeCandidates(Data(json.utf8))
        XCTAssertEqual(items.map(\.code), ["3017620422003", "8901719134852"])
        XCTAssertEqual(items[0].brand, "Nutella")                   // first of the comma-separated brands
        XCTAssertEqual(items[0].quantity, "400 g e")
        XCTAssertNotNil(items[0].imageURL)
        XCTAssertNil(items[1].quantity)                             // blank quantity dropped
        XCTAssertNil(items[1].imageURL)
    }

    func testEmptyOrMissingProductsGivesNoResults() throws {
        XCTAssertEqual(try ProductService.decodeCandidates(Data(#"{"count":0,"products":[]}"#.utf8)), [])
        XCTAssertEqual(try ProductService.decodeCandidates(Data(#"{"count":0}"#.utf8)), [])
    }

    // MARK: end to end: a drawn front-of-pack picture, read with the real text engine

    func testReadsTheProductNameFromAPhotoOfTheFrontOfAPack() async throws {
        let size = CGSize(width: 1200, height: 1600)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            func draw(_ text: String, size pt: CGFloat, y: CGFloat, weight: UIFont.Weight = .bold) {
                (text as NSString).draw(at: CGPoint(x: 80, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: pt, weight: weight), .foregroundColor: UIColor.black])
            }
            draw("NUTELLA", size: 190, y: 250)
            draw("Ferrero", size: 100, y: 500)
            draw("Hazelnut spread with cocoa", size: 52, y: 720, weight: .regular)
            draw("NET WT 400 g", size: 44, y: 1300, weight: .regular)
        }

        guard case .label(let parsed, let guesses) = try await LabelReader.read([image]) else {
            return XCTFail("expected label text, not a barcode")
        }
        XCTAssertNil(parsed.ingredientsText, "a front-of-pack photo has no ingredient list")
        XCTAssertEqual(guesses.first, "Nutella Ferrero", "guesses were \(guesses)")
    }
}
