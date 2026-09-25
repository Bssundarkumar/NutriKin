import Foundation

/// Works out which doses fall on a day and whether each has been taken. Pure, so it's tested.
enum MedicationSchedule {
    /// How long after the due time a dose still counts as "due now" rather than "missed".
    static let dueWindow: TimeInterval = 60 * 60

    /// "08:30" as (8, 30), or nil if it isn't a valid 24-hour time.
    static func parseTime(_ text: String) -> (hour: Int, minute: Int)? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    static func format(hour: Int, minute: Int) -> String { String(format: "%02d:%02d", hour, minute) }

    /// Times cleaned up for saving: valid, unique and in order.
    static func normalized(_ times: [String]) -> [String] {
        Array(Set(times.compactMap { parseTime($0).map { format(hour: $0.hour, minute: $0.minute) } })).sorted()
    }

    /// Monday = 1 ... Sunday = 7 (Foundation numbers Sunday as 1).
    static func isoWeekday(of date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7 + 1
    }

    /// Foundation's weekday number (Sunday = 1) for an ISO weekday (Monday = 1).
    static func calendarWeekday(fromISO iso: Int) -> Int { iso % 7 + 1 }

    static func dueDate(time: String, on day: Date, calendar: Calendar = .current) -> Date? {
        guard let t = parseTime(time) else { return nil }
        return calendar.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: day)
    }

    /// All doses for the day, earliest first.
    static func doses(for medications: [Medication], on day: Date, records: [DoseRecord], now: Date = Date(),
                      calendar: Calendar = .current) -> [ScheduledDose] {
        let weekday = isoWeekday(of: day, calendar: calendar)
        var out: [ScheduledDose] = []
        for med in medications where med.active && med.daysOfWeek.contains(weekday) {
            for time in normalized(med.times) {
                guard let due = dueDate(time: time, on: day, calendar: calendar) else { continue }
                let record = records.first { $0.medicationId == med.id && abs($0.dueAt.timeIntervalSince(due)) < 60 }
                let state: ScheduledDose.State
                if let record { state = record.status == .taken ? .taken : .skipped }
                else if due > now { state = .upcoming }
                else if now.timeIntervalSince(due) <= dueWindow { state = .due }
                else { state = .missed }
                out.append(ScheduledDose(medication: med, dueAt: due, record: record, state: state))
            }
        }
        return out.sorted { ($0.dueAt, $0.medication.name) < ($1.dueAt, $1.medication.name) }
    }

    /// How many of the day's doses are marked taken, out of all scheduled (skipped ones still count as scheduled).
    static func summary(_ doses: [ScheduledDose]) -> (taken: Int, total: Int) {
        (doses.filter { $0.state == .taken }.count, doses.count)
    }
}
