import Foundation

/// Child-specific safety checks, independent of any condition the member has — the same shape as
/// `PregnancyGuidance`, but keyed off age instead of a condition. Shares term lists with
/// `PregnancyGuidance` and `AlcoholGuidance` where the same risk applies to both audiences (caffeine,
/// mercury fish), so the lists can't drift apart.
///
/// `Member.age` is whole years only — there's no month-level precision in the data model — so "infant"
/// here means age 0 (under 1 year old entered), the closest this data can get to "under 12 months".
enum ChildSafetyGuidance {
    static let caffeineTerms = ["caffeine", "guarana", "energy drink", "coffee", "yerba mate", "matcha"]
    static let mercuryFishTerms = ["shark", "swordfish", "king mackerel", "marlin", "tilefish", "orange roughy"]
    static let honeyTerms = ["honey", "raw honey", "wildflower honey", "manuka honey", "honeycomb"]
    static let juiceTerms = ["juice", "fruit juice", "100% juice", "apple juice", "orange juice", "grape juice", "juice drink", "juice box"]
    /// Cured/processed meats carry nitrates or nitrites that healthy adults process fine, but a very
    /// young infant's gut can convert into a form that interferes with how their blood carries oxygen
    /// (methemoglobinemia) — a specific infant risk, distinct from "processed meat isn't great" advice.
    static let curedMeatTerms = ["hot dog", "hot dogs", "frankfurter", "sausage", "salami", "bologna", "deli meat", "lunch meat", "bacon", "ham", "pepperoni", "nitrate", "nitrite", "sodium nitrite", "sodium nitrate"]
    /// The classic choking-hazard list pediatric guidance (AAP, NHS) names by shape, not nutrition —
    /// round, firm, or sticky enough to block a young child's airway whole.
    static let chokingHazardTerms = [
        "whole grape", "whole grapes", "whole cherry tomato", "whole cherry tomatoes", "whole nuts", "whole nut",
        "popcorn", "hard candy", "hard candies", "chewing gum", "bubble gum", "marshmallow", "marshmallows",
        "whole hot dog", "hot dogs", "large chunks of meat",
    ]

    struct Rule {
        let id: String
        let title: String
        let terms: [String]
        /// Years and under this applies to (inclusive); nil means any child (TodayLayout.isChild's own definition).
        let maxAge: Int?
        let cap: Int
        let reason: String
    }

    static let rules: [Rule] = [
        Rule(id: "child-caffeine", title: "Caffeine", terms: caffeineTerms, maxAge: nil, cap: 60,
             reason: "Caffeine is commonly advised against or limited for children \u{2014} it affects a child's heart rate, sleep and anxiety more than an adult's."),
        Rule(id: "child-mercury", title: "High-mercury fish", terms: mercuryFishTerms, maxAge: nil, cap: 55,
             reason: "These fish can be high in mercury. The FDA and EPA advise limiting them for young children, same as in pregnancy."),
        Rule(id: "child-choking", title: "Common choking hazard", terms: chokingHazardTerms, maxAge: 4, cap: 65,
             reason: "This is on the common list of choking-hazard foods for young children (AAP/NHS guidance) \u{2014} cut it up small and supervise eating, don't serve it whole."),
        Rule(id: "child-cured-meat", title: "Cured or processed meat", terms: curedMeatTerms, maxAge: 0, cap: 55,
             reason: "Cured and processed meats contain nitrates/nitrites, which pediatric guidance advises limiting for infants under 1 \u{2014} their gut handles them differently than an older child's or adult's."),
    ]

    /// `member` must already be known to be a child (`TodayLayout.isChild`) before calling this — these
    /// rules don't re-check that themselves, only the extra age ceiling some of them have (e.g. choking
    /// hazards apply to a toddler, not a 16-year-old).
    static func matches(in product: Product, memberAge: Int?) -> [Rule] {
        let text = PregnancyGuidance.searchText(for: product)
        let range = NSRange(text.startIndex..., in: text)
        return rules.filter { rule in
            if let maxAge = rule.maxAge, let age = memberAge, age > maxAge { return false }
            return rule.terms.contains { IngredientAnalyzer.regex(for: $0)?.firstMatch(in: text, range: range) != nil }
        }
    }

    /// Honey is a hard, unambiguous rule (infant botulism risk), not a capped caution — handled on its
    /// own, the same tier as an allergy or alcohol for a child.
    static func containsHoney(_ product: Product) -> Bool {
        let text = PregnancyGuidance.searchText(for: product)
        let range = NSRange(text.startIndex..., in: text)
        return honeyTerms.contains { IngredientAnalyzer.regex(for: $0)?.firstMatch(in: text, range: range) != nil }
    }

    /// Fruit juice under 12 months is also a hard, specific AAP rule ("no juice before age 1"), not a
    /// vague preference — same tier as honey.
    static func containsJuice(_ product: Product) -> Bool {
        let text = PregnancyGuidance.searchText(for: product)
        let range = NSRange(text.startIndex..., in: text)
        return juiceTerms.contains { IngredientAnalyzer.regex(for: $0)?.firstMatch(in: text, range: range) != nil }
    }

    /// Named added sweeteners, as distinct from a product (e.g. whole fruit) that just happens to
    /// naturally contain sugar — used to gate the general child added-sugar guidance so it doesn't flag
    /// a bag of grapes the same way it flags candy.
    private static let addedSweetenerTerms = [
        "sugar", "cane sugar", "brown sugar", "corn syrup", "high fructose corn syrup", "glucose syrup",
        "sucrose", "dextrose", "fructose", "maltose", "honey", "molasses", "agave", "agave syrup",
        "maple syrup", "golden syrup", "invert sugar", "syrup",
    ]

    static func hasAddedSweetener(_ product: Product) -> Bool {
        guard let ingredients = product.ingredientsText else { return false }
        let text = ingredients.lowercased()
        let range = NSRange(text.startIndex..., in: text)
        return addedSweetenerTerms.contains { IngredientAnalyzer.regex(for: $0)?.firstMatch(in: text, range: range) != nil }
    }

    /// A supplement scanned for a child: dosing is sized for adults unless the product says otherwise,
    /// and iron overdose in particular is a leading cause of child poisoning deaths. This can't give
    /// precise dosing advice from a barcode lookup, so it's a caution to check with a pediatrician, not
    /// a block — children's chewable vitamins are a legitimate, common product to scan here. Caller must
    /// already know the member is a child; this only decides the supplement/iron part.
    static func supplementCaution(_ product: Product) -> (cap: Int, reason: String)? {
        guard product.isSupplement else { return nil }
        let text = PregnancyGuidance.searchText(for: product)
        let range = NSRange(text.startIndex..., in: text)
        let hasIron = IngredientAnalyzer.regex(for: "iron")?.firstMatch(in: text, range: range) != nil
        return (cap: hasIron ? 50 : 65,
                reason: hasIron
                    ? "Contains iron. Adult-dose iron supplements are a leading cause of accidental child poisoning \u{2014} use only a children's dose and keep the bottle out of reach."
                    : "This is a supplement, not food \u{2014} check with a pediatrician that the dose is right for a child before giving it.")
    }
}
