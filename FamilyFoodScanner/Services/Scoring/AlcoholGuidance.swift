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

    /// Well-known liquor/beer/wine brands whose name alone doesn't contain a generic term above
    /// (e.g. "Grey Goose" never says "vodka"). Open Food Facts frequently has no ingredients or
    /// category tags for spirits, so brand-name matching is the only signal available for these.
    /// Not exhaustive - a best-effort backstop, not a substitute for better product data.
    static let knownBrands: [String] = [
        "grey goose", "absolut", "smirnoff", "titos", "tito's", "ketel one", "belvedere", "svedka",
        "jack daniels", "jack daniel's", "jim beam", "johnnie walker", "jameson", "crown royal",
        "makers mark", "maker's mark", "wild turkey", "chivas regal", "glenlivet", "glenfiddich",
        "macallan", "bacardi", "captain morgan", "malibu", "jose cuervo", "patron", "don julio",
        "hennessy", "remy martin", "courvoisier", "baileys", "kahlua", "grand marnier", "cointreau",
        "jagermeister", "jägermeister", "bombay sapphire", "tanqueray", "beefeater", "hendricks",
        "hendrick's", "budweiser", "heineken", "corona", "guinness", "stella artois", "coors",
        "miller lite", "modelo", "dos equis", "yuengling", "kingfisher beer", "moet", "moët",
        "veuve clicquot", "dom perignon", "dom pérignon", "barefoot wine", "yellow tail wine",
    ]

    static func isAlcoholic(_ product: Product) -> Bool {
        let text = PregnancyGuidance.searchText(for: product)
        let range = NSRange(text.startIndex..., in: text)
        return (terms + knownBrands).contains { IngredientAnalyzer.regex(for: $0)?.firstMatch(in: text, range: range) != nil }
    }
}
