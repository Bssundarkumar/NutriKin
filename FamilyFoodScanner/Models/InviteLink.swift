import Foundation

/// Builds and reads the family invite link, `nutrikin://join?code=ABCD1234`.
///
/// It's a custom-scheme link, so it only opens the app on phones that have
/// NutriKin installed (a web link that also works for people without the app
/// needs a paid Apple developer account). The share message therefore always
/// includes the plain code as well.
enum InviteLink {
    static let scheme = "nutrikin"
    static let host = "join"

    /// Codes are short letters and digits, e.g. "3F9A01C7".
    static func isValid(code: String) -> Bool {
        (4...12).contains(code.count) && code.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    static func url(for code: String) -> URL? {
        guard isValid(code: code) else { return nil }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        parts.queryItems = [URLQueryItem(name: "code", value: code)]
        return parts.url
    }

    /// The invite code inside a link, or nil for any other URL (including the
    /// Google sign-in callback, which shares this scheme).
    static func code(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == host,
              let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
        else { return nil }
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return isValid(code: code) ? code : nil
    }

    /// The text people send: works even if the link isn't tappable.
    static func message(familyName: String, code: String) -> String {
        let name = familyName.isEmpty ? "our family" : "the \(familyName) family"
        var text = """
        Join \(name) on NutriKin so we can check groceries for everyone's health.

        1. Install NutriKin and sign in
        2. Choose "Join with a code" and enter: \(code)
        """
        if let link = url(for: code) {
            text += "\n\nOr, if NutriKin is already installed, open: \(link.absoluteString)"
        }
        return text
    }
}
