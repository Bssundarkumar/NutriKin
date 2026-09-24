import Foundation

/// A product that suits the family better than the one just scanned.
struct Alternative: Identifiable {
    let product: Product
    /// The lowest score any family member gets for it (per 100 g).
    let worstScore: Int
    var id: String { product.barcode }
}

/// Picks "try this instead" suggestions. Everything is compared on the same
/// per-100 g basis, and a suggestion must be safe for every member: nothing
/// that trips an allergy, nothing with a missing ingredient list or missing
/// nutrition (unknown data must never look like a good score).
struct AlternativeRanker {
    var engine = ScoringEngine()
    /// How many points better than the scanned product an alternative must be.
    var minimumGain = 5

    /// The lowest member score, or nil if anyone is blocked by an allergy or there's nobody to score.
    func worstScore(_ product: Product, members: [Member]) -> Int? {
        let scores = engine.scoreFamily(product, members: members)
        guard !scores.isEmpty, !scores.contains(where: \.blockedByAllergy) else { return nil }
        return scores.map(\.score).min()
    }

    func rank(current: Product, candidates: [Product], members: [Member], limit: Int = 3) -> [Alternative] {
        guard !members.isEmpty, let currentNormalized = current.normalizedTo100g else { return [] }
        // A blocked or unscoreable current product counts as 0, so anything safe beats it.
        let baseline = worstScore(currentNormalized, members: members) ?? 0

        let currentTags = Set(ProductService.searchableCategories(current.categoryTags))
        var seenNames = Set<String>()
        var ranked: [Alternative] = []
        for candidate in candidates where candidate.barcode != current.barcode {
            guard Self.isSimilar(candidate, toTags: currentTags),
                  Self.hasUsableData(candidate),
                  let normalized = candidate.normalizedTo100g,
                  let worst = worstScore(normalized, members: members),
                  worst >= baseline + minimumGain else { continue }
            let key = (candidate.brand ?? "").lowercased() + "|" + candidate.name.lowercased()
            guard seenNames.insert(key).inserted else { continue }
            ranked.append(Alternative(product: candidate, worstScore: worst))
        }
        return Array(ranked.sorted { $0.worstScore > $1.worstScore }.prefix(limit))
    }

    /// Open Food Facts files some odd products under broad categories, so a
    /// suggestion must share at least half of the scanned product's category tags.
    static func isSimilar(_ candidate: Product, toTags tags: Set<String>) -> Bool {
        guard !tags.isEmpty else { return false }
        let shared = tags.intersection(ProductService.searchableCategories(candidate.categoryTags)).count
        return shared >= 2 && Double(shared) / Double(tags.count) >= 0.5
    }

    static func hasUsableData(_ product: Product) -> Bool {
        guard let text = product.ingredientsText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let n = product.per100g, n.calories != nil else { return false }
        return [n.sugarG, n.sodiumMg, n.satFatG].compactMap { $0 }.count >= 2
    }
}
