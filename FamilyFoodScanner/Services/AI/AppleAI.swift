import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Which AI answers text questions and plans meals.
enum AIProvider: String, CaseIterable, Identifiable {
    /// Apple's model running on this iPhone (iOS 26+, Apple Intelligence). Free, private, no key.
    case apple
    /// The person's own key for one of these services.
    case claude, openai, grok, gemini

    var id: String { rawValue }

    /// The services that use a key the person supplies, in the order used as a fallback.
    static let keyVendors: [AIProvider] = [.claude, .openai, .grok, .gemini]

    var title: String {
        switch self {
        case .apple: "Apple (on this iPhone)"
        case .claude: "Claude (your key)"
        case .openai: "OpenAI (your key)"
        case .grok: "Grok (your key)"
        case .gemini: "Gemini (your key)"
        }
    }
    var shortName: String {
        switch self {
        case .apple: "Apple"; case .claude: "Claude"; case .openai: "OpenAI"; case .grok: "Grok"; case .gemini: "Gemini"
        }
    }
    /// The company that receives the request when this provider is used.
    var vendorName: String {
        switch self {
        case .apple: "Apple"; case .claude: "Anthropic"; case .openai: "OpenAI"; case .grok: "xAI"; case .gemini: "Google"
        }
    }
    var usesKey: Bool { self != .apple }

    /// The provider for chat and meals, given what the person prefers and what's set up. Pure, so it's tested.
    static func choose(preference: AIProvider, appleAvailable: Bool, linked: Set<AIProvider>) -> AIProvider? {
        let firstKey = keyVendors.first(where: linked.contains)
        if preference == .apple { return appleAvailable ? .apple : firstKey }
        if linked.contains(preference) { return preference }
        return appleAvailable ? .apple : firstKey
    }

    /// The key-based provider for anything Apple's model can't do (photos) or as a fallback.
    static func chooseKey(preference: AIProvider, linked: Set<AIProvider>) -> AIProvider? {
        if preference.usesKey, linked.contains(preference) { return preference }
        return keyVendors.first(where: linked.contains)
    }
}

struct AIFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Apple's on-device language model. Text only: it can't read photos, so plate scanning still needs a key.
enum AppleAI {
    enum Status: Equatable {
        case available
        case unavailable(String)
        case unsupportedOS

        var isAvailable: Bool { self == .available }
    }

    static var status: Status {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable("This iPhone doesn't support Apple Intelligence (iPhone 15 Pro or later).")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Turn on Apple Intelligence in Settings to use it here.")
            case .unavailable(.modelNotReady):
                return .unavailable("Apple's model is still downloading. Try again later.")
            case .unavailable:
                return .unavailable("Apple's on-device AI isn't available right now.")
            }
        }
        #endif
        return .unsupportedOS
    }

    /// Replies to the latest message. Earlier turns are folded into the prompt because
    /// each request gets a fresh session (keeps it stateless and within the small context window).
    static func chat(system: String, messages: [(role: String, text: String)]) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let recent = messages.suffix(6)
            var prompt = ""
            if recent.count > 1 {
                prompt += "Conversation so far:\n" + recent.dropLast()
                    .map { ($0.role == "user" ? "Person: " : "You: ") + $0.text }.joined(separator: "\n") + "\n\n"
                prompt += "Now reply to the person's latest message:\n"
            }
            prompt += recent.last?.text ?? ""
            do {
                return try await LanguageModelSession(instructions: system).respond(to: prompt).content
            } catch {
                throw failure(error)
            }
        }
        #endif
        throw AIFailure(message: "Apple's on-device AI isn't available on this iPhone.")
    }

    /// A day of meals as JSON text (same shape the Claude path returns), via guided generation
    /// so the small on-device model always produces valid structure.
    static func mealPlanJSON(system: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let plan = try await LanguageModelSession(instructions: system)
                    .respond(to: prompt, generating: GeneratedMealPlan.self).content
                let object: [String: Any] = [
                    "meals": plan.meals.map { slot in
                        ["name": slot.name,
                         "dishes": slot.dishes.map { d in
                            ["name": d.name, "kcal": d.kcal, "ingredients": d.ingredients, "why": d.why] as [String: Any]
                         }] as [String: Any]
                    },
                    "tips": plan.tips,
                ]
                return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            } catch {
                throw failure(error)
            }
        }
        #endif
        throw AIFailure(message: "Apple's on-device AI isn't available on this iPhone.")
    }

    /// A product's details from text the phone read off the pack (OCR), as JSON in the shape
    /// `ProductPhotoReader.parse` expects. The model only structures text that is really there.
    static func productLabelJSON(ocrText: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let instructions = """
            \(AIGuardrails.taskRules)

            You organise text read from a food package by a phone camera. Copy what is PRINTED; never guess or invent. \
            Leave a field empty (or -1 for numbers) when the text doesn't clearly show it. Keep the ingredient list exactly as \
            printed, in its original language. If only salt is listed, sodium in mg is salt in grams times 400.
            """
            do {
                let label = try await LanguageModelSession(instructions: instructions)
                    .respond(to: "Text read from the package:\n\(AIGuardrails.untrusted(String(ocrText.prefix(2500)), tag: "package_text"))", generating: GeneratedProductLabel.self).content
                func number(_ v: Double) -> Any { v < 0 ? NSNull() : v }
                func text(_ s: String) -> Any { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? NSNull() : s }
                let object: [String: Any] = [
                    "name": text(label.name), "brand": text(label.brand), "ingredients": text(label.ingredients),
                    "allergens_statement": text(label.allergens), "serving_size": text(label.servingSize),
                    "nutrition_basis": label.basis,
                    "nutrition": ["calories": number(label.calories), "sugar_g": number(label.sugar), "carbs_g": number(label.carbs),
                                  "sodium_mg": number(label.sodiumMg), "sat_fat_g": number(label.satFat), "protein_g": number(label.protein)],
                ]
                return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            } catch {
                throw failure(error)
            }
        }
        #endif
        throw AIFailure(message: "Apple's on-device AI isn't available on this iPhone.")
    }

    /// Estimates a plate from a text description of the foods, as JSON in the shape `PlateParser` expects.
    static func plateJSON(system: String, foods: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let plate = try await LanguageModelSession(instructions: system)
                    .respond(to: "Foods on the plate: \(AIGuardrails.untrusted(String(foods.prefix(600)), tag: "foods"))", generating: GeneratedPlateEstimate.self).content
                let object: [String: Any] = [
                    "items": plate.items.map { f in
                        ["name": f.name, "grams": f.grams,
                         "per_100g": ["calories": f.calories, "sugar_g": f.sugar, "carbs_g": f.carbs, "sodium_mg": f.sodiumMg,
                                      "sat_fat_g": f.satFat, "protein_g": f.protein, "fiber_g": f.fiber, "fat_g": f.fat],
                         "confidence": f.confidence, "allergens": f.allergens] as [String: Any]
                    },
                    "note": plate.note,
                ]
                return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            } catch {
                throw failure(error)
            }
        }
        #endif
        throw AIFailure(message: "Apple's on-device AI isn't available on this iPhone.")
    }

    /// Three alternative ideas as JSON text (same shape the key-based path returns), via guided generation.
    static func alternativeIdeasJSON(system: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let ideas = try await LanguageModelSession(instructions: system)
                    .respond(to: prompt, generating: GeneratedAlternativeIdeas.self).content
                let object: [String: Any] = ["ideas": ideas.ideas.map { ["search": $0.search, "why": $0.why] }]
                return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            } catch {
                throw failure(error)
            }
        }
        #endif
        throw AIFailure(message: "Apple's on-device AI isn't available on this iPhone.")
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func failure(_ error: Error) -> AIFailure {
        if let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .guardrailViolation: return AIFailure(message: "Apple's AI declined that request. Try rewording it.")
            case .exceededContextWindowSize: return AIFailure(message: "That conversation got too long for the on-device AI. Start a new one.")
            default: break
            }
        }
        return AIFailure(message: "The on-device AI couldn't answer. Try again.")
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedDish {
    @Guide(description: "Name of the dish, e.g. Vegetable upma with curd")
    var name: String
    @Guide(description: "Calories of the dish as served, a whole number", .range(0...1500))
    var kcal: Int
    @Guide(description: "Main ingredients, plain names")
    var ingredients: [String]
    @Guide(description: "One short reason this dish suits the person")
    var why: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedSlot {
    @Guide(description: "Exactly one of: Breakfast, Lunch, Dinner, Snacks")
    var name: String
    @Guide(description: "One to three dishes", .count(1...3))
    var dishes: [GeneratedDish]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedAlternativeIdea {
    @Guide(description: "Short generic product name to search a food database, no brand, e.g. unsweetened almond butter")
    var search: String
    @Guide(description: "One short reason it suits this family better")
    var why: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedAlternativeIdeas {
    @Guide(description: "Exactly three different better alternatives", .count(3))
    var ideas: [GeneratedAlternativeIdea]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedProductLabel {
    @Guide(description: "Product name as printed, or empty if unclear") var name: String
    @Guide(description: "Brand as printed, or empty") var brand: String
    @Guide(description: "The ingredient list exactly as printed, or empty") var ingredients: String
    @Guide(description: "Any 'Contains' or 'May contain' allergen statement as printed, or empty") var allergens: String
    @Guide(description: "Either 'per 100 g' or 'per serving', whichever column the nutrition table uses") var basis: String
    @Guide(description: "Serving size like 30 g, or empty") var servingSize: String
    @Guide(description: "Calories in kcal, or -1 if not shown", .range(-1...5000)) var calories: Double
    @Guide(description: "Sugars in g, or -1 if not shown", .range(-1...500)) var sugar: Double
    @Guide(description: "Carbohydrate in g, or -1 if not shown", .range(-1...500)) var carbs: Double
    @Guide(description: "Sodium in mg, or -1 if not shown", .range(-1...20000)) var sodiumMg: Double
    @Guide(description: "Saturated fat in g, or -1 if not shown", .range(-1...500)) var satFat: Double
    @Guide(description: "Protein in g, or -1 if not shown", .range(-1...500)) var protein: Double
}

@available(iOS 26.0, *)
@Generable
struct GeneratedPlateFood {
    @Guide(description: "Name of the food, e.g. Basmati rice") var name: String
    @Guide(description: "Cooked weight in grams as served on the plate", .range(5...1500)) var grams: Int
    @Guide(description: "Typical calories per 100 g", .range(0...900)) var calories: Double
    @Guide(description: "Typical sugars per 100 g", .range(0...100)) var sugar: Double
    @Guide(description: "Typical carbohydrate per 100 g", .range(0...100)) var carbs: Double
    @Guide(description: "Typical sodium in mg per 100 g", .range(0...5000)) var sodiumMg: Double
    @Guide(description: "Typical saturated fat per 100 g", .range(0...100)) var satFat: Double
    @Guide(description: "Typical protein per 100 g", .range(0...100)) var protein: Double
    @Guide(description: "Typical dietary fibre per 100 g", .range(0...100)) var fiber: Double
    @Guide(description: "Typical total fat per 100 g, including cooking oil or ghee", .range(0...100)) var fat: Double
    @Guide(description: "high, medium or low: how sure you are of the food and amount") var confidence: String
    @Guide(description: "Possible allergens, only from: peanuts, nuts, milk, gluten, eggs, soybeans, fish, crustaceans, sesame") var allergens: [String]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedPlateEstimate {
    @Guide(description: "One entry per distinct food, at most eight", .count(1...8)) var items: [GeneratedPlateFood]
    @Guide(description: "One short sentence about the biggest uncertainty") var note: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedMealPlan {
    @Guide(description: "Breakfast, Lunch, Dinner and Snacks, in that order", .count(4))
    var meals: [GeneratedSlot]
    @Guide(description: "One or two short practical tips", .count(1...2))
    var tips: [String]
}
#endif
