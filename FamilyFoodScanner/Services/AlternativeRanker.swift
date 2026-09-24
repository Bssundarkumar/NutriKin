import Foundation

/// A product that suits the family better than the one just scanned.
struct Alternative: Identifiable {
    let product: Product
    /// Why the AI suggested it (AI-suggested alternatives only).
    var why: String? = nil
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
    var minimumGain = 3
    /// A suggestion must also be a decent choice in its own right, not just less bad.
    var minimumScore = 50

    /// The lowest member score, or nil if anyone is blocked by an allergy or there's nobody to score.
    func worstScore(_ product: Product, members: [Member]) -> Int? {
        let scores = engine.scoreFamily(product, members: members)
        guard !scores.isEmpty, !scores.contains(where: \.blockedByAllergy) else { return nil }
        return scores.map(\.score).min()
    }

    func rank(current: Product, candidates: [Product], members: [Member], limit: Int = 3,
              requireSimilarCategory: Bool = true) -> [Alternative] {
        guard !members.isEmpty, let currentNormalized = current.normalizedTo100g else { return [] }
        // A blocked or unscoreable current product counts as 0, so anything safe beats it.
        let baseline = worstScore(currentNormalized, members: members) ?? 0

        let currentTags = Set(ProductService.searchableCategories(current.categoryTags))
        var seenNames = Set<String>()
        var ranked: [Alternative] = []
        for candidate in candidates where candidate.barcode != current.barcode {
            guard !requireSimilarCategory || Self.isSimilar(candidate, toTags: currentTags),
                  Self.hasUsableData(candidate),
                  Self.isComparableEnergy(candidate, to: currentNormalized),
                  let normalized = candidate.normalizedTo100g,
                  let worst = worstScore(normalized, members: members),
                  worst >= max(baseline + minimumGain, minimumScore) else { continue }
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

    /// A rich food (a spread, a biscuit) shouldn't be "improved" by something that is mostly water, like a sauce.
    /// Only applies when the scanned product is energy-dense; drinks and light foods compare freely.
    static func isComparableEnergy(_ candidate: Product, to current: Product) -> Bool {
        guard let base = current.nutrition.calories, base >= 150 else { return true }
        guard let other = candidate.per100g?.calories else { return false }
        return other >= base * 0.4 && other <= base * 2
    }

    static func hasUsableData(_ product: Product) -> Bool {
        guard let text = product.ingredientsText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let n = product.per100g, n.calories != nil else { return false }
        return [n.sugarG, n.sodiumMg, n.satFatG].compactMap { $0 }.count >= 2
    }
}
