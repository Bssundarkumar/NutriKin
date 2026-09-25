import XCTest
@testable import NutriKin

final class GrowthTests: XCTestCase {
    private func m(_ day: String, h: Double? = nil, w: Double? = nil) -> BodyMeasurement {
        BodyMeasurement(memberId: UUID(), measuredOn: day, heightCm: h, weightKg: w)
    }
    func testChangeAndLatest() {
        let list = [m("2026-03-01", h: 120, w: 24), m("2026-09-01", h: 126, w: 26.5), m("2026-06-01", w: 25)]
        XCTAssertEqual(GrowthMath.weightChange(list) ?? 0, 2.5, accuracy: 0.001)
        XCTAssertEqual(GrowthMath.heightChange(list) ?? 0, 6, accuracy: 0.001)
        XCTAssertEqual(GrowthMath.latest(list)?.measuredOn, "2026-09-01")
        XCTAssertNil(GrowthMath.weightChange([m("2026-03-01", w: 24)]))
    }
    func testValidationRejectsTypos() {
        XCTAssertTrue(GrowthMath.isValid(heightCm: 150, weightKg: 50))
        XCTAssertFalse(GrowthMath.isValid(heightCm: 15, weightKg: nil))
        XCTAssertFalse(GrowthMath.isValid(heightCm: nil, weightKg: 900))
        XCTAssertFalse(GrowthMath.isValid(heightCm: nil, weightKg: nil))
    }
    func testDateRoundTripAndBMI() {
        let d = BodyMeasurement.formatter.date(from: "2026-09-25")!
        XCTAssertEqual(BodyMeasurement.day(d), "2026-09-25")
        XCTAssertEqual(GrowthMath.bmi(m("2026-09-25", h: 180, w: 81)) ?? 0, 25, accuracy: 0.01)
    }
    func testDecodesFromSnakeCaseRow() throws {
        let json = #"{"id":"\#(UUID().uuidString)","member_id":"\#(UUID().uuidString)","measured_on":"2026-09-25","height_cm":130.5,"weight_kg":28}"#
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let row = try dec.decode(BodyMeasurement.self, from: Data(json.utf8))
        XCTAssertEqual(row.heightCm, 130.5); XCTAssertEqual(row.measuredOn, "2026-09-25")
    }
}
