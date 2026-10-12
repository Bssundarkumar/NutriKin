import Foundation

/// A general-knowledge nutrition estimate for a product Open Food Facts has no data for, guessed from its
/// name/brand alone (no label photo). Deliberately never includes ingredients or allergens: those drive
/// hard safety blocks (allergies, alcohol-for-children, ...), and a wrong guess there is a different and
/// more dangerous kind of mistake than a wrong guess at calories. Ingredient-based warnings stay in force
/// even after an estimate is applied - see `Product.dataWarnings`.
struct NutritionEstimate: Equatable {
    var nutrition: Nutrition
    /// What the AI says this estimate is based on, e.g. "typical nutrition for vodka, 40% ABV".
    var note: String
    /// False when the model doesn't recognise the product or its category well enough to estimate.
    var recognized: Bool
}

enum NutritionEstimator {
    enum EstimateError: LocalizedError {
        case notRecognized
        var errorDescription: String? {
            "Apple's AI doesn't recognise this product well enough to estimate its nutrition."
        }
    }

    /// Asks Apple's on-device model (the only provider wired up for this - it needs no key and the
    /// request never leaves the phone) for a nutrition estimate, and throws `.notRecognized` rather
    /// than returning a guess it has no confidence in.
    static func estimate(name: String, brand: String?) async throws -> NutritionEstimate {
        let json = try await AppleAI.nutritionEstimateJSON(name: name, brand: brand)
        let result = try parse(json)
        guard result.recognized else { throw EstimateError.notRecognized }
        return result
    }

    private struct DTO: Decodable {
        struct Nut: Decodable {
            var calories, sugarG, carbsG, sodiumMg, satFatG, proteinG: Double?
            enum CodingKeys: String, CodingKey {
                case calories, sugarG = "sugar_g", carbsG = "carbs_g", sodiumMg = "sodium_mg"
                case satFatG = "sat_fat_g", proteinG = "protein_g"
            }
        }
        var recognized: Bool?
        var note: String?
        var basis: String?
        var nutrition: Nut?
    }

    static func parse(_ reply: String) throws -> NutritionEstimate {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let dto = try? JSONDecoder().decode(DTO.self, from: Data(reply[start...end].utf8)) else {
            throw AIFailure(message: "The AI's reply couldn't be read. Try again.")
        }
        func clamp(_ v: Double?, _ hi: Double) -> Double? { v.map { min(max($0, 0), hi) } }
        let basis = (dto.basis ?? "").lowercased().contains("serving") ? "per serving" : "per 100 g"
        let note = AIGuardrails.sanitize((dto.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines), max: 200, keepNewlines: false)
        let n = dto.nutrition
        return NutritionEstimate(
            nutrition: Nutrition(calories: clamp(n?.calories, 5000), sugarG: clamp(n?.sugarG, 500), carbsG: clamp(n?.carbsG, 500),
                                 sodiumMg: clamp(n?.sodiumMg, 20000), satFatG: clamp(n?.satFatG, 500), transFatG: nil,
                                 proteinG: clamp(n?.proteinG, 500), basis: basis),
            note: note.isEmpty ? "AI estimate, not from the package." : note,
            recognized: dto.recognized ?? false)
    }

    /// Applies an estimate to a product, marking it as AI-estimated. Never touches ingredients,
    /// allergens, or category/tag data - only the nutrition figures the real product data was missing.
    static func apply(_ estimate: NutritionEstimate, to product: Product) -> Product {
        var copy = product
        copy.nutrition = estimate.nutrition
        copy.nutritionIsAIEstimate = true
        copy.nutritionEstimateNote = estimate.note
        return copy
    }
}
