import Foundation
import SwiftUI

/// One thing that happened at a point in the day, for the timeline ("ladder") view — food, activity,
/// medication, and quick check-ins all collapsed into one time-ordered list.
struct TimelineEvent: Identifiable, Hashable {
    enum Kind: Hashable { case food, workout, medicationTaken, medicationSkipped, water, hunger, mood, weight, sleep }

    let id: String
    let at: Date
    let kind: Kind
    let title: String
    var detail: String
    let symbol: String
    let tint: ColorToken
    /// Set only for `.food`/`.workout`, so a tap can look the real entry back up to edit it — the
    /// event itself stays a flat, display-only value, not a wrapper around every possible model type.
    var foodEntryId: UUID?
    var workoutId: UUID?

    /// A `Codable`/`Hashable`-friendly stand-in for `Color` (a `Color` itself isn't Hashable the way we'd
    /// need here). One place to map a token to the real color, so every ladder view agrees on it.
    enum ColorToken: Hashable {
        case brand, green, orange, blue, purple, pink, indigo, red, gray

        var color: Color {
            switch self {
            case .brand: Theme.brand
            case .green: .green
            case .orange: .orange
            case .blue: .blue
            case .purple: .purple
            case .pink: .pink
            case .indigo: .indigo
            case .red: .red
            case .gray: .gray
            }
        }
    }
}

enum DayTimeline {
    /// Builds the day's events for one member, oldest first. Pure and easy to test: no view code, no I/O.
    /// `sleepHours`/`sleepAnchor` have no single "log" moment of their own (Health reports a total, not a
    /// tap), so they're anchored to the start of the day — representing the night just gone, not "now".
    static func events(
        foodEntries: [FoodEntry],
        workouts: [Workout],
        doses: [ScheduledDose],
        waterTimes: [Date],
        hungerEntries: [(at: Date, value: Int)],
        moodEntries: [(at: Date, value: Int)],
        weightEntries: [(at: Date, kg: Double)] = [],
        sleepHours: Double? = nil,
        sleepAnchor: Date = Calendar.current.startOfDay(for: .now)
    ) -> [TimelineEvent] {
        var out: [TimelineEvent] = []

        for e in foodEntries {
            out.append(TimelineEvent(
                id: "food-\(e.id)", at: e.eatenAt, kind: .food, title: e.label,
                detail: e.calories > 0 ? "\(Int(e.calories.rounded())) kcal" : "",
                symbol: symbol(for: e.source), tint: mealTint(e.eatenAt), foodEntryId: e.id))
        }

        for w in workouts {
            out.append(TimelineEvent(
                id: "workout-\(w.id)", at: w.doneAt, kind: .workout, title: "Burn \u{00B7} \(w.workoutKind.title)",
                detail: "\(w.minutes) min, \(w.caloriesBurned) kcal",
                symbol: "flame.fill", tint: .green, workoutId: w.id))
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

        for w in weightEntries {
            let display = w.kg.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w.kg)) : String(format: "%.1f", w.kg)
            out.append(TimelineEvent(id: "weight-\(w.at.timeIntervalSince1970)", at: w.at, kind: .weight,
                                      title: "Weight", detail: "\(display) kg", symbol: "scalemass.fill", tint: .purple))
        }

        if let sleepHours {
            out.append(TimelineEvent(id: "sleep-\(sleepAnchor.timeIntervalSince1970)", at: sleepAnchor, kind: .sleep,
                                      title: "Sleep", detail: String(format: "%.1f h", sleepHours),
                                      symbol: "bed.double.fill", tint: .indigo))
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

    /// Colors each food ring by roughly when it was eaten, like a tracker's per-meal colored dots —
    /// purely visual grouping, nothing is stored or computed from this.
    private static func mealTint(_ at: Date) -> TimelineEvent.ColorToken {
        switch Calendar.current.component(.hour, from: at) {
        case 4..<11: .green
        case 11..<16: .orange
        case 16..<21: .brand
        default: .purple
        }
    }
}
