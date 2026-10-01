import Foundation

/// One short, rule-based read on how the day's going, for a small card near the bottom of Today —
/// deterministic like `ScoringEngine`/`NutritionPlanner`, not AI, so it's always there even before
/// anyone connects a key. `DayTipCard` still offers an AI-written tip on request; this is a free,
/// always-on companion to it.
enum TodayInsight {
    static func line(for budget: DayBudget, fiberShareGoal: Double = 1.0) -> (headline: String, detail: String)? {
        guard budget.eaten.calories > 0 else { return nil }

        if budget.calorieShare >= 1 {
            return ("Over today's calorie goal", "Today's \(Int(budget.eaten.calories.rounded())) kcal is past the \(Int(budget.limits.calories.rounded())) kcal target — a lighter dinner helps balance it out.")
        }
        if let alert = budget.nutrientAlert {
            let name = alert.name == "saturated fat" ? "saturated fat" : alert.name
            return ("Close to today's \(name) limit", "You're at \(Int((alert.share * 100).rounded()))% of the \(name) limit — worth watching the rest of the day.")
        }
        if budget.fiberShare < 0.7 {
            return ("Great job staying within your calorie goal!", "Try adding a serving of vegetables at dinner to reach your fibre target.")
        }
        if budget.calorieShare >= 0.8 {
            return ("Nearly at today's calories", "\(Int(budget.remaining.rounded())) kcal left — a lighter choice for what's left of the day keeps you on track.")
        }
        return ("On track today", "Calories and nutrients are all within range so far — keep it up.")
    }
}
