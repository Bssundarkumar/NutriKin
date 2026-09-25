import Foundation

/// One place for short, single-shot AI text (a cheer, a daily tip, a workout idea). It picks the person's provider,
/// falls back from Apple's on-device model to their own key, and runs the reply through the shared review.
/// Returns nil when nothing is set up or the AI fails, so callers always have a non-AI path.
enum AIQuick {
    @MainActor
    static func text(rules: String, user: String, members: [Member], ai: AIConnection, maxTokens: Int = 220, limit: Int = 420) async -> String? {
        guard let provider = ai.textProvider else { return nil }
        let system = rules + "\n\n" + AIGuardrails.taskRules
        let turns = [(role: "user", text: user)]
        let raw = [["role": "user", "content": user]]
        do {
            let reply: String
            switch provider {
            case .apple:
                do { reply = try await AppleAI.chat(system: system, messages: turns) }
                catch {
                    guard let llm = ai.keyClient else { return nil }
                    reply = try await llm.chat(system: system, messages: raw, maxTokens: maxTokens)
                }
            case .claude, .openai, .grok, .gemini:
                guard let llm = ai.client(for: provider) else { return nil }
                reply = try await llm.chat(system: system, messages: raw, maxTokens: maxTokens)
            }
            let reviewed = AIGuardrails.review(reply: reply, members: members)
            let trimmed = AIGuardrails.capped(reviewed.trimmingCharacters(in: .whitespacesAndNewlines), to: limit)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }
}

/// A daily food-and-movement tip, and a workout idea, both on request.
enum DayCoach {
    static let tipRules = """
    You are NutriKin's friendly food helper. Given one family member's day so far (food eaten against their limits, movement and \\
    goals), write at most 3 short sentences: one thing going well, then ONE practical food idea for the rest of the day that fits \\
    their allergies and conditions (name real, everyday foods). Be warm and specific. Never shame, never suggest skipping meals or \\
    eating very little, never talk about weight loss, no medical advice, no medication, insulin or supplement advice, no emojis, no links. \\
    For a child keep it playful and about trying foods. For an older adult (65 or over) favour protein at each meal, fibre, fluids, calcium and vitamin D rich foods, easy-to-chew choices, and small frequent meals if appetite is low; never suggest fasting or restrictive diets. For a pregnant person keep to general healthy eating and suggest asking \\
    their midwife or doctor. Only use the numbers given; never invent any.
    """

    static let workoutIdeaRules = """
    You are NutriKin's friendly movement helper. Given one family member's details, this week's activity and goals, suggest ONE \\
    simple workout or activity for today in at most 3 short sentences: what to do, roughly how long, and a light reason. Match \\
    their age and stay gentle: never suggest anything intense for a child, an older adult, a pregnant person or anyone with a \\
    listed condition; say to check with their doctor if unsure. No medical advice, no weight-loss talk, no emojis, no links. \\
    Only use the details given; never invent numbers.
    """

    static let kidWeekRules = """
    You are NutriKin's friendly helper writing a short weekly note for the PARENTS of one child about the child's active play. \
    Write at most 3 short sentences: what the child did well this week (name the activities and days), then ONE simple, fun idea \
    for next week (for example a new activity or something to do together as a family). Be warm and encouraging. Never criticise \
    the child or the parents, never compare with other children, never talk about weight, body size or calories, no medical advice, \
    no emojis, no links. Only use the details given; never invent numbers.
    """

    static func kidWeekPrompt(member: Member, days: [KidActivity.Day], workouts: [Workout]) -> String {
        let cal = Calendar.current
        let start = ActivityGoals.weekStart()
        let lines = days.filter { $0.date <= Date() }.map { d -> String in
            let kinds = Set(workouts.filter { cal.isDate($0.doneAt, inSameDayAs: d.date) }.map { $0.workoutKind.title }).sorted().joined(separator: ", ")
            return "\(d.date.formatted(.dateTime.weekday(.wide))): \(d.minutes) minutes\(kinds.isEmpty ? "" : " (\(kinds))")"
        }
        _ = start
        return AIGuardrails.untrusted(AIContext.describe(member), tag: "family_data") + "\n\n"
            + AIGuardrails.untrusted(("Daily target: \(KidActivity.dailyGoalMinutes) minutes of active play.\n" + lines.joined(separator: "\n")), tag: "week_data")
    }

    static let kidSnackRules = """
    You are NutriKin's friendly food helper for the parents of one child. Suggest 3 simple, healthy snack or lunchbox ideas in at \
    most 4 short sentences, using everyday foods. Strictly avoid anything matching the child's allergies or conditions in the data, \
    and never say a food is safe for an allergy (say to read the label). Keep portions and choking safety in mind for young children. \
    No medical advice, no dieting or weight talk, no emojis, no links. Only use the details given.
    """

    static let carerWeekRules = """
    You are NutriKin's friendly helper writing a short weekly note for the FAMILY of one older adult, about how their week of eating \
    and movement went. Write at most 3 short sentences: what went well (name activities and days), then ONE gentle, practical idea for \
    next week (a favourite walk, a shared meal, an easy protein-rich food). Be warm and respectful and never patronising. Never blame \
    the person or the family, never talk about weight loss, no medical advice, no comments on medication beyond thanking them for \
    keeping up with it, no emojis, no links. Only use the details given; never invent numbers.
    """

    static func carerWeekPrompt(member: Member, days: [KidActivity.Day], doses: (taken: Int, total: Int)?, eatenToday: Bool) -> String {
        var lines = days.filter { $0.date <= Date() }.map { "\($0.date.formatted(.dateTime.weekday(.wide))): \($0.minutes) minutes of activity" }
        if let doses, doses.total > 0 { lines.append("Medicines today: \(doses.taken) of \(doses.total) marked taken.") }
        lines.append(eatenToday ? "Meals have been logged today." : "No meals logged yet today.")
        if let g = member.goals.weeklyWorkoutMinutes { lines.append("Weekly activity goal: \(g) minutes.") }
        return AIGuardrails.untrusted(AIContext.describe(member), tag: "family_data") + "\n\n" + AIGuardrails.untrusted(lines.joined(separator: "\n"), tag: "week_data")
    }

    /// A rough protein guide for older adults: about 1 g per kg a day, as general guidance.
    static func olderProteinGuide(_ member: Member) -> Int? {
        guard TodayLayout.isOlderAdult(member), let w = member.weightKg else { return nil }
        return Int((min(max(w, 30), 200)).rounded())
    }

    static func dayPrompt(member: Member, budget: DayBudget, steps: Int?, weekMinutes: Int) -> String {
        func n(_ v: Double) -> String { String(Int(v.rounded())) }
        var lines = [
            "Calories: \(n(budget.eaten.calories)) eaten, allowance \(n(budget.allowance)).",
            "Sugar: \(n(budget.eaten.sugarG)) g of a \(n(budget.limits.sugarG)) g limit.",
            "Sodium: \(n(budget.eaten.sodiumMg)) mg of a \(n(budget.limits.sodiumMg)) mg limit.",
            "Saturated fat: \(n(budget.eaten.satFatG)) g of a \(n(budget.limits.satFatG)) g limit.",
            "Fibre: \(n(budget.eaten.fiberG)) g of a \(n(budget.limits.fiberG)) g target.",
            "Protein: \(n(budget.eaten.proteinG)) g.",
            "Active calories today: \(budget.burned).",
        ]
        if let steps { lines.append("Steps today: \(steps).") }
        if let goal = member.goals.dailySteps { lines.append("Step goal: \(goal).") }
        if let g = olderProteinGuide(member) { lines.append("Protein guide for this age: about \(g) g a day, spread across meals.") }
        if let goal = member.goals.weeklyWorkoutMinutes { lines.append("Workout goal: \(weekMinutes) of \(goal) minutes this week.") }
        return AIGuardrails.untrusted(AIContext.describe(member), tag: "family_data") + "\n\n"
            + AIGuardrails.untrusted(lines.joined(separator: "\n"), tag: "day_data")
    }

    static func workoutPrompt(member: Member, weekMinutes: Int, steps: Int?) -> String {
        var lines = ["Minutes of activity so far this week: \(weekMinutes)."]
        if let goal = member.goals.weeklyWorkoutMinutes { lines.append("Weekly workout goal: \(goal) minutes.") }
        if let steps { lines.append("Steps today: \(steps).") }
        return AIGuardrails.untrusted(AIContext.describe(member), tag: "family_data") + "\n\n"
            + AIGuardrails.untrusted(lines.joined(separator: "\n"), tag: "activity_data")
    }
}
