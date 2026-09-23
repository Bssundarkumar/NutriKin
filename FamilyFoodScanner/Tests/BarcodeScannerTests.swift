import XCTest
@testable import NutriKin

final class BarcodeScannerTests: XCTestCase {
    private func code(_ s: String) -> String? { BarcodeScannerView.productCode(from: s) }

    func testPlainBarcodeIsAccepted() {
        XCTAssertEqual(code("3017620422003"), "3017620422003")
        XCTAssertEqual(code("  96385074 \n"), "96385074")
    }

    func testGS1DigitalLinkQRYieldsTheGTIN() {
        XCTAssertEqual(code("https://id.gs1.org/01/03017620422003"), "03017620422003")
        XCTAssertEqual(code("https://example.com/01/3017620422003/10/LOT7?x=1"), "3017620422003")
    }

    func testOrdinaryQRCodesAreIgnored() {
        XCTAssertNil(code("https://www.nestle.com/brands"))
        XCTAssertNil(code("WIFI:S:home;T:WPA;P:secret;;"))
        XCTAssertNil(code("12345"))               // too short to be a product code
        XCTAssertNil(code("12345678901234567"))   // too long
    }
}
