import Foundation

/// A playful "how far would you walk for this plate" idea. It is only ever shown for adults, is written to be
/// light and never guilt-tripping, and can be switched off. Deterministic: no AI, no data leaves the phone.
enum BurnItOff {
    struct Equivalent: Equatable {
        var steps: Int
        var walkMinutes: Int
        var runMinutes: Int
        var danceMinutes: Int
    }

    /// Roughly 0.045 kcal per step for a 70 kg adult, scaled by body weight.
    static func kcalPerStep(weightKg: Double?) -> Double {
        0.045 * min(max(weightKg ?? 70, 30), 250) / 70
    }

    static func equivalents(kcal: Double, weightKg: Double?) -> Equivalent {
        let weight = min(max(weightKg ?? 70, 30), 250)
        let energy = max(kcal, 0)
        func minutes(met: Double) -> Int { Int((energy / (met * weight / 60)).rounded()) }
        return Equivalent(steps: Int((energy / kcalPerStep(weightKg: weight) / 50).rounded()) * 50,
                          walkMinutes: minutes(met: 3.5), runMinutes: minutes(met: 9.8), danceMinutes: minutes(met: 5.5))
    }

    /// Only for adults who are not underweight. Children, and anyone whose BMI is under 18.5, never see it, because
    /// talk of "burning off" food isn't helpful for them.
    static func isSuitable(_ member: Member) -> Bool {
        if member.isPregnant { return false }
        if let age = member.age { if age < 18 { return false } }
        else if member.isManagedByParent { return false }
        if let h = member.heightCm, let w = member.weightKg, NutritionPlanner.bmi(weightKg: w, heightCm: h) < 18.5 { return false }
        return true
    }

    // MARK: Lines

    private static let foodLines: [(keywords: [String], lines: [String])] = [
        (["biryani", "pulao", "fried rice"], [
            "Biryani spotted! About {steps} steps of pure happiness. Worth every single one of them.",
            "Biryani is not a meal, it's an event. About {steps} steps to celebrate it properly.",
            "Rice, spice and everything nice: about {steps} steps. The biryani will wait for you, it always does."]),
        (["pizza", "burger", "fries", "pasta", "noodle"], [
            "About {steps} steps of cheese-powered walking. Cheese is a legitimate fuel source, allegedly.",
            "That plate is worth roughly {steps} steps. Bring a friend and split the route.",
            "About {steps} steps. Walk fast enough and the fries never even notice."]),
        (["cake", "gulab", "jalebi", "dessert", "sweet", "ice cream", "halwa", "kheer", "chocolate", "cookie", "biscuit", "laddu"], [
            "Something sweet on the plate! About {steps} steps, or {songs} songs of dancing in the kitchen.",
            "Dessert alert: {steps} steps, or one very enthusiastic dance-off. Your call.",
            "Sweet tooth on duty. About {steps} steps, and the walk is basically part of dessert."]),
        (["samosa", "pakora", "bhaji", "vada", "fried", "chips", "puri"], [
            "Crispy things are worth about {steps} steps. Your future self gets a great story out of it.",
            "That crunch costs roughly {steps} steps. Best paid in instalments.",
            "About {steps} steps. Crispy on the outside, a lovely stroll on the inside."]),
        (["salad", "soup", "idli", "fruit", "veg"], [
            "A light plate! About {steps} steps: basically a stroll to the corner shop and back.",
            "Looking after yourself: only about {steps} steps, and your legs barely notice.",
            "Light and clever. About {steps} steps, which is roughly the distance to your favourite chair."]),
        (["dosa", "roti", "chapati", "dal", "rice", "curry", "sabzi"], [
            "Honest home food. About {steps} steps, and a lovely evening walk with a chat.",
            "Proper comfort food: {steps} steps, ideally with a podcast and someone to talk to.",
            "Mum-approved plate. About {steps} steps, and mention the food when you get back."]),
    ]

    private static let tierLines: [(upTo: Double, lines: [String])] = [
        (150, ["Barely a snack: about {steps} steps and it's history. The trip to the fridge nearly covers it.",
               "A tiny bite: about {steps} steps. Blink and it's done.",
               "About {steps} steps. That's a wander around the kitchen, plus a dramatic sigh."]),
        (350, ["About {steps} steps: one lap of the neighbourhood, plus a hello to every dog you meet.",
               "Around {steps} steps. That's a {walk}-minute wander with a good song on.",
               "About {steps} steps: a leisurely loop, with an optional ice-cream stop for the very brave."]),
        (600, ["Roughly {steps} steps, about {walk} minutes of brisk walking. Put on a podcast and it disappears.",
               "About {steps} steps: a decent stroll, or {songs} songs of dancing like nobody's watching.",
               "Around {steps} steps. Your shoes have been waiting for this exact moment."]),
        (900, ["A proper feast! About {steps} steps. Grab a friend, a good playlist and comfy shoes.",
               "Big plate, big adventure: about {steps} steps. Take the scenic route.",
               "About {steps} steps. That's a walk with a beginning, a middle and a very good view."]),
        (.infinity, ["A grand feast: about {steps} steps. Spread it over the day, or share the plate. Legends do both.",
                     "That's a banquet, worth about {steps} steps. Two walks and a nap would sort it out.",
                     "About {steps} steps. A small pilgrimage, ideally in good company."]),
    ]

    private static let closers = [
        "Just for fun, not a rule.",
        "Or skip the walk and simply enjoy your meal. We won't tell.",
        "Walking is optional. Enjoying your food is mandatory.",
        "Fun maths, not advice.",
    ]

    /// Every line, so tests can check the tone.
    static var allLines: [String] { foodLines.flatMap(\.lines) + tierLines.flatMap(\.lines) + closers }

    /// A light line about this plate. The same plate and `seed` always give the same line; a new `seed` gives another.
    static func message(kcal: Double, foods: [String], equivalent e: Equivalent, seed: Int = 0) -> String {
        let names = foods.map { $0.lowercased() }
        var pool = foodLines.filter { entry in names.contains { name in entry.keywords.contains { name.contains($0) } } }.flatMap(\.lines)
        if pool.isEmpty { pool = (tierLines.first { kcal < $0.upTo } ?? tierLines[tierLines.count - 1]).lines }
        let line = pool[abs(seed) % pool.count]
        let filled = line
            .replacingOccurrences(of: "{steps}", with: e.steps.formatted())
            .replacingOccurrences(of: "{walk}", with: String(e.walkMinutes))
            .replacingOccurrences(of: "{songs}", with: String(max(e.danceMinutes / 4, 1)))
        return filled + " " + closers[abs(seed / max(pool.count, 1)) % closers.count]
    }
}
