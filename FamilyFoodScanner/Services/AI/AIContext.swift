import Foundation

/// Plain-text facts about the family and a product, given to the AI so its answers
/// are about *these* people. Only what the person has entered in the app; nothing
/// about the phone or account.
enum AIContext {
    static func family(_ members: [Member]) -> String {
        guard !members.isEmpty else { return "<family_data>\nNo family members have been added yet.\n</family_data>" }
        return AIGuardrails.untrusted(members.map(describe).joined(separator: "\n"), tag: "family_data")
    }

    static func describe(_ m: Member) -> String {
        var parts: [String] = []
        if let sex = m.sex { parts.append(sex.displayName.lowercased()) }
        if let age = m.age { parts.append("\(age) years old") }
        if let h = m.heightCm, let w = m.weightKg {
            parts.append("\(Int(h)) cm, \(Int(w)) kg (BMI \(String(format: "%.1f", NutritionPlanner.bmi(weightKg: w, heightCm: h))))")
        }
        let allergies = m.allergies.map(\.displayName) + m.customAllergyNames
        let conditions = m.conditions.filter { if case .allergy = $0 { false } else if case .customAllergy = $0 { false } else { true } }
            .map(\.displayName)
        if !conditions.isEmpty { parts.append("conditions: " + conditions.joined(separator: ", ")) }
        if !allergies.isEmpty { parts.append("ALLERGIES: " + allergies.joined(separator: ", ")) }
        var goals: [String] = []
        if let c = m.goals.dailyCalories { goals.append("\(Int(c)) kcal") }
        if let s = m.goals.dailySugarGrams { goals.append("sugar under \(Int(s)) g") }
        if let na = m.goals.dailySodiumMg { goals.append("sodium under \(Int(na)) mg") }
        if let f = m.goals.dailySatFatGrams { goals.append("sat. fat under \(Int(f)) g") }
        if !goals.isEmpty { parts.append("daily goals: " + goals.joined(separator: ", ")) }
        return "- \(m.name)" + (parts.isEmpty ? "" : ": " + parts.joined(separator: "; "))
    }

    static func product(_ p: Product, members: [Member]) -> String {
        var lines = ["Product: \(p.name)" + (p.brand.map { " by \($0)" } ?? "")]
        let n = p.nutrition
        var facts: [String] = []
        if let v = n.calories { facts.append("\(Int(v)) kcal") }
        if let v = n.sugarG { facts.append("sugar \(fmt(v)) g") }
        if let v = n.carbsG { facts.append("carbs \(fmt(v)) g") }
        if let v = n.sodiumMg { facts.append("sodium \(Int(v)) mg") }
        if let v = n.satFatG { facts.append("saturated fat \(fmt(v)) g") }
        if let v = n.proteinG { facts.append("protein \(fmt(v)) g") }
        lines.append(facts.isEmpty ? "Nutrition: not available." : "Nutrition \(n.basis): " + facts.joined(separator: ", "))
        if !p.isSupplement {
            var grades: [String] = []
            if let g = p.nutriScore { grades.append("Nutri-Score \(g.uppercased())") }
            if let g = p.novaGroup { grades.append("NOVA group \(g)") }
            if !grades.isEmpty { lines.append(grades.joined(separator: ", ")) }
        }
        if let text = p.ingredientsText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            lines.append("Ingredients: " + String(text.prefix(700)))
        } else {
            lines.append("Ingredients: not available.")
        }
        if !p.tracesTags.isEmpty {
            lines.append("May contain traces of: " + p.tracesTags.map { $0.replacingOccurrences(of: "en:", with: "") }.joined(separator: ", "))
        }
        let alerts = IngredientAnalyzer().alerts(for: p, members: members).map(\.flag.title)
        if !alerts.isEmpty { lines.append("Ingredient alerts: " + alerts.joined(separator: "; ")) }
        let scores = ScoringEngine().scoreFamily(p, members: members)
        if !scores.isEmpty {
            lines.append("NutriKin's scores for the family (0 to 100, rule-based):")
            for s in scores {
                lines.append("- \(s.member.name): \(s.score) (\(s.verdict.label))" + (s.blockedByAllergy ? " ALLERGY BLOCK" : "")
                             + ". " + s.reasons.prefix(2).joined(separator: " "))
            }
        }
        lines.append(contentsOf: p.dataWarnings)
        return AIGuardrails.untrusted(lines.joined(separator: "\n"), tag: "product_data")
    }

    private static func fmt(_ v: Double) -> String { v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v) }
}

enum AskAI {
    /// `compact` trims the product facts for Apple's small on-device context window.
    static func systemPrompt(family: [Member], product: Product?, compact: Bool = false) -> String {
        var s = """
        \(AIGuardrails.chatRules)

        Answer the person's questions about food for THEIR family, using the facts below. Be practical, warm and brief \
        (under 150 words unless asked for more), in plain language, with short lists when useful.

        When they ask for suggestions (meals, snacks, swaps, ideas), always answer with 3 to 5 concrete, specific ideas \
        tailored to this family: respect every condition and allergy listed, and say briefly why each one fits. \
        Don't refuse or ask for a product first; general food questions need no scanned product.

        Family:
        \(AIContext.family(family))
        """
        if let product {
            let facts = AIContext.product(product, members: family)
            s += "\n\nThe product they just scanned:\n\(compact ? String(facts.prefix(1400)) : facts)"
        } else {
            s += "\n\nNo product was scanned. Answer generally for the family."
        }
        return s
    }

    static let starters = [
        "Is this OK for everyone?",
        "What could we eat instead?",
        "How often is it fine to have this?",
    ]
}
