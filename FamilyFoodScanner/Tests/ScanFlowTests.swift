import XCTest
@testable import NutriKin

final class ScanFlowTests: XCTestCase {
    // MARK: tap-to-focus region

    func testRegionIsCentredOnTheTap() {
        let r = BarcodeScannerView.regionRect(around: CGPoint(x: 200, y: 400), in: CGSize(width: 400, height: 800))
        XCTAssertEqual(r.midX, 200, accuracy: 0.5)
        XCTAssertEqual(r.midY, 400, accuracy: 0.5)
        XCTAssertEqual(r.width, 220, accuracy: 0.5)          // 55% of the short side
        XCTAssertEqual(r.height, r.width)
    }

    func testRegionStaysInsideTheViewNearEdges() {
        let size = CGSize(width: 400, height: 800)
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 800), CGPoint(x: 5, y: 790), CGPoint(x: 399, y: 3)] {
            let r = BarcodeScannerView.regionRect(around: point, in: CGRect(origin: .zero, size: size).size)
            XCTAssertGreaterThanOrEqual(r.minX, 0); XCTAssertGreaterThanOrEqual(r.minY, 0)
            XCTAssertLessThanOrEqual(r.maxX, size.width + 0.001); XCTAssertLessThanOrEqual(r.maxY, size.height + 0.001)
        }
    }

    // MARK: what gets saved to history

    func testHistoryPayloadHasEveryMembersVerdictAndTheAlerts() throws {
        let product = Product(barcode: "3154230809302", name: "Jambon", brand: "HERTA", imageURL: nil,
                              ingredientsText: "porc, sel, nitrite de sodium", allergenTags: [],
                              nutrition: Nutrition(basis: "per 100 g"))
        let amma = Member(name: "Amma", conditions: [.diabetes])
        let arjun = Member(name: "Arjun", conditions: [.customAllergy("porc")])
        let household = UUID()

        let payload = HistoryStore.makePayload(product: product, householdId: household, members: [amma, arjun])
        XCTAssertEqual(Set(payload.results.map(\.memberName)), ["Amma", "Arjun"])
        XCTAssertTrue(payload.results.first { $0.memberName == "Arjun" }!.blockedByAllergy)
        XCTAssertEqual(payload.alerts, ["Nitrite / nitrate preservatives"])

        // The JSON keys must match the `scans` table columns exactly.
        let object = try JSONSerialization.jsonObject(with: Backend.encoder.encode(payload)) as! [String: Any]
        XCTAssertEqual(Set(object.keys), ["household_id", "barcode", "product_name", "brand", "results", "alerts"])
        XCTAssertEqual(object["household_id"] as? String, household.uuidString)
        let first = (object["results"] as! [[String: Any]])[0]
        XCTAssertEqual(Set(first.keys), ["member_name", "score", "verdict", "blocked_by_allergy"])
    }

    func testPayloadWorksWithAnEmptyFamily() {
        let product = Product(barcode: "1", name: "X", brand: nil, imageURL: nil, ingredientsText: nil,
                              allergenTags: [], nutrition: Nutrition(basis: "per 100 g"))
        let payload = HistoryStore.makePayload(product: product, householdId: UUID(), members: [])
        XCTAssertTrue(payload.results.isEmpty)
    }
}

final class AutoZoomTests: XCTestCase {
    func testSearchCyclesThroughTheLevelsAndWrapsAround() {
        XCTAssertEqual(AutoZoom.next(after: 1), 2)
        XCTAssertEqual(AutoZoom.next(after: 2), 3)
        XCTAssertEqual(AutoZoom.next(after: 3), 1)
    }

    func testAnInBetweenPinchZoomStillAdvancesSensibly() {
        XCTAssertEqual(AutoZoom.next(after: 1.4), 2)     // pinched a bit past 1x
        XCTAssertEqual(AutoZoom.next(after: 2.6), 3)
        XCTAssertEqual(AutoZoom.next(after: 7), 1)       // beyond the top: start over
        XCTAssertEqual(AutoZoom.next(after: 0.5), 1)
    }

    func testStepInStopsAtTheTop() {
        XCTAssertEqual(AutoZoom.stepIn(from: 1), 2)
        XCTAssertEqual(AutoZoom.stepIn(from: 1.6), 2)
        XCTAssertEqual(AutoZoom.stepIn(from: 3), 3)
        XCTAssertEqual(AutoZoom.stepIn(from: 10), 3)
    }

    func testTapMapsToTheRightPlaceOnTheSensor() {
        let view = CGSize(width: 400, height: 800)
        // Centre of the view is the centre of the sensor.
        let c = CameraFocus.sensorPoint(forViewPoint: CGPoint(x: 200, y: 400), viewSize: view)
        XCTAssertEqual(c.x, 0.5, accuracy: 0.001); XCTAssertEqual(c.y, 0.5, accuracy: 0.001)
        // Top of the screen is one end of the sensor's long edge, bottom the other.
        XCTAssertEqual(CameraFocus.sensorPoint(forViewPoint: CGPoint(x: 200, y: 0), viewSize: view).x, 0, accuracy: 0.001)
        XCTAssertEqual(CameraFocus.sensorPoint(forViewPoint: CGPoint(x: 200, y: 800), viewSize: view).x, 1, accuracy: 0.001)
        // Screen sides are cropped, so they map inside the sensor, not to its edge.
        let left = CameraFocus.sensorPoint(forViewPoint: CGPoint(x: 0, y: 400), viewSize: view)
        let right = CameraFocus.sensorPoint(forViewPoint: CGPoint(x: 400, y: 400), viewSize: view)
        XCTAssertGreaterThan(left.y, right.y)            // flipped axis
        XCTAssertLessThan(left.y, 1); XCTAssertGreaterThan(right.y, 0)
    }

    func testDegenerateViewSizeFallsBackToTheCentre() {
        let p = CameraFocus.sensorPoint(forViewPoint: .zero, viewSize: .zero)
        XCTAssertEqual(p, CGPoint(x: 0.5, y: 0.5))
    }
}
