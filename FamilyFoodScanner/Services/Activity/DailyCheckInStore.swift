import Foundation
import Observation

/// Quick daily check-ins that don't need a backend table of their own: water glasses, hunger and mood.
/// Kept on-device (UserDefaults) per person per day — a lightweight log for the Today screen, not
/// something shared with the rest of the family or synced across devices.
///
/// Each tap is kept as its own timestamped entry (not just a running total), so the day's timeline can
/// show exactly when each glass of water or mood check-in happened, not just an end-of-day count.
@MainActor
@Observable
final class DailyCheckInStore {
    private static let key = "dailyCheckInsV2"
    static let waterGoalGlasses = 8
    static let moodLabels = ["😞", "🙁", "😐", "🙂", "😄"]
    static let hungerLabels = ["Stuffed", "Full", "Satisfied", "Hungry", "Starving"]

    private struct RatingEntry: Codable, Hashable { var at: Date; var value: Int }
    private struct DayEntry: Codable { var water: [Date] = []; var hunger: [RatingEntry] = []; var mood: [RatingEntry] = [] }
    /// "<memberId>_<yyyy-MM-dd>" -> that day's entries.
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

    func waterGlasses(for memberId: UUID, day: Date) -> Int { byDay[keyFor(memberId, day)]?.water.count ?? 0 }
    /// The most recent rating logged that day, if any — what the quick-log pill shows.
    func hunger(for memberId: UUID, day: Date) -> Int? { byDay[keyFor(memberId, day)]?.hunger.last?.value }
    func mood(for memberId: UUID, day: Date) -> Int? { byDay[keyFor(memberId, day)]?.mood.last?.value }

    /// Every glass logged that day, in order — for the day's timeline.
    func waterTimes(for memberId: UUID, day: Date) -> [Date] { byDay[keyFor(memberId, day)]?.water ?? [] }
    func hungerEntries(for memberId: UUID, day: Date) -> [(at: Date, value: Int)] { (byDay[keyFor(memberId, day)]?.hunger ?? []).map { ($0.at, $0.value) } }
    func moodEntries(for memberId: UUID, day: Date) -> [(at: Date, value: Int)] { (byDay[keyFor(memberId, day)]?.mood ?? []).map { ($0.at, $0.value) } }

    func addWater(_ delta: Int, for memberId: UUID, day: Date) {
        let key = keyFor(memberId, day)
        var entry = byDay[key] ?? DayEntry()
        if delta > 0 {
            for _ in 0..<delta where entry.water.count < 40 { entry.water.append(.now) }
        } else if delta < 0 {
            entry.water.removeLast(min(-delta, entry.water.count))
        }
        byDay[key] = entry
        persist()
    }

    func setHunger(_ value: Int?, for memberId: UUID, day: Date) {
        let key = keyFor(memberId, day)
        var entry = byDay[key] ?? DayEntry()
        if let value { entry.hunger.append(RatingEntry(at: .now, value: value)) }
        byDay[key] = entry
        persist()
    }

    func setMood(_ value: Int?, for memberId: UUID, day: Date) {
        let key = keyFor(memberId, day)
        var entry = byDay[key] ?? DayEntry()
        if let value { entry.mood.append(RatingEntry(at: .now, value: value)) }
        byDay[key] = entry
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(byDay) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
