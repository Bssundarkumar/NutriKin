import Foundation

/// A short cheer and one idea after a workout is saved. Always shows something: a warm line written in the app
/// straight away, upgraded to an AI-written one if the person has AI set up and it answers in time.
/// The AI only ever sees this workout and the person's details as data, and its reply goes through the usual review.
enum WorkoutCoach {
    static let maxCharacters = 420

    static let rules = """
    You are NutriKin's friendly workout cheerleader for one family member who has just logged a workout. Write at most 3 short \\
    sentences: first a warm, specific cheer about what they did, then ONE simple idea for what to do next (for example a stretch, \\
    a glass of water, a light snack or meal idea that suits their allergies and conditions, or a way to vary tomorrow's session). \\
    Be upbeat and a little playful. Never shame, never mention weight loss, punishment or "burning off" food, and never push harder \\
    than what they did. For a child keep it playful and simple. For a pregnant person keep it gentle and say to follow their midwife \\
    or doctor's advice on exercise. No medical advice, no medication or dosing, no supplements, no links, no emojis. \\
    Only use the details given; never invent numbers.
    """

    static func prompt(workout: Workout, member: Member, minutesToday: Int) -> String {
        var lines = ["Workout: \(workout.workoutKind.title), \(workout.minutes) minutes, effort \(workout.intensity.title.lowercased()), about \(workout.caloriesBurned) kcal (an estimate)."]
        if let ex = workout.exercises, !ex.isEmpty {
            let names = ex.prefix(6).map(\.name).joined(separator: ", ")
            lines.append("Strength: \(ex.count) exercises (\(names)), \(StrengthMath.totalSets(ex)) sets, \(StrengthMath.totalReps(ex)) reps.")
        }
        if minutesToday > workout.minutes { lines.append("Total active time logged today: \(minutesToday) minutes.") }
        return AIGuardrails.untrusted(AIContext.describe(member), tag: "family_data") + "\n\n"
            + AIGuardrails.untrusted(lines.joined(separator: "\n"), tag: "workout_data")
    }

    /// The instant, no-AI line. Deterministic for the same workout, so it doesn't flicker on redraw.
    static func fallback(workout: Workout, member: Member) -> String {
        let name = member.name
        let child = (member.age ?? 30) < 13 || (member.age == nil && member.isManagedByParent)
        if member.isPregnant {
            return "Lovely work, \(name)! Listening to your body is the whole game. A glass of water and a rest now, and check with your midwife or doctor about what suits you."
        }
        if child {
            let lines = [
                "Superstar move, \(name)! \(workout.minutes) minutes of play is a big win. Go grab some water like a champion.",
                "Wow, \(name), that's a lot of energy! Have a drink of water and tell someone what your favourite part was.",
            ]
            return lines[workout.minutes % lines.count]
        }
        var pool: [String]
        switch workout.workoutKind {
        case .strength:
            pool = ["Strong work, \(name)! Your muscles just did their homework. A protein-rich meal and some water will help them settle in.",
                    "Nice lifting, \(name)! Every set counts. Finish with a gentle stretch and a glass of water."]
        case .running, .hiit, .cycling, .swimming:
            pool = ["That's the spirit, \(name)! \(workout.minutes) minutes is a proper effort. Cool down slowly and drink some water.",
                    "Great session, \(name)! Your heart is happy. A short stretch and a snack with some carbs and protein would round it off."]
        case .yoga:
            pool = ["Beautifully done, \(name). Calm body, calm mind. Stay hydrated and enjoy the glow.",
                    "Lovely, \(name)! Slow and steady counts. A warm drink and a few deep breaths make a nice finish."]
        default:
            pool = ["Well done, \(name)! \(workout.minutes) minutes of moving is a real win. Have some water and enjoy the feeling.",
                    "Nice one, \(name)! Consistency beats intensity. Tomorrow, try to move a little again, even for ten minutes."]
        }
        return pool[workout.minutes % pool.count]
    }

    /// The AI version, or nil if nothing is set up or it fails. Never throws: the cheer is a bonus, not a requirement.
    @MainActor
    static func aiCheer(workout: Workout, member: Member, minutesToday: Int, ai: AIConnection, family: [Member]) async -> String? {
        guard let provider = ai.textProvider else { return nil }
        let user = prompt(workout: workout, member: member, minutesToday: minutesToday)
        let turns = [(role: "user", text: user)]
        let system = rules + "\n\n" + AIGuardrails.taskRules
        do {
            let reply: String
            switch provider {
            case .apple:
                do { reply = try await AppleAI.chat(system: system, messages: turns) }
                catch {
                    guard let llm = ai.keyClient else { return nil }
                    reply = try await llm.chat(system: system, messages: [["role": "user", "content": user]], maxTokens: 200)
                }
            case .claude, .openai, .grok, .gemini:
                guard let llm = ai.client(for: provider) else { return nil }
                reply = try await llm.chat(system: system, messages: [["role": "user", "content": user]], maxTokens: 200)
            }
            let reviewed = AIGuardrails.review(reply: reply, members: family)
            let trimmed = AIGuardrails.capped(reviewed.trimmingCharacters(in: .whitespacesAndNewlines), to: maxCharacters)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }
}
