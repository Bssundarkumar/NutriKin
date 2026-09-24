import Foundation

/// One food on the plate, with the AI's estimate of how much of it there is.
struct PlateItem: Identifiable, Hashable {
    struct Per100g: Hashable {
        var calories: Double
        var sugarG: Double
        var carbsG: Double
        var sodiumMg: Double
        var satFatG: Double
        var proteinG: Double
    }
    enum Confidence: String, Hashable { case high, medium, low }

    var id = UUID()
    var name: String
    /// Editable: nutrition scales with this.
    var grams: Double
    var per100g: Per100g
    var confidence: Confidence
    var allergens: [Allergen]

    private func amount(_ per100: Double) -> Double { per100 * grams / 100 }
    var calories: Double { amount(per100g.calories) }
    var sugarG: Double { amount(per100g.sugarG) }
    var carbsG: Double { amount(per100g.carbsG) }
    var sodiumMg: Double { amount(per100g.sodiumMg) }
    var satFatG: Double { amount(per100g.satFatG) }
    var proteinG: Double { amount(per100g.proteinG) }
}

struct MealTotals: Hashable {
    var calories = 0.0, sugarG = 0.0, carbsG = 0.0, sodiumMg = 0.0, satFatG = 0.0, proteinG = 0.0

    static func of(_ items: [PlateItem]) -> MealTotals {
        items.reduce(into: MealTotals()) {
            $0.calories += $1.calories; $0.sugarG += $1.sugarG; $0.carbsG += $1.carbsG
            $0.sodiumMg += $1.sodiumMg; $0.satFatG += $1.satFatG; $0.proteinG += $1.proteinG
        }
    }
}

struct PlateAnalysis {
    var items: [PlateItem]
    var note: String?
    /// The plate size the AI worked out from the photo, when the person didn't give one.
    var estimatedPlateCm: Int? = nil
}

/// What this meal means for one family member, as a share of their daily targets.
struct MemberImpact: Identifiable {
    var member: Member
    var caloriePct: Double
    var sugarPct: Double
    var sodiumPct: Double
    var satFatPct: Double
    var allergyHits: [Allergen]
    var id: UUID { member.id }

    /// Red on a possible allergen; otherwise by the biggest share of a daily limit this one meal uses.
    var level: Verdict {
        if !allergyHits.isEmpty { return .avoid }
        let worst = max(sugarPct, sodiumPct, satFatPct)
        return worst >= 0.6 ? .avoid : worst >= 0.35 ? .caution : .okay
    }
}

enum PlateMath {
    static func impact(of totals: MealTotals, allergens: Set<Allergen>, for member: Member) -> MemberImpact {
        let sugarLimit = member.goals.dailySugarGrams ?? ScoringEngine.defaultSugarLimitG(for: member.sex)
        let satFatLimit = member.goals.dailySatFatGrams ?? ScoringEngine.defaultSatFatLimitG(for: member.sex)
        let calorieGoal = member.goals.dailyCalories ?? ScoringEngine.defaultCalorieGoal(for: member.sex)
        // 1500 mg is the stricter limit for high blood pressure; 2300 mg is the general adult limit.
        let sodiumLimit = member.goals.dailySodiumMg
            ?? (member.has(.hypertension) ? ScoringEngine.defaultSodiumLimitMg : 2300)
        return MemberImpact(
            member: member,
            caloriePct: totals.calories / calorieGoal,
            sugarPct: totals.sugarG / sugarLimit,
            sodiumPct: totals.sodiumMg / sodiumLimit,
            satFatPct: totals.satFatG / satFatLimit,
            allergyHits: member.allergies.filter(allergens.contains)
        )
    }
}
