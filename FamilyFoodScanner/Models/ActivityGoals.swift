import Foundation

/// Step and workout goals: the person's own, or a general starting point they can accept.
enum ActivityGoals {
    /// General guidance only (roughly WHO / common public-health targets), not a prescription.
    static func suggested(for member: Member) -> (steps: Int, weeklyMinutes: Int) {
        let age = member.age ?? (member.isManagedByParent ? 10 : 35)
        if age < 18 { return (10_000, 420) }          // about an hour of play a day
        if age >= 65 { return (6_000, 150) }
        return (8_000, 150)
    }

    /// Monday 00:00 of the week containing `date`.
    static func weekStart(_ date: Date = Date(), calendar: Calendar = .current) -> Date {
        var cal = calendar; cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    static func weeklyMinutes(_ workouts: [Workout], since start: Date) -> Int {
        workouts.filter { $0.doneAt >= start }.reduce(0) { $0 + $1.minutes }
    }

    /// 0...1 for a progress bar; nil when there's no goal.
    static func fraction(done: Int, goal: Int?) -> Double? {
        guard let goal, goal > 0 else { return nil }
        return min(Double(max(done, 0)) / Double(goal), 1)
    }
}

/// A child's day of active play against the usual one-hour-a-day guidance, and a week of stars.
enum KidActivity {
    static let dailyGoalMinutes = 60

    static func minutes(_ workouts: [Workout], on day: Date, calendar: Calendar = .current) -> Int {
        workouts.filter { calendar.isDate($0.doneAt, inSameDayAs: day) }.reduce(0) { $0 + $1.minutes }
    }

    struct Day: Identifiable, Equatable {
        var date: Date
        var minutes: Int
        var id: Date { date }
        var earnedStar: Bool { minutes >= KidActivity.dailyGoalMinutes }
    }

    /// Monday to Sunday of the week containing `today`; days that haven't happened yet have no minutes.
    static func week(_ workouts: [Workout], today: Date = Date(), calendar: Calendar = .current) -> [Day] {
        let start = ActivityGoals.weekStart(today, calendar: calendar)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map {
            Day(date: $0, minutes: minutes(workouts, on: $0, calendar: calendar))
        }
    }

    static func stars(_ days: [Day]) -> Int { days.filter(\.earnedStar).count }

    /// A friendly line: always encouraging, never a failure.
    static func message(name: String, todayMinutes: Int) -> String {
        let left = max(dailyGoalMinutes - todayMinutes, 0)
        if left == 0 { return "\(name) got today's star! An hour of play is a big win." }
        if todayMinutes == 0 { return "A little play today? \(dailyGoalMinutes) minutes earns a star." }
        return "\(todayMinutes) minutes so far. \(left) more for today's star."
    }
}
