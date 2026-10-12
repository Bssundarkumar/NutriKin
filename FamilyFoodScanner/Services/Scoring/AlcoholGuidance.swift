import Foundation

/// Detects alcoholic products/ingredients, independent of any one member's conditions. Used by
/// `ScoringEngine` as a hard safety rule (never "okay" for a child, never silently "good" for anyone),
/// and shared with `PregnancyGuidance` so the two term lists can't drift apart.
enum AlcoholGuidance {
    static let terms: [String] = [
        "alcohol", "ethanol", "beer", "liqueur", "rum", "whisky", "whiskey", "brandy", "vodka",
        "red wine", "white wine", "rice wine", "cooking wine", "alcoholic beverage", "gin", "tequila",
        "champagne", "sake", "mead", "ale", "lager", "stout", "port wine", "sherry", "vermouth",
        // Open Food Facts category names are plural
        "alcoholic beverages", "beers", "wines", "spirits", "liqueurs", "cider", "ciders", "cocktails",
    ]

    static func isAlcoholic(_ product: Product) -> Bool {
        let text = PregnancyGuidance.searchText(for: product)
        let range = NSRange(text.startIndex..., in: text)
        return terms.contains { IngredientAnalyzer.regex(for: $0)?.firstMatch(in: text, range: range) != nil }
    }
}
