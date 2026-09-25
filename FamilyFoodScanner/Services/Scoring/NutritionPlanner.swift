import Foundation

enum ActivityLevel: String, CaseIterable, Identifiable {
    case sedentary, light, moderate, active
    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        }
    }

    var title: String {
        switch self {
        case .sedentary: "Mostly sitting"
        case .light: "Light: exercise 1 to 3 days a week"
        case .moderate: "Moderate: exercise 3 to 5 days a week"
        case .active: "Very active: exercise 6 to 7 days a week"
        }
    }

    var shortTitle: String {
        switch self {
        case .sedentary: "Sitting"
        case .light: "Light"
        case .moderate: "Moderate"
        case .active: "Active"
        }
    }
}

enum BMICategory: Equatable {
    case underweight, healthy, overweight, obese

    init(bmi: Double) {
        switch bmi {
        case ..<18.5: self = .underweight
        case ..<25: self = .healthy
        case ..<30: self = .overweight
        default: self = .obese
        }
    }

    var label: String {
        switch self {
        case .underweight: "Underweight"
        case .healthy: "Healthy range"
        case .overweight: "Overweight"
        case .obese: "Obese range"
        }
    }
}

struct MealShare: Equatable {
    let name: String
    let kcal: Int
}

/// A daily intake suggestion worked out from a person's height, weight, age, sex and activity.
struct NutritionPlan {
    enum Direction { case lose, maintain, gain }

    let bmi: Double
    let category: BMICategory
    let healthyRangeKg: ClosedRange<Double>
    let currentKg: Double
    let targetKg: Double
    let direction: Direction
    let bmr: Int
    let maintenanceKcal: Int
    let dailyKcal: Int
    /// Signed: negative when losing.
    let weeklyChangeKg: Double
    let weeksToTarget: Int?
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let fiberG: Int
    let sugarLimitG: Int
    let satFatLimitG: Int
    let sodiumLimitMg: Int
    let meals: [MealShare]
    let notes: [String]
}

/// Deterministic and explainable, like the food scoring: standard published formulas,
/// no AI. A starting point to review with a doctor or dietitian, not medical advice.
enum NutritionPlanner {
    enum Result {
        case plan(NutritionPlan)
        /// Names of the details still missing or out of range.
        case needsInfo([String])
        case notForChildren
        /// Needs change through pregnancy, so no weight or calorie target is suggested.
        case notDuringPregnancy
    }

    /// The BMI the target weight is worked out from: the middle of the healthy range.
    static let targetBMI = 22.0

    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let m = heightCm / 100
        return weightKg / (m * m)
    }

    static func plan(for member: Member, activity: ActivityLevel) -> Result {
        if member.isPregnant { return .notDuringPregnancy }
        var missing: [String] = []
        if member.age == nil { missing.append("age") }
        if member.heightCm == nil { missing.append("height") }
        if member.weightKg == nil { missing.append("weight") }
        guard let age = member.age, let height = member.heightCm, let weight = member.weightKg, missing.isEmpty else {
            return .needsInfo(missing)
        }
        if age < 18 { return .notForChildren }
        guard age <= 100, (100...230).contains(height), (25...300).contains(weight) else {
            return .needsInfo(["realistic age, height and weight"])
        }

        let m = height / 100
        let bmiValue = bmi(weightKg: weight, heightCm: height)
        let category = BMICategory(bmi: bmiValue)
        let healthy = (18.5 * m * m)...(24.9 * m * m)
        let target = category == .healthy ? weight : targetBMI * m * m
        let direction: NutritionPlan.Direction = abs(target - weight) < 0.5 ? .maintain : (target < weight ? .lose : .gain)

        // Mifflin-St Jeor resting energy use.
        let sexOffset: Double = member.sex == .male ? 5 : (member.sex == .female ? -161 : -78)
        let bmr = 10 * weight + 6.25 * height - 5 * Double(age) + sexOffset
        let maintenance = bmr * activity.multiplier

        let floorKcal = member.sex == .male ? 1500.0 : 1200.0
        var daily = maintenance
        switch direction {
        case .lose:
            let deficit = min(550, maintenance * 0.25)          // about 0.5 kg a week, never more than 25%
            daily = min(maintenance, max(maintenance - deficit, floorKcal))
        case .gain:
            daily = maintenance + 300                            // about 0.25 to 0.3 kg a week
        case .maintain:
            break
        }
        let weekly = (daily - maintenance) * 7 / 7700
        let weeks: Int? = {
            guard abs(weekly) > 0.05, direction != .maintain else { return nil }
            let n = Int((abs(target - weight) / abs(weekly)).rounded(.up))
            return n <= 104 ? n : nil
        }()

        let hasHighCholesterol = member.has(.highCholesterol)
        let perKgProtein = direction == .maintain ? 1.0 : 1.2
        let proteinG = min(perKgProtein * (direction == .lose ? target : weight), 0.30 * daily / 4)
        let fatShare = member.has(.diabetes) ? 0.30 : 0.28
        let fatG = fatShare * daily / 9
        let carbsG = max(0, (daily - proteinG * 4 - fatG * 9) / 4)

        let satFatLimit = (hasHighCholesterol ? 0.07 : 0.10) * daily / 9
        let sugarLimit = min(member.goals.dailySugarGrams ?? ScoringEngine.defaultSugarLimitG(for: member.sex),
                             0.10 * daily / 4)
        let sodiumLimit = member.goals.dailySodiumMg
            ?? (member.has(.hypertension) ? ScoringEngine.defaultSodiumLimitMg : 2300)

        func round5(_ v: Double) -> Int { Int((v / 5).rounded()) * 5 }
        let meals = [MealShare(name: "Breakfast", kcal: round5(daily * 0.25)),
                     MealShare(name: "Lunch", kcal: round5(daily * 0.35)),
                     MealShare(name: "Dinner", kcal: round5(daily * 0.30)),
                     MealShare(name: "Snacks", kcal: round5(daily * 0.10))]

        var notes = [
            "BMI is a rough guide. It ignores muscle, age and body shape. Some groups, including people of South Asian background, have higher health risks at a lower BMI, so a doctor may use different cutoffs.",
            "Not for pregnancy or breastfeeding, or for anyone with an eating disorder or a condition that needs a special diet.",
        ]
        switch category {
        case .underweight:
            notes.insert("A BMI under 18.5 can have medical causes. Please see a doctor before changing how you eat.", at: 0)
        case .obese:
            notes.insert("At this BMI, medical support (a doctor or dietitian) usually helps more than going alone.", at: 0)
        default: break
        }
        if member.has(.diabetes) {
            notes.append("With diabetes, spread carbohydrates evenly across meals and check your targets with your care team before cutting calories.")
        }
        if daily <= floorKcal + 1 && direction == .lose {
            notes.append("This is already near the lowest safe daily intake, so the pace is slower. Don't eat less than this without medical supervision.")
        }

        return .plan(NutritionPlan(
            bmi: bmiValue, category: category, healthyRangeKg: healthy,
            currentKg: weight, targetKg: target, direction: direction,
            bmr: Int(bmr.rounded()), maintenanceKcal: Int(maintenance.rounded()), dailyKcal: Int(daily.rounded()),
            weeklyChangeKg: weekly, weeksToTarget: weeks,
            proteinG: Int(proteinG.rounded()), carbsG: Int(carbsG.rounded()), fatG: Int(fatG.rounded()),
            fiberG: Int((14 * daily / 1000).rounded()),
            sugarLimitG: Int(sugarLimit.rounded()), satFatLimitG: Int(satFatLimit.rounded()),
            sodiumLimitMg: Int(sodiumLimit.rounded()),
            meals: meals, notes: notes))
    }
}
