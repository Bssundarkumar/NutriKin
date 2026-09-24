import XCTest
@testable import NutriKin

final class InviteLinkTests: XCTestCase {
    func testBuildsAndParsesARoundTrip() throws {
        let url = try XCTUnwrap(InviteLink.url(for: "3F9A01C7"))
        XCTAssertEqual(url.absoluteString, "nutrikin://join?code=3F9A01C7")
        XCTAssertEqual(InviteLink.code(from: url), "3F9A01C7")
    }

    func testParsingIsForgivingAboutCase() throws {
        XCTAssertEqual(InviteLink.code(from: try XCTUnwrap(URL(string: "NutriKin://JOIN?code=3f9a01c7"))), "3F9A01C7")
    }

    func testOtherLinksAreIgnored() throws {
        // The Google sign-in callback shares the scheme and must not look like an invite.
        XCTAssertNil(InviteLink.code(from: try XCTUnwrap(URL(string: "nutrikin://login-callback?code=abcd1234"))))
        XCTAssertNil(InviteLink.code(from: try XCTUnwrap(URL(string: "https://example.com/join?code=3F9A01C7"))))
        XCTAssertNil(InviteLink.code(from: try XCTUnwrap(URL(string: "nutrikin://join"))))
    }

    func testBadCodesAreRejected() throws {
        XCTAssertNil(InviteLink.url(for: "ab"))
        XCTAssertNil(InviteLink.url(for: "has space"))
        XCTAssertNil(InviteLink.url(for: "3F9A01C7&x=1"))
        XCTAssertNil(InviteLink.code(from: try XCTUnwrap(URL(string: "nutrikin://join?code=ab"))))
    }

    func testMessageAlwaysContainsTheCodeAndTheLink() {
        let text = InviteLink.message(familyName: "Kumars", code: "3F9A01C7")
        XCTAssertTrue(text.contains("3F9A01C7"))
        XCTAssertTrue(text.contains("nutrikin://join?code=3F9A01C7"))
        XCTAssertTrue(text.contains("the Kumars family"))
        XCTAssertTrue(InviteLink.message(familyName: "", code: "3F9A01C7").contains("our family"))
    }
}
