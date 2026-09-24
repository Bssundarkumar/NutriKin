import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Which AI answers text questions and plans meals.
enum AIProvider: String, CaseIterable, Identifiable {
    /// Apple's model running on this iPhone (iOS 26+, Apple Intelligence). Free, private, no key.
    case apple
    /// The person's own Anthropic key.
    case claude

    var id: String { rawValue }
    var title: String { self == .apple ? "Apple (on this iPhone)" : "Claude (your key)" }

    /// The provider to use given what the person prefers and what's available. Pure, so it's tested.
    static func choose(preference: AIProvider, appleAvailable: Bool, keyConnected: Bool) -> AIProvider? {
        switch preference {
        case .apple: return appleAvailable ? .apple : (keyConnected ? .claude : nil)
        case .claude: return keyConnected ? .claude : (appleAvailable ? .apple : nil)
        }
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
struct GeneratedMealPlan {
    @Guide(description: "Breakfast, Lunch, Dinner and Snacks, in that order", .count(4))
    var meals: [GeneratedSlot]
    @Guide(description: "One or two short practical tips", .count(1...2))
    var tips: [String]
}
#endif
