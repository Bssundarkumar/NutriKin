import Foundation

// MARK: - Allergens

enum Allergen: String, CaseIterable, Codable, Identifiable, Hashable {
    case peanuts, nuts, milk, gluten, eggs, soybeans, fish, crustaceans, sesame

    var id: String { rawValue }

    /// Tag format used by Open Food Facts in `allergens_tags`.
    var offTag: String { "en:\(rawValue)" }

    var displayName: String {
        switch self {
        case .peanuts: "Peanuts"
        case .nuts: "Tree nuts"
        case .milk: "Milk"
        case .gluten: "Gluten"
        case .eggs: "Eggs"
        case .soybeans: "Soy"
        case .fish: "Fish"
        case .crustaceans: "Shellfish"
        case .sesame: "Sesame"
        }
    }

    /// Fallback keywords checked against the ingredient text when the
    /// product's allergen tags are missing. Deliberately broad: a false
    /// alarm is better than a missed allergen. Includes the common French,
    /// Spanish, German and Italian words, since labels are often not in English.
    var keywords: [String] {
        switch self {
        case .peanuts: ["peanut", "groundnut", "cacahuète", "cacahuete", "arachide", "cacahuate", "erdnuss", "erdnüsse"]
        case .nuts: ["almond", "hazelnut", "cashew", "walnut", "pecan", "pistachio", "macadamia",
                     "noisette", "amande", "cajou", "pistache", "avellana", "almendra", "nuez", "nueces",
                     "haselnuss", "haselnüsse", "mandel", "walnuss", "nocciol", "mandorl"]
        case .milk: ["milk", "whey", "casein", "butter", "cream", "lactose",
                     "lait", "lactosérum", "lactoserum", "beurre", "crème", "creme fraiche",
                     "leche", "suero de leche", "mantequilla", "nata", "milch", "molke", "sahne",
                     "latte", "siero di latte", "burro", "panna",
                     "cheese", "yogurt", "yoghurt", "curd", "paneer", "ghee", "kefir", "custard",
                     "fromage", "yaourt", "queso", "yogur", "käse", "formaggio"]
        case .gluten: ["wheat", "barley", "rye", "spelt", "gluten",
                       "blé", "froment", "orge", "seigle", "épeautre", "trigo", "cebada", "centeno",
                       "weizen", "gerste", "roggen", "dinkel", "frumento", "orzo", "segale",
                       "semolina", "suji", "maida", "atta", "chapati", "roti", "naan", "paratha", "couscous",
                       "pasta", "noodle", "seitan"]
        case .eggs: ["egg", "oeuf", "œuf", "huevo", "eier", "uovo", "uova", "mayonnaise", "mayo"]
        case .soybeans: ["soy", "soya", "soja", "soia", "tofu", "tempeh", "edamame", "miso"]
        case .fish: ["fish", "anchov", "salmon", "tuna", "cod",
                     "poisson", "saumon", "thon", "morue", "pescado", "salmón", "atún", "bacalao",
                     "fisch", "lachs", "thunfisch", "pesce", "tonno", "merluzzo",
                     "sardine", "mackerel", "tilapia", "trout", "herring"]
        case .crustaceans: ["shrimp", "prawn", "crab", "lobster",
                            "crevette", "crabe", "homard", "gamba", "camarón", "camaron", "cangrejo",
                            "garnele", "krabbe", "hummer", "gambero", "granchio", "aragosta"]
        case .sesame: ["sesame", "tahini", "sésame", "sesamo", "sésamo", "sesam"]
        }
    }
}

// MARK: - Pregnancy

extension Condition {
    static let pregnancyLabel = "Pregnancy"

    /// Stored as a typed condition named "Pregnancy". That keeps older app versions on other family phones able
    /// to read the family (they just show it as text); this version recognises it and changes its advice.
    static var pregnancy: Condition { .custom(pregnancyLabel) }

    var isPregnancy: Bool {
        if case .custom(let name) = self { return name.lowercased().hasPrefix("pregnan") }
        return false
    }
}

// MARK: - Member

enum Condition: Hashable, Codable, Identifiable {
    case diabetes
    case hypertension
    case highCholesterol
    case allergy(Allergen)
    /// A named allergy that isn't one of the built-in `Allergen` cases,
    /// e.g. "kiwi" or "mustard". Matched against ingredient text by keyword.
    case customAllergy(String)
    /// Any other condition typed in by the user, e.g. "Celiac disease".
    /// Shown for context; it doesn't currently affect scoring.
    case custom(String)

    var id: String { String(describing: self) }

    var displayName: String {
        switch self {
        case .diabetes: "Diabetes"
        case .hypertension: "High blood pressure"
        case .highCholesterol: "High cholesterol"
        case .allergy(let a): "\(a.displayName) allergy"
        case .customAllergy(let name): "\(name) allergy"
        case .custom(let name): name
        }
    }
}

struct Goals: Codable, Hashable {
    var dailyCalories: Double?
    var dailySugarGrams: Double?
    var dailySodiumMg: Double?
    var dailySatFatGrams: Double?
}

/// Biological sex, used only to pick a more accurate default daily target
/// (calories, sugar, etc.) when a member hasn't set their own goal.
/// Optional and never required — leave unset if it doesn't apply or
/// the person would rather not say.
enum Sex: String, Codable, CaseIterable, Identifiable {
    case female, male

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        }
    }
}

struct Member: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var conditions: [Condition]
    var goals = Goals()
    /// A child or anyone without their own iPhone, managed by a parent.
    var isManagedByParent = false
    var age: Int?
    var heightCm: Double?
    var weightKg: Double?
    var sex: Sex?

    var allergies: [Allergen] {
        conditions.compactMap { if case .allergy(let a) = $0 { a } else { nil } }
    }

    var customAllergyNames: [String] {
        conditions.compactMap { if case .customAllergy(let name) = $0 { name } else { nil } }
    }

    var customConditionNames: [String] {
        conditions.compactMap { if case .custom(let name) = $0, !$0.isPregnancy { name } else { nil } }
    }

    var isPregnant: Bool { conditions.contains { $0.isPregnancy } }

    func has(_ condition: Condition) -> Bool {
        condition.isPregnancy ? isPregnant : conditions.contains(condition)
    }
}

// MARK: - Product

struct Nutrition: Hashable {
    var calories: Double?
    var sugarG: Double?
    var carbsG: Double?
    var sodiumMg: Double?
    var satFatG: Double?
    var transFatG: Double?
    var proteinG: Double?
    /// e.g. "per serving (40 g)" or "per 100 g"
    var basis: String
}

/// One ingredient and its share of the product.
struct IngredientAmount: Hashable {
    /// Open Food Facts' canonical id, e.g. "en:palm-oil" (English whatever the label's language).
    var id: String
    /// The name as printed on the label.
    var text: String
    /// Percent of the product, 0...100, when known.
    var percent: Double?
    /// True when the label itself states the percentage; false when it's
    /// Open Food Facts' estimate from the ingredient order and nutrition.
    var isStated: Bool

    /// The canonical id as plain English words: "en:skimmed-milk-powder" -> "skimmed milk powder".
    var englishWords: String {
        let bare = id.split(separator: ":", maxSplits: 1).last.map(String.init) ?? id
        return bare.replacingOccurrences(of: "-", with: " ")
    }
}

struct Product: Identifiable, Hashable {
    var id: String { barcode }
    var barcode: String
    var name: String
    var brand: String?
    var imageURL: URL?
    var ingredientsText: String?
    var allergenTags: [String]
    var nutrition: Nutrition
    /// Open Food Facts' standardised English tags, e.g. "en:palm-oil" and
    /// "en:e250". Language-independent, so ingredient alerts work on labels
    /// that aren't in English.
    var ingredientTags: [String] = []
    var additivesTags: [String] = []
    /// Each ingredient with how much of the product it makes up, in label order.
    /// Empty when Open Food Facts has no breakdown for the product.
    var ingredientAmounts: [IngredientAmount] = []
    /// Open Food Facts' Nutri-Score letter ("a" to "e") and NOVA processing group (1 to 4).
    var nutriScore: String?
    var novaGroup: Int?
    /// English category ids, general to specific (e.g. "en:spreads").
    var categoryTags: [String] = []
    /// The same nutrition on a fixed per-100 g basis, so different products can be compared fairly.
    var per100g: Nutrition?
    /// Allergens the label says it "may contain" (cross-contact), e.g. "en:nuts".
    var tracesTags: [String] = []

    /// True when there is any ingredient information to check allergies against.
    var hasIngredientInfo: Bool {
        !(ingredientsText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !ingredientTags.isEmpty
    }

    /// True when the product has at least one nutrition figure.
    var hasAnyNutrition: Bool {
        let n = nutrition
        return [n.calories, n.sugarG, n.carbsG, n.sodiumMg, n.satFatG, n.proteinG].contains { $0 != nil }
    }

    func mayContainTraces(of allergen: Allergen) -> Bool { tracesTags.contains(allergen.offTag) }

    /// Plain-language gaps in this product's data, shown on the result screen.
    var dataWarnings: [String] {
        var out: [String] = []
        if !hasIngredientInfo { out.append("No ingredient list is available for this product.") }
        if !hasAnyNutrition { out.append("No nutrition facts are available for this product.") }
        return out
    }

    /// Dietary supplements (vitamins, capsules and the like). Open Food Facts still
    /// computes NOVA and Nutri-Score for them from the ingredient list, but both
    /// grades were built for foods and would mislead here.
    var isSupplement: Bool {
        categoryTags.contains { $0.lowercased().hasPrefix("en:") && $0.lowercased().contains("supplement") }
    }

    /// A copy scored on the per-100 g figures, or nil when the product has none.
    var normalizedTo100g: Product? {
        guard let per100g else { return nil }
        var copy = self
        copy.nutrition = per100g
        return copy
    }

    func contains(_ allergen: Allergen) -> Bool {
        if allergenTags.contains(allergen.offTag) { return true }
        guard let text = ingredientsText?.lowercased() else { return false }
        return allergen.keywords.contains { text.contains($0) }
    }

    /// Best-effort keyword match for a custom, user-typed allergy name
    /// against the ingredient text and product name.
    func containsKeyword(_ term: String) -> Bool {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return false }
        if let ingredients = ingredientsText?.lowercased(), ingredients.contains(needle) { return true }
        return name.lowercased().contains(needle)
    }
}

// MARK: - Scoring output

enum Verdict: Int, Comparable {
    case avoid = 0, caution = 1, okay = 2

    static func < (a: Verdict, b: Verdict) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .avoid: "Avoid"
        case .caution: "Caution"
        case .okay: "Okay"
        }
    }
}

struct MemberScore: Identifiable {
    var id: UUID { member.id }
    var member: Member
    var score: Int
    var verdict: Verdict
    var reasons: [String]
    var blockedByAllergy: Bool
}
