import Foundation

/// Rule-based, explainable scoring. Every point deducted produces a reason
/// the user can read. Keep AI out of this path: especially for allergies,
/// the result must be deterministic.
struct ScoringEngine {
    // Defaults used when a member hasn't set their own goal.
    static let defaultSugarLimitG = 25.0     // per day
    static let defaultSodiumLimitMg = 1500.0 // per day
    static let defaultSatFatLimitG = 13.0    // per day

    func score(_ product: Product, for member: Member) -> MemberScore {
        // 1. Allergies are a hard block, independent of nutrition.
        let hits = member.allergies.filter(product.contains)
        if !hits.isEmpty {
            let names = hits.map(\.displayName).joined(separator: ", ")
            return MemberScore(
                member: member, score: 0, verdict: .avoid,
                reasons: ["Contains \(names.lowercased()). Allergy rules block this product regardless of nutrition."],
                blockedByAllergy: true
            )
        }

        var score = 100.0
        var reasons: [String] = []
        let n = product.nutrition

        // 2. Diabetes: sugar against the daily goal, plus a carb check.
        if member.has(.diabetes) {
            if let sugar = n.sugarG {
                let limit = member.goals.dailySugarGrams ?? Self.defaultSugarLimitG
                let share = sugar / limit
                let penalty = min(60, share * 100)
                score -= penalty
                if penalty >= 10 {
                    reasons.append("\(fmt(sugar)) g sugar is \(pct(share)) of the \(fmt(limit)) g daily sugar goal.")
                }
            }
            if let carbs = n.carbsG, carbs > 30 {
                score -= 10
                reasons.append("\(fmt(carbs)) g carbs is on the high side for one serving.")
            }
        }

        // 3. Hypertension: sodium against the daily limit.
        if member.has(.hypertension), let sodium = n.sodiumMg {
            let limit = member.goals.dailySodiumMg ?? Self.defaultSodiumLimitMg
            let share = sodium / limit
            let penalty = min(60, share * 150)
            score -= penalty
            if penalty >= 10 {
                reasons.append("\(fmt(sodium)) mg sodium is \(pct(share)) of the \(fmt(limit)) mg daily limit.")
            }
        }

        // 4. High cholesterol: saturated and trans fat.
        if member.has(.highCholesterol) {
            if let sat = n.satFatG {
                let limit = member.goals.dailySatFatGrams ?? Self.defaultSatFatLimitG
                let share = sat / limit
                let penalty = min(50, share * 120)
                score -= penalty
                if penalty >= 10 {
                    reasons.append("\(fmt(sat)) g saturated fat is \(pct(share)) of the \(fmt(limit)) g daily limit.")
                }
            }
            if let trans = n.transFatG, trans > 0.2 {
                score -= 20
                reasons.append("Contains trans fat (\(fmt(trans)) g).")
            }
        }

        // 5. Calorie goal: only penalise a large share of the day in one go.
        if let cal = n.calories, let goal = member.goals.dailyCalories {
            let share = cal / goal
            if share > 0.25 {
                score -= min(30, (share - 0.25) * 100)
            }
            reasons.append("\(fmt(cal)) kcal is \(pct(share)) of the \(fmt(goal)) kcal daily goal.")
        }

        let final = Int(max(0, min(100, score.rounded())))
        let verdict: Verdict = final >= 70 ? .okay : (final >= 40 ? .caution : .avoid)
        if reasons.isEmpty {
            reasons.append("No concerns for \(member.name)'s conditions or goals.")
        }
        return MemberScore(member: member, score: final, verdict: verdict,
                           reasons: reasons, blockedByAllergy: false)
    }

    /// Scores everyone, most at-risk first.
    func scoreFamily(_ product: Product, members: [Member]) -> [MemberScore] {
        members.map { score(product, for: $0) }
            .sorted { ($0.verdict, $0.score) < ($1.verdict, $1.score) }
    }

    private func fmt(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
    }

    private func pct(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }
}
