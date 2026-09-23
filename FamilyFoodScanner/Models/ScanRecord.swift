import Foundation

/// A saved scan: the product plus each family member's verdict at that moment.
struct ScanRecord: Identifiable, Codable, Hashable {
    struct Result: Codable, Hashable {
        var memberName: String
        var score: Int
        /// `Verdict.rawValue`: 0 avoid, 1 caution, 2 okay.
        var verdict: Int
        var blockedByAllergy: Bool

        var verdictValue: Verdict { Verdict(rawValue: verdict) ?? .caution }
    }

    var id = UUID()
    var barcode: String
    var productName: String
    var brand: String?
    var imageUrl: String?
    var results: [Result]
    /// Titles of the ingredient alerts that applied.
    var alerts: [String]
    var scannedAt = Date()

    /// The worst verdict across the family, for the row's headline colour.
    var worstVerdict: Verdict? { results.map(\.verdictValue).min() }
}
