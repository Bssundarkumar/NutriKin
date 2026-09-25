import Foundation

/// A repeating weekly activity, for example swimming on Tuesday and Thursday at 5pm.
struct ActivitySchedule: Identifiable, Codable, Hashable {
    var id = UUID()
    var householdId: UUID?
    var memberId: UUID
    var kind: String
    var label: String?
    var minutes = 60
    /// Local time of day, "HH:MM".
    var time = "17:00"
    /// ISO weekdays: 1 = Monday ... 7 = Sunday.
    var daysOfWeek: [Int] = []
    var remind = true
    var active = true

    var workoutKind: WorkoutKind { WorkoutKind(rawValue: kind) ?? .other }
    var title: String { (label?.isEmpty == false ? label : nil) ?? workoutKind.title }
}

enum ScheduleMath {
    static func occurs(_ s: ActivitySchedule, on day: Date, calendar: Calendar = .current) -> Bool {
        s.active && s.daysOfWeek.contains(MedicationSchedule.isoWeekday(of: day, calendar: calendar))
    }

    /// Today's items for a person, earliest first.
    static func items(_ all: [ActivitySchedule], for memberID: UUID, on day: Date, calendar: Calendar = .current) -> [ActivitySchedule] {
        all.filter { $0.memberId == memberID && occurs($0, on: day, calendar: calendar) }.sorted { $0.time < $1.time }
    }

    /// Done once a workout of that kind has been logged that day.
    static func isLogged(_ s: ActivitySchedule, workouts: [Workout], on day: Date, calendar: Calendar = .current) -> Bool {
        workouts.contains { $0.memberId == s.memberId && $0.kind == s.kind && calendar.isDate($0.doneAt, inSameDayAs: day) }
    }

    static func daysText(_ days: [Int]) -> String {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let set = Set(days.filter { (1...7).contains($0) })
        if set.count == 7 { return "Every day" }
        if set == [1, 2, 3, 4, 5] { return "Weekdays" }
        if set == [6, 7] { return "Weekends" }
        return set.sorted().map { names[$0 - 1] }.joined(separator: ", ")
    }

    static func timeText(_ time: String) -> String {
        guard let t = MedicationSchedule.parseTime(time) else { return time }
        var c = DateComponents(); c.hour = t.hour; c.minute = t.minute
        return (Calendar.current.date(from: c) ?? Date()).formatted(date: .omitted, time: .shortened)
    }
}
