import Foundation

/// A rough, rule-based A–E quality grade for one logged food, from its nutrient density (per 100 kcal) —
/// not tied to any one person's conditions or goals, unlike `ScoringEngine`. It's a quick "how processed
/// and nutrient-poor vs. whole and nutrient-dense is this, roughly" read for the day as a whole, the way
/// a Nutri-Score-style label works. Deterministic and explainable, not medical advice.
enum FoodGrade: Int, CaseIterable, Comparable {
    case e = 0, d = 1, c = 2, b = 3, a = 4

    static func < (x: FoodGrade, y: FoodGrade) -> Bool { x.rawValue < y.rawValue }

    var letter: String {
        switch self {
        case .a: "A"
        case .b: "B"
        case .c: "C"
        case .d: "D"
        case .e: "E"
        }
    }

    private static func letter(for score: Double) -> FoodGrade {
        switch score {
        case 85...: .a
        case 70..<85: .b
        case 55..<70: .c
        case 35..<55: .d
        default: .e
        }
    }

    /// 0–100 nutrient-density score for one entry, or nil when there's nothing to grade it on
    /// (e.g. a 0-calorie entry like plain water).
    static func score(for entry: FoodEntry) -> Double? {
        guard entry.calories > 0 else { return nil }
        let perHundredKcal = 100 / entry.calories
        let sugar = entry.sugarG * perHundredKcal
        let satFat = entry.satFatG * perHundredKcal
        let sodium = entry.sodiumMg * perHundredKcal
        let fiber = entry.fiberG * perHundredKcal
        let protein = entry.proteinG * perHundredKcal

        var score = 100.0
        score -= min(40, sugar * 3)        // g sugar per 100 kcal
        score -= min(30, satFat * 8)       // g saturated fat per 100 kcal
        score -= min(20, sodium * 0.15)    // mg sodium per 100 kcal
        score += min(15, fiber * 5)        // g fibre per 100 kcal
        score += min(10, protein * 1.5)    // g protein per 100 kcal
        return min(max(score, 0), 100)
    }

    static func grade(for entry: FoodEntry) -> FoodGrade? { score(for: entry).map(letter(for:)) }

    /// The day's average: a 0–100 percent and the letter it rounds to, or nil with nothing gradeable logged.
    static func average(_ entries: [FoodEntry]) -> (percent: Int, grade: FoodGrade)? {
        let scores = entries.compactMap(score(for:))
        guard !scores.isEmpty else { return nil }
        let mean = scores.reduce(0, +) / Double(scores.count)
        return (Int(mean.rounded()), letter(for: mean))
    }
}
