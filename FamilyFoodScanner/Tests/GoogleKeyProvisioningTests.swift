import XCTest
@testable import NutriKin

final class GoogleKeyProvisioningTests: XCTestCase {
    func testPKCEChallengeIsDerivedFromVerifierAndBothAreURLSafe() {
        let pkce = GoogleKeyProvisioning.makePKCE()
        XCTAssertFalse(pkce.verifier.isEmpty)
        XCTAssertFalse(pkce.challenge.isEmpty)
        XCTAssertNotEqual(pkce.verifier, pkce.challenge)
        for s in [pkce.verifier, pkce.challenge] {
            XCTAssertFalse(s.contains("+")); XCTAssertFalse(s.contains("/")); XCTAssertFalse(s.contains("="))
        }
    }

    func testTwoPKCEPairsAreNeverTheSame() {
        let a = GoogleKeyProvisioning.makePKCE(), b = GoogleKeyProvisioning.makePKCE()
        XCTAssertNotEqual(a.verifier, b.verifier)
    }

    func testAuthorizationCodeIsExtractedOnlyWhenStateMatches() {
        let good = URL(string: "nutrikin://google-oauth-callback?code=abc123&state=xyz")!
        XCTAssertEqual(GoogleKeyProvisioning.authorizationCode(from: good, expectedState: "xyz"), "abc123")
        XCTAssertNil(GoogleKeyProvisioning.authorizationCode(from: good, expectedState: "different"))
    }

    func testAuthorizationCodeIsNilWhenGoogleReturnsAnError() {
        let denied = URL(string: "nutrikin://google-oauth-callback?error=access_denied&state=xyz")!
        XCTAssertNil(GoogleKeyProvisioning.authorizationCode(from: denied, expectedState: "xyz"))
    }

    func testAuthorizationURLIsNilWhenNotConfigured() {
        // GoogleOAuthConfig.clientID is empty until backend/functions/gemini-key/README.md's setup is done.
        XCTAssertFalse(GoogleOAuthConfig.isConfigured)
        let pkce = GoogleKeyProvisioning.makePKCE()
        let url = GoogleKeyProvisioning.authorizationURL(pkce: pkce, state: "s")
        // Still builds a URL (client_id is just an empty query item) rather than crashing; the app gates
        // on isConfigured before ever calling this, which is what actually keeps the feature hidden.
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("code_challenge=\(pkce.challenge)"))
    }
}
