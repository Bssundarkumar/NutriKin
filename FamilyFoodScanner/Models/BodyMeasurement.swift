import Foundation

/// One dated height and/or weight reading for a person.
struct BodyMeasurement: Identifiable, Codable, Hashable {
    var id = UUID()
    var householdId: UUID?
    var memberId: UUID
    /// "yyyy-MM-dd", as the database stores a plain date.
    var measuredOn: String
    var heightCm: Double?
    var weightKg: Double?

    var date: Date { Self.formatter.date(from: measuredOn) ?? Date() }

    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func day(_ date: Date) -> String { formatter.string(from: date) }
}

enum GrowthMath {
    /// Oldest first, which is what a chart wants.
    static func sorted(_ list: [BodyMeasurement]) -> [BodyMeasurement] { list.sorted { $0.measuredOn < $1.measuredOn } }

    static func latest(_ list: [BodyMeasurement]) -> BodyMeasurement? { list.max { $0.measuredOn < $1.measuredOn } }

    /// Change in weight from the first to the last reading that has one, or nil with fewer than two.
    static func weightChange(_ list: [BodyMeasurement]) -> Double? {
        let w = sorted(list).compactMap(\.weightKg)
        guard w.count >= 2, let first = w.first, let last = w.last else { return nil }
        return last - first
    }

    static func heightChange(_ list: [BodyMeasurement]) -> Double? {
        let h = sorted(list).compactMap(\.heightCm)
        guard h.count >= 2, let first = h.first, let last = h.last else { return nil }
        return last - first
    }

    static func bmi(_ m: BodyMeasurement) -> Double? {
        guard let w = m.weightKg, let h = m.heightCm, h > 0 else { return nil }
        return w / pow(h / 100, 2)
    }

    /// Plausible human values only, so a typo can't wreck a chart.
    static func isValid(heightCm: Double?, weightKg: Double?) -> Bool {
        guard heightCm != nil || weightKg != nil else { return false }
        if let h = heightCm, !(20...260).contains(h) { return false }
        if let w = weightKg, !(1...500).contains(w) { return false }
        return true
    }
}
