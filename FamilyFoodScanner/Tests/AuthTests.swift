import XCTest
@testable import NutriKin

final class AuthTests: XCTestCase {
    func testEmailIsTrimmedAndLowercased() {
        XCTAssertEqual(AuthStore.normalizedEmail("  Sundar@Example.COM \n"), "sundar@example.com")
    }

    func testBadEmailsAreRejected() {
        for bad in ["", "plain", "a@b", "@example.com", "a@@example.com", "a b@example.com",
                    "a@.com", "a@example.", "a@example.com extra"] {
            XCTAssertNil(AuthStore.normalizedEmail(bad), "\(bad) should be rejected")
        }
    }

    func testCodeKeepsDigitsOnly() {
        XCTAssertEqual(AuthStore.sanitizedCode("123 456"), "123456")
        XCTAssertEqual(AuthStore.sanitizedCode("12-34-56"), "123456")
        XCTAssertEqual(AuthStore.sanitizedCode("abc"), "")
        XCTAssertEqual(AuthStore.sanitizedCode("123456789012"), "1234567890")   // capped
    }

    // create_household / join_household return one row; PostgREST may send
    // it as a bare object or as a one-item array. Both must decode.
    private struct Row: Decodable, Equatable { var id: String; var inviteCode: String }

    func testDecodeRowAcceptsObjectOrArray() throws {
        let object = Data(#"{"id":"a","invite_code":"3F9A01C7"}"#.utf8)
        let array = Data(#"[{"id":"a","invite_code":"3F9A01C7"}]"#.utf8)
        XCTAssertEqual(try Backend.decodeRow(object) as Row, Row(id: "a", inviteCode: "3F9A01C7"))
        XCTAssertEqual(try Backend.decodeRow(array) as Row, Row(id: "a", inviteCode: "3F9A01C7"))
    }

    func testDecodeRowFailsOnEmptyArray() {
        XCTAssertThrowsError(try Backend.decodeRow(Data("[]".utf8)) as Row)
    }
}
