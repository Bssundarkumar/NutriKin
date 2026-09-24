import CoreImage.CIFilterBuiltins
import UIKit
import XCTest
@testable import NutriKin

/// These run Apple's real Vision engine on pictures drawn in the test.
final class LabelReaderTests: XCTestCase {
    private func labelImage() -> UIImage {
        let size = CGSize(width: 1400, height: 1500)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            let font = UIFont.systemFont(ofSize: 46, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
            var y: CGFloat = 60
            for line in ["INGREDIENTS: Sugar, palm oil, hazelnuts (13%),",
                         "skimmed milk powder, lecithins (soy), vanillin.",
                         "Contains: hazelnuts, milk, soy."] {
                (line as NSString).draw(at: CGPoint(x: 60, y: y), withAttributes: attrs); y += 80
            }
            y += 60
            ("Nutrition per 100 g" as NSString).draw(at: CGPoint(x: 60, y: y), withAttributes: attrs); y += 90
            // A two-column table: the name and its value are separate pieces of text.
            for (name, value) in [("Energy", "539 kcal"), ("Saturates", "10.6 g"), ("Carbohydrate", "57.5 g"),
                                  ("Sugars", "56.3 g"), ("Protein", "6.3 g"), ("Salt", "0.11 g")] {
                (name as NSString).draw(at: CGPoint(x: 60, y: y), withAttributes: attrs)
                (value as NSString).draw(at: CGPoint(x: 900, y: y), withAttributes: attrs)
                y += 80
            }
        }
    }

    private func barcodeImage(_ digits: String) -> UIImage {
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = Data(digits.utf8)
        filter.quietSpace = 20
        let scaled = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 5, y: 260 / filter.outputImage!.extent.height))
        let cg = CIContext().createCGImage(scaled, from: scaled.extent)!
        return UIImage(cgImage: cg)
    }

    func testReadsIngredientsAndNutritionFromAPhotoOfALabel() async throws {
        let outcome = try await LabelReader.read([labelImage()])
        guard case .label(let parsed) = outcome else { return XCTFail("expected a label, got \(outcome)") }

        let text = try XCTUnwrap(parsed.ingredientsText).lowercased()
        XCTAssertTrue(text.contains("sugar"), text)
        XCTAssertTrue(text.contains("palm oil"), text)
        XCTAssertTrue(text.contains("soy"), text)                     // from the ingredients and the allergen line

        XCTAssertEqual(parsed.nutrition.basis, "per 100 g")
        XCTAssertEqual(parsed.nutrition.calories, 539)
        XCTAssertEqual(parsed.nutrition.sugarG, 56.3)
        XCTAssertEqual(parsed.nutrition.satFatG, 10.6)
        XCTAssertEqual(parsed.nutrition.proteinG, 6.3)
        XCTAssertEqual(parsed.nutrition.sodiumMg ?? 0, 44, accuracy: 1)   // 0.11 g salt x 400
    }

    func testAFoundBarcodeWinsOverReadingText() async throws {
        #if targetEnvironment(simulator)
        // Vision's barcode detector returns nothing on the simulator, even for a
        // perfect QR code. This needs a real device to run.
        throw XCTSkip("Barcode detection isn't available in the iOS Simulator.")
        #endif
        let outcome = try await LabelReader.read([labelImage(), barcodeImage("3017620422003")])
        XCTAssertEqual(outcome, .barcode("3017620422003"))
    }

    func testAPhotoWithNothingUsefulIsReportedHonestly() async throws {
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 800)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 800))
        }
        guard case .label(let parsed) = try await LabelReader.read([blank]) else { return XCTFail("expected a label") }
        XCTAssertFalse(parsed.foundAnything)
    }

    // MARK: pure row grouping

    func testPiecesOnTheSameLineJoinLeftToRight() {
        let pieces: [LabelReader.Piece] = [
            .init(text: "539 kcal", minX: 0.7, midY: 0.50, height: 0.03),
            .init(text: "Ingredients: sugar", minX: 0.1, midY: 0.80, height: 0.03),
            .init(text: "Energy", minX: 0.1, midY: 0.505, height: 0.03),
            .init(text: "Protein", minX: 0.1, midY: 0.40, height: 0.03),
        ]
        XCTAssertEqual(LabelReader.groupRows(pieces), ["Ingredients: sugar", "Energy 539 kcal", "Protein"])
    }
}
