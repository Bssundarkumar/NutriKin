import Foundation

/// Guesses a product's name from a photo of the front of the pack: the biggest
/// lettering is nearly always the brand and product name. The guesses only
/// pre-fill a search box; the person always confirms the match.
enum ProductNameGuesser {
    /// Text that's on packs but isn't the name.
    private static let noise = #"(?i)net\s*(wt|weight|qty|quantity|content)|\bmrp\b|price|best\s*before|use\s*by|\bexp\b|batch|ingredients?|nutrition|per\s*100|www\.|\.com|@|fssai|non[- ]?veg|\bveg\b|vegetarian|manufactured|marketed|customer|toll|scan|barcode|kcal|servings?|pack of|made in|\bdate\b|store in|keep|sugar free|no added|fresh|new\b"#

    /// Up to `limit` distinct guesses, best first: the two biggest pieces of
    /// text read top to bottom (brand then product), then each big piece alone.
    static func guesses(from pieces: [LabelReader.Piece], limit: Int = 4) -> [String] {
        let usable = pieces.filter { isNameLike($0.text) }
        guard !usable.isEmpty else { return [] }
        let bySize = usable.sorted { $0.height > $1.height }

        var out: [String] = []
        let topTwo = bySize.prefix(2)
        if topTwo.count == 2 {
            out.append(topTwo.sorted { $0.midY > $1.midY }.map { clean($0.text) }.joined(separator: " "))
        }
        for piece in bySize.prefix(4) { out.append(clean(piece.text)) }

        var seen = Set<String>()
        return out.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(limit).map { $0 }
    }

    static func isNameLike(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = t.filter(\.isLetter).count
        guard letters >= 3, t.count <= 40 else { return false }
        guard Double(letters) / Double(t.count) >= 0.6 else { return false }      // mostly letters, not "250 g" or a phone number
        return t.range(of: noise, options: .regularExpression) == nil
    }

    /// Collapses spaces and calms SHOUTING ("NUTELLA" -> "Nutella") so the search box reads naturally.
    static func clean(_ text: String) -> String {
        let t = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,;:-–—*®™©"))
        guard t.filter(\.isLetter).allSatisfy(\.isUppercase) else { return t }
        return t.lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
