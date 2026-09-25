import Foundation

enum WorkoutEstimator {
    static let defaultWeightKg = 70.0

    /// Calories burned = MET x body weight (kg) x hours. A guide, not a measurement.
    static func calories(kind: WorkoutKind, intensity: WorkoutIntensity, minutes: Int, weightKg: Double?) -> Int {
        let weight = min(max(weightKg ?? defaultWeightKg, 30), 250)
        return Int((kind.met(intensity) * weight * Double(max(minutes, 0)) / 60).rounded())
    }
}

/// A person's daily targets, from their own goals where set and sensible defaults otherwise.
struct DailyLimits: Equatable {
    var calories: Double
    var sugarG: Double
    var sodiumMg: Double
    var satFatG: Double
    /// A fibre target (about 14 g per 1000 kcal, at least 20 g). Unlike the others, more is better.
    var fiberG: Double

    static func `for`(_ member: Member) -> DailyLimits {
        DailyLimits(
            calories: member.goals.dailyCalories ?? ScoringEngine.defaultCalorieGoal(for: member.sex),
            sugarG: member.goals.dailySugarGrams ?? ScoringEngine.defaultSugarLimitG(for: member.sex),
            // 1500 mg is the stricter limit for high blood pressure; 2300 mg is the general adult limit.
            sodiumMg: member.goals.dailySodiumMg ?? (member.has(.hypertension) ? ScoringEngine.defaultSodiumLimitMg : 2300),
            satFatG: member.goals.dailySatFatGrams ?? ScoringEngine.defaultSatFatLimitG(for: member.sex),
            fiberG: 0).withFiber()
    }

    private func withFiber() -> DailyLimits { var l = self; l.fiberG = max(20, 14 * calories / 1000); return l }
}

struct DayTotals: Equatable {
    var calories = 0.0, sugarG = 0.0, carbsG = 0.0, sodiumMg = 0.0, satFatG = 0.0, proteinG = 0.0
    var fiberG = 0.0, fatG = 0.0

    static func of(_ entries: [FoodEntry]) -> DayTotals {
        entries.reduce(into: DayTotals()) {
            $0.calories += $1.calories; $0.sugarG += $1.sugarG; $0.carbsG += $1.carbsG
            $0.sodiumMg += $1.sodiumMg; $0.satFatG += $1.satFatG; $0.proteinG += $1.proteinG
            $0.fiberG += $1.fiberG; $0.fatG += $1.fatG
        }
    }
}

/// How one person's day stands: what they may eat, what they have eaten, and what's left.
struct DayBudget {
    /// Only part of exercise calories is added back to the day's allowance, so exercise never
    /// licenses a big meal. Half is the usual guidance.
    static let eatBackFraction = 0.5

    let limits: DailyLimits
    let eaten: DayTotals
    let burned: Int

    /// Calories from logged workouts (typed in or imported).
    let loggedBurned: Int
    /// Active calories Apple Health reports for the day, if this phone belongs to the person.
    let healthBurned: Int

    /// Health's active calories include the workouts, so the larger of the two is used, never their sum.
    init(member: Member, entries: [FoodEntry], workouts: [Workout], healthActiveKcal: Double? = nil) {
        limits = DailyLimits.for(member)
        eaten = DayTotals.of(entries)
        loggedBurned = workouts.reduce(0) { $0 + $1.caloriesBurned }
        healthBurned = max(Int((healthActiveKcal ?? 0).rounded()), 0)
        burned = max(loggedBurned, healthBurned)
    }

    var exerciseBonus: Double { Double(burned) * Self.eatBackFraction }
    var allowance: Double { limits.calories + exerciseBonus }
    var remaining: Double { allowance - eaten.calories }
    var calorieShare: Double { allowance > 0 ? eaten.calories / allowance : 0 }
    var sugarShare: Double { eaten.sugarG / limits.sugarG }
    var sodiumShare: Double { eaten.sodiumMg / limits.sodiumMg }
    var satFatShare: Double { eaten.satFatG / limits.satFatG }
    var fiberShare: Double { eaten.fiberG / limits.fiberG }

    /// Green until 80% of any daily limit is used, orange until it's passed, then red.
    var status: Verdict {
        let worst = max(calorieShare, sugarShare, sodiumShare, satFatShare)
        return worst >= 1 ? .avoid : worst >= 0.8 ? .caution : .okay
    }

    /// The calorie ring's colour: about calories only, so a nutrient limit doesn't make a light day look bad.
    var calorieStatus: Verdict { calorieShare >= 1 ? .avoid : calorieShare >= 0.8 ? .caution : .okay }

    /// The nutrient closest to (or past) its daily limit, if it has used at least 80% of it.
    var nutrientAlert: (name: String, share: Double)? {
        let list = [("sugar", sugarShare), ("sodium", sodiumShare), ("saturated fat", satFatShare)]
        guard let worst = list.max(by: { $0.1 < $1.1 }), worst.1 >= 0.8 else { return nil }
        return (worst.0, worst.1)
    }
}

enum Portion: Equatable {
    case grams(Double)
    case servings(Double)
}

enum PortionScaler {
    /// What to offer first: servings when the product's figures are per serving, otherwise 100 g.
    static func defaultPortion(for product: Product) -> Portion {
        product.nutrition.basis.lowercased().hasPrefix("per serving") ? .servings(1) : .grams(100)
    }

    /// The nutrition of the amount eaten, or nil if the product's figures can't be scaled to it.
    static func entry(for product: Product, portion: Portion, memberId: UUID, householdId: UUID?, at date: Date = Date()) -> FoodEntry? {
        let base: Nutrition
        let factor: Double
        switch portion {
        case .grams(let g):
            if let per100 = product.per100g { base = per100 }
            else if product.nutrition.basis.lowercased().contains("100 g") { base = product.nutrition }
            else { return nil }
            factor = g / 100
        case .servings(let n):
            guard product.nutrition.basis.lowercased().hasPrefix("per serving") else { return nil }
            base = product.nutrition
            factor = n
        }
        func scaled(_ v: Double?) -> Double { (v ?? 0) * factor }
        return FoodEntry(
            householdId: householdId, memberId: memberId, eatenAt: date,
            label: String((product.brand.map { "\($0) " } ?? "") + product.name).prefix(120).description,
            barcode: product.barcode.hasPrefix("photo-") ? nil : product.barcode, source: .scan,
            calories: scaled(base.calories), sugarG: scaled(base.sugarG), carbsG: scaled(base.carbsG),
            sodiumMg: scaled(base.sodiumMg), satFatG: scaled(base.satFatG), proteinG: scaled(base.proteinG))
    }

    /// One entry for a whole plate, so a meal is a single line in the day.
    static func entry(for items: [PlateItem], memberId: UUID, householdId: UUID?, at date: Date = Date()) -> FoodEntry {
        let totals = MealTotals.of(items)
        return FoodEntry(
            householdId: householdId, memberId: memberId, eatenAt: date,
            label: String(items.map(\.name).joined(separator: ", ").prefix(120)),
            source: .plate, calories: totals.calories, sugarG: totals.sugarG, carbsG: totals.carbsG,
            sodiumMg: totals.sodiumMg, satFatG: totals.satFatG, proteinG: totals.proteinG,
            fiberG: totals.fiberG, fatG: totals.fatG)
    }
}

enum GroceryRules {
    /// Lowercased, trimmed, single-spaced, so "Milk " and "milk" count as the same item.
    static func normalized(_ name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func isDuplicate(_ name: String, in items: [GroceryItem]) -> Bool {
        let n = normalized(name)
        return !n.isEmpty && items.contains { normalized($0.name) == n }
    }

    /// Cleans free text into an item name: no links or control characters, capped, first letter capitalised.
    static func cleanName(_ raw: String) -> String {
        let t = AIGuardrails.sanitize(raw, max: 120)
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// Names worth adding from a list of ingredients (for example from a meal plan): cleaned, no repeats,
    /// nothing already on the list.
    static func newNames(from ingredients: [String], existing: [GroceryItem]) -> [String] {
        var seen = Set(existing.map { normalized($0.name) })
        var out: [String] = []
        for raw in ingredients {
            let name = cleanName(raw)
            guard !name.isEmpty, seen.insert(normalized(name)).inserted else { continue }
            out.append(name)
        }
        return out
    }
}
