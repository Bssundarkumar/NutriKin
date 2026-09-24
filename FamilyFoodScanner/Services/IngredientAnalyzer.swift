import Foundation

/// Flags ingredients that are widely regarded as worth limiting, with a plain
/// reason for each. Like the scoring engine this is a fixed, explainable
/// watchlist (no AI), and it only *informs*: it never changes a score.
///
/// The list is deliberately conservative. Every entry is tied to a mainstream
/// source (WHO, IARC, FDA/EU rulings, AHA) rather than to food-blog lore, and
/// anything evidence-mixed is marked `.note`, not `.warning`. Review the list
/// with a dietitian before launch, like the scoring thresholds.
struct IngredientFlag: Identifiable {
    enum Severity: Int, Comparable {
        case note = 0, warning = 1
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    /// Who the flag is relevant to. Condition-specific flags only show up
    /// when someone in the family has that condition.
    enum Applies {
        case everyone
        case condition(Condition)
        case children
    }

    let id: String
    let title: String
    let severity: Severity
    let applies: Applies
    let reason: String
    /// Phrases matched (whole-word, case-insensitive) against the ingredient
    /// text and Open Food Facts' English ingredient tags.
    let terms: [String]
    /// E-numbers, lowercase (e.g. "e250").
    let eCodes: [String]

    init(_ id: String, _ title: String, _ severity: Severity, _ applies: Applies,
         terms: [String] = [], eCodes: [String] = [], reason: String) {
        self.id = id; self.title = title; self.severity = severity; self.applies = applies
        self.terms = terms; self.eCodes = eCodes; self.reason = reason
    }
}

struct IngredientAlert: Identifiable {
    let flag: IngredientFlag
    /// Family members this matters most for. Empty means "everyone".
    let members: [String]
    var id: String { flag.id }
}

struct IngredientAnalyzer {
    static let watchlist: [IngredientFlag] = [
        IngredientFlag("trans-fat", "Partially hydrogenated oil", .warning, .everyone,
            terms: ["partially hydrogenated", "partly hydrogenated", "partiellement hydrogéné", "parcialmente hidrogenado", "teilweise gehärtet"],
            reason: "A source of artificial trans fat, which raises LDL (\"bad\") cholesterol and lowers HDL. The FDA has removed it from the US food supply."),
        IngredientFlag("processed-meat-nitrite", "Nitrite / nitrate preservatives", .warning, .everyone,
            terms: ["sodium nitrite", "sodium nitrate", "potassium nitrite", "potassium nitrate",
                    "nitrite de sodium", "nitrate de potassium", "nitrito sódico", "nitrito de sodio", "natriumnitrit"],
            eCodes: ["e249", "e250", "e251", "e252"],
            reason: "Used to cure processed meat. The WHO's cancer agency classes processed meat as carcinogenic, so it's best kept occasional."),
        IngredientFlag("titanium-dioxide", "Titanium dioxide", .warning, .everyone,
            terms: ["titanium dioxide"], eCodes: ["e171"],
            reason: "A whitening colour the EU banned as a food additive in 2022 over safety concerns it couldn't rule out."),
        IngredientFlag("potassium-bromate", "Potassium bromate", .warning, .everyone,
            terms: ["potassium bromate"], eCodes: ["e924"],
            reason: "A flour improver classed as possibly carcinogenic to humans and banned in the EU and several other countries."),
        IngredientFlag("bha-bht", "BHA / BHT preservatives", .note, .everyone,
            terms: ["butylated hydroxyanisole", "butylated hydroxytoluene", "bha", "bht"],
            eCodes: ["e320", "e321"],
            reason: "Synthetic antioxidants. BHA is classed as possibly carcinogenic to humans, so many people choose to avoid them."),
        IngredientFlag("artificial-sweetener", "Artificial sweeteners", .note, .everyone,
            terms: ["aspartame", "acesulfame", "sucralose", "saccharin"],
            eCodes: ["e950", "e951", "e954", "e955"],
            reason: "The WHO advises against relying on non-sugar sweeteners for weight control, and their long-term effects are still uncertain."),
        IngredientFlag("artificial-colour-children", "Artificial colours linked to hyperactivity", .warning, .children,
            terms: ["tartrazine", "sunset yellow", "quinoline yellow", "carmoisine", "azorubine", "ponceau 4r", "allura red"],
            eCodes: ["e102", "e104", "e110", "e122", "e124", "e129"],
            reason: "Some studies link these colours to increased hyperactivity in children. The EU requires a warning label on foods containing them."),

        // Condition-specific: only shown when someone in the family has it.
        IngredientFlag("added-sugar", "Added sugars", .note, .condition(.diabetes),
            terms: ["sugar", "sucre", "azúcar", "azucar", "zucker", "zucchero", "sirop de glucose", "jarabe de glucosa", "glucose syrup", "glucose-fructose syrup", "high fructose corn syrup",
                    "corn syrup", "fructose", "dextrose", "invert sugar", "maltose", "cane juice",
                    "jaggery", "honey", "brown rice syrup"],
            reason: "Added sugars raise blood glucose quickly. Look for products where sugar isn't among the first ingredients."),
        IngredientFlag("refined-flour", "Refined flour", .note, .condition(.diabetes),
            terms: ["refined wheat flour", "refined flour", "enriched wheat flour", "white flour", "maida"],
            reason: "Refined flour is digested fast and can spike blood sugar more than whole grains."),
        IngredientFlag("sodium-additives", "Sodium-based additives", .note, .condition(.hypertension),
            terms: ["monosodium glutamate", "sodium benzoate", "disodium inosinate", "disodium guanylate",
                    "sodium phosphate", "sodium nitrite", "sodium bicarbonate"],
            eCodes: ["e621", "e211", "e631", "e627", "e339", "e250", "e500"],
            reason: "These add sodium on top of the salt, which counts against a blood-pressure limit."),
        IngredientFlag("saturated-fat-oils", "Palm / coconut oil", .note, .condition(.highCholesterol),
            terms: ["palm oil", "huile de palme", "aceite de palma", "palmöl", "olio di palma", "palm kernel", "palmolein", "coconut oil", "lard", "tallow", "shortening"],
            reason: "High in saturated fat, which raises LDL cholesterol."),
    ]

    private let watchlist: [IngredientFlag]
    init(watchlist: [IngredientFlag] = IngredientAnalyzer.watchlist) { self.watchlist = watchlist }

    /// Alerts for this product, most serious first. Condition-specific flags
    /// are dropped when nobody in the family has that condition.
    func alerts(for product: Product, members: [Member]) -> [IngredientAlert] {
        let haystack = searchableText(for: product)
        let codes = eCodes(in: haystack, product: product)

        var out: [IngredientAlert] = []
        for flag in watchlist where matches(flag, haystack: haystack, codes: codes) {
            switch flag.applies {
            case .everyone:
                out.append(IngredientAlert(flag: flag, members: []))
            case .condition(let condition):
                let names = members.filter { $0.has(condition) }.map(\.name)
                if !names.isEmpty { out.append(IngredientAlert(flag: flag, members: names)) }
            case .children:
                let names = members.filter(Self.isChild).map(\.name)
                if !names.isEmpty { out.append(IngredientAlert(flag: flag, members: names)) }
            }
        }
        return out.sorted { $0.flag.severity > $1.flag.severity }
    }

    /// The most serious of the given alerts that applies to one ingredient
    /// (for colouring that ingredient in the list), or nil.
    func flag(for item: String, among alerts: [IngredientAlert]) -> IngredientFlag? {
        let haystack = item.lowercased()
        let codes = eCodes(in: haystack)
        return alerts.map(\.flag)
            .filter { matches($0, haystack: haystack, codes: codes) }
            .max { $0.severity < $1.severity }
    }

    static func isChild(_ member: Member) -> Bool {
        if let age = member.age { return age <= 12 }
        return member.isManagedByParent   // no age set: a parent-managed member is likely a child
    }

    // MARK: - Matching

    private func searchableText(for product: Product) -> String {
        // Open Food Facts' tags are English and language-independent
        // ("en:palm-oil"), so they work even when the label text isn't English.
        let tags = product.ingredientTags.map {
            $0.replacingOccurrences(of: "en:", with: "").replacingOccurrences(of: "-", with: " ")
        }
        // The parsed breakdown carries each ingredient's label name and English id.
        let amounts = product.ingredientAmounts.map { $0.text + " " + $0.englishWords }
        return ([product.ingredientsText ?? ""] + tags + amounts).joined(separator: " , ").lowercased()
    }

    private func eCodes(in haystack: String, product: Product) -> Set<String> {
        eCodes(in: haystack, extra: product.additivesTags.map {
            $0.replacingOccurrences(of: "en:", with: "").lowercased()
        })
    }

    private func eCodes(in haystack: String, extra: [String] = []) -> Set<String> {
        var found = Set(extra)
        // "E250", "E 250", "e-250", "E150d" in the label text.
        let pattern = #"\be[ -]?(\d{3}[a-i]?)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(haystack.startIndex..., in: haystack)
            for match in regex.matches(in: haystack, range: range) {
                if let r = Range(match.range(at: 1), in: haystack) { found.insert("e" + haystack[r]) }
            }
        }
        return found
    }

    private func matches(_ flag: IngredientFlag, haystack: String, codes: Set<String>) -> Bool {
        if flag.eCodes.contains(where: codes.contains) { return true }
        return flag.terms.contains { term in
            let pattern = "(?<![a-z])" + NSRegularExpression.escapedPattern(for: term) + "(?![a-z])"
            return haystack.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
