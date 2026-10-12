import Foundation

/// Workout time counts each session once; exercise load is external weight, not body weight.
enum BuddyAnalytics {
    struct DayPoint: Identifiable, Equatable {
        let day: Date
        let value: Double
        var id: Date { day }
    }
    static func unique(_ workouts: [Workout]) -> [Workout] {
        Array(Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values)
    }
    static func time(_ workouts: [Workout], start: Date, end: Date, calendar: Calendar = .current) -> [DayPoint] {
        let grouped = Dictionary(grouping: unique(workouts).filter { $0.doneAt >= start && $0.doneAt < end }) {
            calendar.startOfDay(for: $0.doneAt)
        }
        var day = calendar.startOfDay(for: start)
        var points: [DayPoint] = []
        while day < end {
            points.append(DayPoint(day: day, value: Double(grouped[day, default: []].reduce(0) { $0 + $1.minutes })))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return points
    }
    static func weight(_ workouts: [Workout], exercise: String, calendar: Calendar = .current) -> [DayPoint] {
        var maximums: [Date: Double] = [:]
        for workout in unique(workouts) {
            let day = calendar.startOfDay(for: workout.doneAt)
            for item in workout.exercises ?? [] where item.name == exercise {
                for set in item.sets where set.reps > 0 && set.weightKg > 0 {
                    maximums[day] = max(maximums[day] ?? 0, set.weightKg)
                }
            }
        }
        return maximums.map { DayPoint(day: $0.key, value: $0.value) }.sorted { $0.day < $1.day }
    }
    static func volume(_ workouts: [Workout], exercise: String, calendar: Calendar = .current) -> [DayPoint] {
        var totals: [Date: Double] = [:]
        for workout in unique(workouts) {
            let day = calendar.startOfDay(for: workout.doneAt)
            for item in workout.exercises ?? [] where item.name == exercise {
                for set in item.sets where set.reps > 0 && set.weightKg > 0 {
                    totals[day, default: 0] += Double(set.reps) * set.weightKg
                }
            }
        }
        return totals.map { DayPoint(day: $0.key, value: $0.value) }.sorted { $0.day < $1.day }
    }
}
