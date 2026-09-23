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
    /// alarm is better than a missed allergen.
    var keywords: [String] {
        switch self {
        case .peanuts: ["peanut", "groundnut"]
        case .nuts: ["almond", "hazelnut", "cashew", "walnut", "pecan", "pistachio", "macadamia"]
        case .milk: ["milk", "whey", "casein", "butter", "cream", "lactose"]
        case .gluten: ["wheat", "barley", "rye", "spelt", "gluten"]
        case .eggs: ["egg"]
        case .soybeans: ["soy", "soya"]
        case .fish: ["fish", "anchov", "salmon", "tuna", "cod"]
        case .crustaceans: ["shrimp", "prawn", "crab", "lobster"]
        case .sesame: ["sesame", "tahini"]
        }
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
        conditions.compactMap { if case .custom(let name) = $0 { name } else { nil } }
    }

    func has(_ condition: Condition) -> Bool { conditions.contains(condition) }
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
