import Foundation

struct MealDish: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var kcal: Int
    var ingredients: [String]
    var why: String
}

struct MealSlot: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var dishes: [MealDish]
    var kcal: Int { dishes.map(\.kcal).reduce(0, +) }
}

struct MealIdeas {
    var slots: [MealSlot]
    var tips: [String]
    /// How many suggestions were dropped because they may contain the person's allergen.
    var removedForAllergy: Int
    var totalKcal: Int { slots.map(\.kcal).reduce(0, +) }
}

enum MealSafety {
    /// Allergens (built-in and custom) that this dish's name or ingredients mention.
    /// The AI is asked to avoid them, but this check never relies on that.
    static func allergenHits(name: String, ingredients: [String], for member: Member) -> [String] {
        let text = ([name] + ingredients).joined(separator: " , ").lowercased()
        var hits = member.allergies.filter { $0.keywords.contains { text.contains($0) } }.map(\.displayName)
        hits += member.customAllergyNames.filter { text.contains($0.lowercased()) }
        return hits
    }
}

enum MealIdeasService {
    static func systemPrompt(member: Member, plan: NutritionPlan?, targetKcal: Int, preferences: String, expectJSON: Bool = true) -> String {
        var limits = ""
        if let plan {
            limits = """
            Aim for about \(plan.proteinG) g protein, \(plan.carbsG) g carbs, \(plan.fatG) g fat and \(plan.fiberG) g fibre a day; \
            added sugar under \(plan.sugarLimitG) g, saturated fat under \(plan.satFatLimitG) g, sodium under \(plan.sodiumLimitMg) mg.
            """
        }
        let prefs = preferences.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        You plan realistic home-style meals for one person in a family nutrition app.

        Person:
        \(AIContext.describe(member))

        Plan one day of eating: Breakfast, Lunch, Dinner and Snacks, totalling about \(targetKcal) kcal. \
        \(limits)
        \(prefs.isEmpty ? "" : "Their preferences: \(prefs).")

        Rules:
        - Everyday dishes with ordinary ingredients, with 1 to 3 dishes per meal.
        - NEVER include an ingredient the person is allergic to, including hidden forms (for example milk in butter or ghee, nuts in sauces).
        - Respect their conditions (lower sugar for diabetes, lower sodium for high blood pressure, less saturated fat for high cholesterol).
        - kcal is per dish as served. Be honest and approximate.

        \(expectJSON ? """
        Reply with JSON only, in exactly this shape:
        {"meals":[{"name":"Breakfast","dishes":[{"name":"Vegetable upma with curd","kcal":320,"ingredients":["semolina","mixed vegetables","curd"],"why":"Fibre-rich and slow to digest."}]}],"tips":["one short practical tip"]}
        """ : "")
        """
    }

    static func generate(member: Member, plan: NutritionPlan?, preferences: String,
                         provider: AIProvider, client: LLM?) async throws -> MealIdeas {
        let target = plan?.dailyKcal ?? Int(member.goals.dailyCalories ?? ScoringEngine.defaultCalorieGoal(for: member.sex))
        let request = "Plan today's meals for \(member.name)."
        let text: String
        switch provider {
        case .apple:
            do {
                text = try await AppleAI.mealPlanJSON(
                    system: systemPrompt(member: member, plan: plan, targetKcal: target, preferences: preferences, expectJSON: false),
                    prompt: request)
            } catch {
                guard let client else { throw error }       // fall back to the person's own key
                text = try await client.send(
                    system: systemPrompt(member: member, plan: plan, targetKcal: target, preferences: preferences),
                    content: [["type": "text", "text": request]], maxTokens: 2000)
            }
        case .claude, .openai:
            guard let client else { throw AnthropicClient.ClientError.invalidKey }
            text = try await client.send(
                system: systemPrompt(member: member, plan: plan, targetKcal: target, preferences: preferences),
                content: [["type": "text", "text": request]], maxTokens: 2000)
        }
        // Whoever wrote the plan, the app re-checks every dish against the person's allergies.
        return try MealIdeasParser.parse(text, for: member)
    }
}

enum MealIdeasParser {
    private struct DTO: Decodable {
        struct Slot: Decodable {
            struct Dish: Decodable { var name: String?; var kcal: Double?; var ingredients: [String]?; var why: String? }
            var name: String?
            var dishes: [Dish]?
        }
        var meals: [Slot]?
        var tips: [String]?
    }

    static let order = ["breakfast", "lunch", "dinner", "snack"]

    static func parse(_ reply: String, for member: Member) throws -> MealIdeas {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let dto = try? JSONDecoder().decode(DTO.self, from: Data(reply[start...end].utf8)) else {
            throw AnthropicClient.ClientError.badResponse
        }
        var removed = 0
        var ranked: [(rank: Int, slot: MealSlot)] = []
        for raw in dto.meals ?? [] {
            let name = (raw.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let rank = order.firstIndex(where: { name.lowercased().hasPrefix($0) }) else { continue }
            var dishes: [MealDish] = []
            for d in (raw.dishes ?? []).prefix(3) {
                let dishName = (d.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !dishName.isEmpty, let kcal = d.kcal, kcal >= 0 else { continue }
                let ingredients = Array((d.ingredients ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(12))
                if !MealSafety.allergenHits(name: dishName, ingredients: ingredients, for: member).isEmpty {
                    removed += 1
                    continue
                }
                dishes.append(MealDish(name: String(dishName.prefix(80)), kcal: Int(min(kcal, 1500)),
                                       ingredients: ingredients, why: String((d.why ?? "").prefix(160))))
            }
            if !dishes.isEmpty {
                let title = rank == 3 ? "Snacks" : order[rank].capitalized
                ranked.append((rank, MealSlot(name: title, dishes: dishes)))
            }
        }
        let slots = ranked.sorted { $0.rank < $1.rank }.map(\.slot)
        let tips = (dto.tips ?? []).map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)) }.filter { !$0.isEmpty }
        return MealIdeas(slots: slots, tips: Array(tips.prefix(4)), removedForAllergy: removed)
    }
}
