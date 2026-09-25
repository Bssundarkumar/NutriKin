import Foundation

/// One line of the ingredient list on the result screen.
struct IngredientRow: Identifiable, Equatable {
    enum Kind { case plain, limit, allergen }

    let id: Int
    let text: String
    let kind: Kind
    /// Percent of the product, when known.
    var percent: Double?
    /// True when printed on the label, false when it's Open Food Facts' estimate.
    var isStated = false
    /// A short fact shown when the row is tapped (why it's flagged).
    var note: String?

    /// "13%" when the label states it, "~52%" for an estimate, "<1%" for a trace.
    var amountLabel: String? {
        guard let percent else { return nil }
        if percent < 1 { return isStated ? "\(Self.trim(percent))%" : "<1%" }
        return (isStated ? "" : "~") + "\(Self.trim(percent))%"
    }

    private static func trim(_ v: Double) -> String {
        v.rounded() == v || v >= 10 ? String(Int(v.rounded())) : String(format: "%.1f", v)
    }
}

/// Builds the ingredient rows for a product: names and amounts from Open Food
/// Facts' breakdown when it has one, otherwise the label text split into items.
/// Each row is marked if it's worth limiting or an allergen for someone in the
/// family, with a plain reason.
enum IngredientRows {
    static func make(product: Product, alerts: [IngredientAlert], members: [Member],
                     analyzer: IngredientAnalyzer = IngredientAnalyzer()) -> [IngredientRow] {
        let sources: [(name: String, english: String, percent: Double?, stated: Bool)]
        if !product.ingredientAmounts.isEmpty {
            sources = product.ingredientAmounts.compactMap { a in
                guard let name = IngredientParser.tidy(a.text) ?? IngredientParser.tidy(a.englishWords) else { return nil }
                return (name, a.englishWords, a.percent, a.isStated)
            }
        } else if let raw = product.ingredientsText {
            sources = IngredientParser.items(from: raw).map { ($0, "", nil, false) }
        } else {
            sources = []
        }

        return sources.enumerated().map { index, s in
            // Match on the label word and the English id, so "Sucre" and "sugar" both count.
            let haystack = (s.name + " " + s.english).lowercased()

            let affected = members.filter { m in
                m.allergies.contains { a in a.keywords.contains { haystack.contains($0) } }
                    || m.customAllergyNames.contains { haystack.contains($0.lowercased()) }
            }.map(\.name)
            if !affected.isEmpty {
                return IngredientRow(id: index, text: s.name, kind: .allergen, percent: s.percent, isStated: s.stated,
                                     note: "An allergen for \(affected.joined(separator: ", ")).")
            }
            if let flag = analyzer.flag(for: haystack, among: alerts) {
                return IngredientRow(id: index, text: s.name, kind: .limit, percent: s.percent, isStated: s.stated,
                                     note: "\(flag.title). \(flag.reason)")
            }
            return IngredientRow(id: index, text: s.name, kind: .plain, percent: s.percent, isStated: s.stated)
        }
    }

    /// Roughly how much of the product is made of ingredients worth limiting
    /// or allergens, if the amounts are known. Nil when there are no amounts.
    static func flaggedShare(_ rows: [IngredientRow]) -> Double? {
        guard rows.contains(where: { $0.percent != nil }) else { return nil }
        let share = rows.filter { $0.kind != .plain }.compactMap(\.percent).reduce(0, +)
        return min(share, 100)
    }
}
