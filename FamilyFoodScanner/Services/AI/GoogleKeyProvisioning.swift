import Foundation
import CryptoKit
import AuthenticationServices

/// Lets a person get a Gemini key without visiting Google AI Studio themselves: they sign in with Google in a
/// secure system browser (their password never touches NutriKin), and a server function creates a Gemini API
/// key inside their OWN Google Cloud project and hands it back to this phone, where it's stored exactly like a
/// manually pasted key. BETA: needs one-time setup in Google Cloud Console (see docs/google-oauth-setup.md) and
/// only works for test accounts you've added there until Google finishes reviewing the app.
enum GoogleOAuthConfig {
    /// Fill these in after completing docs/google-oauth-setup.md. Left empty on purpose: the feature stays
    /// hidden in the app until they're set, so nothing here can break anyone before it's configured.
    static let clientID = ""
    static let redirectURI = "nutrikin://google-oauth-callback"
    static let scope = "https://www.googleapis.com/auth/cloud-platform"
    static var isConfigured: Bool { !clientID.isEmpty }
}

enum GoogleKeyProvisioning {
    struct PKCE { let verifier: String; let challenge: String }

    /// A random verifier and its SHA-256 challenge, per the OAuth PKCE spec (RFC 7636). PKCE means even if the
    /// authorization code were somehow intercepted in transit, it can't be redeemed without this verifier, which
    /// never leaves the phone until the final token exchange.
    static func makePKCE() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64EncodedString().urlSafe
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().urlSafe
        return PKCE(verifier: verifier, challenge: challenge)
    }

    static func authorizationURL(pkce: PKCE, state: String) -> URL? {
        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // Always shows the consent screen and issues a refresh token; without this a returning
            // test user can silently skip seeing what they're approving.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return comps.url
    }

    /// Pulls the one-time authorization code out of Google's redirect, and checks `state` matches what this
    /// session sent, so a stray or forged callback can't be mistaken for this person's own sign-in.
    static func authorizationCode(from callback: URL, expectedState: String) -> String? {
        guard let comps = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              comps.queryItems?.first(where: { $0.name == "error" }) == nil,
              comps.queryItems?.first(where: { $0.name == "state" })?.value == expectedState else { return nil }
        return comps.queryItems?.first(where: { $0.name == "code" })?.value
    }

    /// Asks NutriKin's server function to turn that one-time code into a real Gemini key in the person's own
    /// Google Cloud project. The code and verifier are sent once, over HTTPS, and never stored on the phone;
    /// only the resulting Gemini key comes back, which is then saved exactly like a manually pasted one.
    private struct KeyRequest: Encodable { var code: String, codeVerifier: String, redirectUri: String }
    private struct KeyResponse: Decodable { var apiKey: String? }

    static func requestKey(code: String, codeVerifier: String) async throws -> String {
        do {
            let response: KeyResponse = try await Backend.client.functions.invoke(
                "gemini-key",
                options: .init(body: KeyRequest(code: code, codeVerifier: codeVerifier, redirectUri: GoogleOAuthConfig.redirectURI))
            )
            guard let key = response.apiKey, !key.isEmpty else { throw AIFailure(message: "Google didn't return a key. Please try again, or add one yourself.") }
            return key
        } catch let failure as AIFailure {
            throw failure
        } catch {
            throw AIFailure(message: "Couldn't get a key from Google. Please try again, or add one yourself.")
        }
    }
}

private extension String {
    /// Base64 that's safe inside a URL: no padding, no `+`/`/`.
    var urlSafe: String { replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

/// Drives Google's sign-in page in a secure system browser (Safari's own sandboxed view: NutriKin never sees
/// what's typed there) and hands back the redirect URL once the person finishes or cancels.
@MainActor
final class GoogleSignInPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    func run(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "nutrikin") { callback, error in
                if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: error ?? AIFailure(message: "Sign-in was cancelled.")) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true   // no shared cookies with Safari; a clean sign-in each time
            session.start()
        }
    }
}
