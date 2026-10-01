import Foundation
import Observation

/// Quick daily check-ins that don't need a backend table of their own: water glasses, hunger and mood.
/// Kept on-device (UserDefaults) per person per day — a lightweight log for the Today screen, not
/// something shared with the rest of the family or synced across devices.
@MainActor
@Observable
final class DailyCheckInStore {
    private static let key = "dailyCheckIns"
    static let waterGoalGlasses = 8
    static let moodLabels = ["😞", "🙁", "😐", "🙂", "😄"]
    static let hungerLabels = ["Stuffed", "Full", "Satisfied", "Hungry", "Starving"]

    private struct DayEntry: Codable { var waterGlasses = 0; var hunger: Int?; var mood: Int? }
    /// "<memberId>_<yyyy-MM-dd>" -> that day's entry.
    private var byDay: [String: DayEntry]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: DayEntry].self, from: data) {
            byDay = decoded
        } else {
            byDay = [:]
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f
    }()

    private func keyFor(_ memberId: UUID, _ day: Date) -> String { "\(memberId)_\(Self.dayFormatter.string(from: day))" }

    func waterGlasses(for memberId: UUID, day: Date) -> Int { byDay[keyFor(memberId, day)]?.waterGlasses ?? 0 }
    func hunger(for memberId: UUID, day: Date) -> Int? { byDay[keyFor(memberId, day)]?.hunger }
    func mood(for memberId: UUID, day: Date) -> Int? { byDay[keyFor(memberId, day)]?.mood }

    func addWater(_ delta: Int, for memberId: UUID, day: Date) {
        let key = keyFor(memberId, day)
        var entry = byDay[key] ?? DayEntry()
        entry.waterGlasses = min(max(entry.waterGlasses + delta, 0), 40)
        byDay[key] = entry
        persist()
    }

    func setHunger(_ value: Int?, for memberId: UUID, day: Date) {
        let key = keyFor(memberId, day)
        var entry = byDay[key] ?? DayEntry()
        entry.hunger = value
        byDay[key] = entry
        persist()
    }

    func setMood(_ value: Int?, for memberId: UUID, day: Date) {
        let key = keyFor(memberId, day)
        var entry = byDay[key] ?? DayEntry()
        entry.mood = value
        byDay[key] = entry
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(byDay) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
