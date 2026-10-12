import Foundation

/// Extra checks for the short coaching texts (workout cheers, daily tips, snack ideas, weekly notes). They come on top of
/// `AIGuardrails.review`: whatever a model writes, a sentence about dieting, weight loss, fasting, supplements, diagnosis,
/// or (for a child or a pregnant person) topics that don't fit them is removed before anyone reads it.
extension AIGuardrails {
    /// Never fine for anyone.
    private static let bannedForAll = [
        "lose weight", "losing weight", "weight loss", "weight-loss", "burn off", "burn it off", "earn your", "earn that",
        "calorie deficit", "cut calories", "starve", "starving", "fasting", "detox", "cleanse", "crash diet", "skip meals", "skip a meal",
        "diet pill", "fat burner", "fat-burner", "supplement", "you should see a doctor", "you have diabetes", "you probably have",
        "diagnos", "symptom", "guilty", "lazy", "fat ", "obese", "too heavy", "cheat meal", "punish"
    ]
    /// Extra for children: no numbers or talk about weight, calories or body size.
    private static let bannedForChildren = ["calorie", "kcal", "weight", "bmi", "diet", "slim", "skinny", "chubby", "overweight", "underweight"]
    /// Extra for pregnancy: no pushing harder, and nothing pregnant people are commonly told to avoid.
    private static let bannedForPregnancy = ["push harder", "max effort", "all-out", "heavy lifting", "alcohol", "wine", "beer", "raw fish", "sushi",
                                            "raw egg", "unpasteurised", "unpasteurized", "liver", "high intensity"]
    /// Extra for older adults: no fasting or restrictive eating.
    private static let bannedForOlder = ["intermittent", "low-calorie", "very low", "restrict"]

    /// The reviewed text, or nil when nothing safe is left (the caller then shows its own written line).
    static func reviewCoaching(reply: String, for member: Member?) -> String? {
        var banned = bannedForAll
        if let member {
            if TodayLayout.isChild(member) { banned += bannedForChildren }
            if member.isPregnant { banned += bannedForPregnancy }
            if TodayLayout.isOlderAdult(member) { banned += bannedForOlder }
        }
        let kept = sentences(reply).filter { sentence in
            let lower = " " + sentence.lowercased() + " "
            return !banned.contains { lower.contains($0) }
        }
        let text = kept.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        // Emoji and stray markup don't belong in these short notes.
        let plain = text.unicodeScalars.filter { !($0.properties.isEmojiPresentation) }.map(String.init).joined()
            .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "#", with: "")
        return plain.count >= 12 ? plain : nil
    }
}

/// A simple brake so a stuck button or a loop can never run up someone's AI bill: at most 20 short AI texts per 10 minutes.
enum AIThrottle {
    nonisolated(unsafe) private static var stamps: [Date] = []
    static let limit = 20
    static let window: TimeInterval = 600

    static func allow(now: Date = Date()) -> Bool {
        stamps = stamps.filter { now.timeIntervalSince($0) < window }
        guard stamps.count < limit else { return false }
        stamps.append(now)
        return true
    }

    static func reset() { stamps = [] }
}
