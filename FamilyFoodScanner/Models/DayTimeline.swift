import Foundation

/// One thing that happened at a point in the day, for the timeline ("ladder") view — food, activity,
/// medication, and quick check-ins all collapsed into one time-ordered list.
struct TimelineEvent: Identifiable, Hashable {
    enum Kind: Hashable { case food, workout, medicationTaken, medicationSkipped, water, hunger, mood }

    let id: String
    let at: Date
    let kind: Kind
    let title: String
    let detail: String
    let symbol: String
    let tint: ColorToken

    /// A `Codable`/`Hashable`-friendly stand-in for `Color`, mapped to an actual `Color` in the view layer.
    enum ColorToken: Hashable { case brand, orange, blue, purple, pink, indigo, red, gray }
}

enum DayTimeline {
    /// Builds the day's events for one member, oldest first. Pure and easy to test: no view code, no I/O.
    static func events(
        foodEntries: [FoodEntry],
        workouts: [Workout],
        doses: [ScheduledDose],
        waterTimes: [Date],
        hungerEntries: [(at: Date, value: Int)],
        moodEntries: [(at: Date, value: Int)]
    ) -> [TimelineEvent] {
        var out: [TimelineEvent] = []

        for e in foodEntries {
            out.append(TimelineEvent(
                id: "food-\(e.id)", at: e.eatenAt, kind: .food, title: e.label,
                detail: e.calories > 0 ? "\(Int(e.calories.rounded())) kcal" : "",
                symbol: symbol(for: e.source), tint: .brand))
        }

        for w in workouts {
            out.append(TimelineEvent(
                id: "workout-\(w.id)", at: w.doneAt, kind: .workout, title: w.workoutKind.title,
                detail: "\(w.minutes) min \u{00B7} \(w.caloriesBurned) kcal",
                symbol: "flame.fill", tint: .orange))
        }

        for d in doses where d.state == .taken || d.state == .skipped {
            let at = d.record?.takenAt ?? d.dueAt
            out.append(TimelineEvent(
                id: "dose-\(d.id)", at: at, kind: d.state == .taken ? .medicationTaken : .medicationSkipped,
                title: d.medication.name, detail: d.state == .taken ? "Taken" : "Skipped",
                symbol: d.state == .taken ? "pills.fill" : "pills", tint: d.state == .taken ? .blue : .gray))
        }

        for t in waterTimes {
            out.append(TimelineEvent(id: "water-\(t.timeIntervalSince1970)", at: t, kind: .water,
                                      title: "Water", detail: "1 glass", symbol: "drop.fill", tint: .blue))
        }

        for h in hungerEntries {
            out.append(TimelineEvent(id: "hunger-\(h.at.timeIntervalSince1970)", at: h.at, kind: .hunger,
                                      title: "Hunger", detail: DailyCheckInStore.hungerLabels[h.value],
                                      symbol: "fork.knife", tint: .orange))
        }

        for m in moodEntries {
            out.append(TimelineEvent(id: "mood-\(m.at.timeIntervalSince1970)", at: m.at, kind: .mood,
                                      title: "Mood", detail: DailyCheckInStore.moodLabels[m.value],
                                      symbol: "face.smiling", tint: .pink))
        }

        return out.sorted { $0.at < $1.at }
    }

    private static func symbol(for source: FoodSource) -> String {
        switch source {
        case .scan: "barcode.viewfinder"
        case .plate: "camera.viewfinder"
        case .ai: "sparkles"
        case .manual: "pencil"
        }
    }
}
