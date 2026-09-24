import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Supabase

/// Email sign-in with a 6-digit code (no links or redirects to configure).
/// Flow: `sendCode(to:)` emails a code, `verify(code:)` exchanges it for a
/// session, and the SDK keeps that session in the Keychain across launches.
@MainActor
@Observable
final class AuthStore {
    enum State: Equatable {
        /// Checking for a saved session (or refreshing an expired one).
        case loading
        case signedOut
        case signedIn(email: String)
    }

    private(set) var state: State = .loading
    /// The address a code was just sent to; non-nil means "enter the code".
    private(set) var pendingEmail: String?
    var isWorking = false
    var errorMessage: String?

    private var auth: AuthClient { Backend.client.auth }
    init() {
        // Lives as long as the app; exits on its own if the store is released.
        Task { [weak self] in
            for await (event, session) in Backend.client.auth.authStateChanges {
                guard let self else { return }
                self.apply(event: event, session: session)
            }
        }
    }

    private func apply(event: AuthChangeEvent, session: Session?) {
        if let session {
            // An expired stored session is being refreshed; wait for that
            // result instead of flashing the sign-in screen.
            state = session.isExpired ? .loading : .signedIn(email: session.user.email ?? "")
        } else {
            state = .signedOut
        }
    }

    // MARK: - Sign in

    func sendCode(to rawEmail: String) async {
        guard let email = Self.normalizedEmail(rawEmail) else {
            errorMessage = "That doesn't look like an email address."
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await auth.signInWithOTP(email: email, shouldCreateUser: true)
            pendingEmail = email
        } catch {
            errorMessage = "Couldn't send the code. \(error.localizedDescription)"
        }
    }

    func verify(code rawCode: String) async {
        guard let email = pendingEmail else { return }
        let code = Self.sanitizedCode(rawCode)
        guard code.count >= 6 else {
            errorMessage = "Enter the full code from the email."
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await auth.verifyOTP(email: email, token: code, type: .email)
            pendingEmail = nil          // the auth listener flips `state` to signedIn
        } catch {
            errorMessage = "That code didn't work. Check it and try again, or request a new one."
        }
    }

    /// Where Google sends the user back to the app. Must also be listed under
    /// Supabase > Authentication > URL Configuration > Redirect URLs.
    static let oauthRedirect = URL(string: "nutrikin://login-callback")!

    /// Google sign-in in the system browser sheet. Needs the Google provider
    /// enabled in Supabase.
    func signInWithGoogle() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await auth.signInWithOAuth(provider: .google, redirectTo: Self.oauthRedirect)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // The user closed the sheet; nothing to report.
        } catch {
            errorMessage = "Couldn't sign in with Google. \(error.localizedDescription)"
        }
    }

    /// Finishes native Sign in with Apple: hands Apple's identity token to
    /// Supabase. `nonce` is the raw value whose SHA-256 was sent to Apple.
    func handleApple(_ result: Result<ASAuthorization, Error>, nonce: String) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "Couldn't sign in with Apple. \(error.localizedDescription)"
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let idToken = String(data: data, encoding: .utf8) else {
                errorMessage = "Apple didn't return a sign-in token. Please try again."
                return
            }
            isWorking = true
            errorMessage = nil
            defer { isWorking = false }
            do {
                try await auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
            } catch {
                errorMessage = "Couldn't sign in with Apple. \(error.localizedDescription)"
            }
        }
    }

    /// Password sign-in, used for the App Review demo account. Regular users
    /// sign in with an emailed code.
    func signIn(email rawEmail: String, password: String) async {
        guard let email = Self.normalizedEmail(rawEmail), !password.isEmpty else {
            errorMessage = "Enter your email and password."
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await auth.signIn(email: email, password: password)
        } catch {
            errorMessage = "That email and password didn't work."
        }
    }

    /// Permanently deletes the account and any family only this person belonged to.
    /// Returns true on success (the auth listener then shows the sign-in screen).
    func deleteAccount() async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await Backend.client.rpc("delete_my_account").execute()
            try? await auth.signOut(scope: .local)
            return true
        } catch {
            errorMessage = "Couldn't delete the account. \(error.localizedDescription)"
            return false
        }
    }

    /// Back to the email step (wrong address, or the code never arrived).
    func startOver() {
        pendingEmail = nil
        errorMessage = nil
    }

    func signOut() async {
        do {
            try await auth.signOut()
        } catch {
            errorMessage = "Couldn't sign out. \(error.localizedDescription)"
        }
    }

    // MARK: - Input cleanup (pure, unit-tested)

    nonisolated static func normalizedEmail(_ raw: String) -> String? {
        let e = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = e.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."), !e.contains(" ") else { return nil }
        return e
    }

    /// Keeps digits only, so pasted codes with spaces or dashes still work.
    nonisolated static func sanitizedCode(_ raw: String) -> String {
        String(raw.filter(\.isNumber).prefix(10))
    }

    // MARK: - Sign in with Apple nonce (pure, unit-tested)

    nonisolated static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars.randomElement(using: &generator)! })
    }

    nonisolated static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
