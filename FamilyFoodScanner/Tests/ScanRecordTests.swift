import XCTest
@testable import NutriKin

final class ScanRecordTests: XCTestCase {
    func testDecodesARowAsSupabaseReturnsIt() throws {
        let json = """
        {"id":"b9b79608-8c3a-4391-bbc0-b66b2db3505a",
         "household_id":"b7ab18c5-6192-4a8b-aaea-b7cf8f7444db",
         "barcode":"3154230809302","product_name":"Jambon à l'étouffée","brand":"HERTA",
         "image_url":null,
         "results":[{"member_name":"Amma","score":30,"verdict":0,"blocked_by_allergy":false},
                    {"member_name":"Arjun","score":0,"verdict":0,"blocked_by_allergy":true}],
         "alerts":["Nitrite / nitrate preservatives"],
         "scanned_at":"2026-09-23T22:23:53.377814+00:00"}
        """
        let record = try Backend.decoder.decode(ScanRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.productName, "Jambon à l'étouffée")
        XCTAssertNil(record.imageUrl)
        XCTAssertEqual(record.results.map(\.memberName), ["Amma", "Arjun"])
        XCTAssertEqual(record.results[1].blockedByAllergy, true)
        XCTAssertEqual(record.worstVerdict, .avoid)
        XCTAssertEqual(record.alerts, ["Nitrite / nitrate preservatives"])
        // 2026-09-23 22:23:53 UTC
        XCTAssertEqual(record.scannedAt.timeIntervalSince1970, 1_790_202_233.377, accuracy: 0.01)
    }

    func testDecodesTimestampsWithoutFractionalSeconds() throws {
        let json = #"{"id":"b9b79608-8c3a-4391-bbc0-b66b2db3505a","barcode":"1","product_name":"X","results":[],"alerts":[],"scanned_at":"2026-01-02T03:04:05Z"}"#
        XCTAssertNoThrow(try Backend.decoder.decode(ScanRecord.self, from: Data(json.utf8)))
    }

    func testEncodesInsertPayloadWithSnakeCaseKeys() throws {
        struct Payload: Encodable { var householdId: UUID; var productName: String; var results: [ScanRecord.Result] }
        let payload = Payload(householdId: UUID(), productName: "X",
                              results: [.init(memberName: "A", score: 90, verdict: 2, blockedByAllergy: false)])
        let object = try JSONSerialization.jsonObject(with: Backend.encoder.encode(payload)) as! [String: Any]
        XCTAssertNotNil(object["household_id"])
        XCTAssertNotNil(object["product_name"])
        let first = (object["results"] as! [[String: Any]])[0]
        XCTAssertEqual(first["member_name"] as? String, "A")
        XCTAssertEqual(first["blocked_by_allergy"] as? Bool, false)
    }

    func testWorstVerdictIsNilWithNoResults() {
        XCTAssertNil(ScanRecord(barcode: "1", productName: "X", results: [], alerts: []).worstVerdict)
    }
}
