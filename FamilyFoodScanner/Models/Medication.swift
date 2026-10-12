import Foundation

/// A medicine one family member takes, typed in by the family. NutriKin records and reminds; it never
/// checks doses or interactions.
struct Medication: Identifiable, Codable, Hashable {
    var id = UUID()
    var householdId: UUID?
    var memberId: UUID
    var name: String
    var dose: String?
    var notes: String?
    /// Local times of day as "HH:MM" (24 hour).
    var times: [String] = ["08:00"]
    /// ISO weekdays: 1 = Monday ... 7 = Sunday.
    var daysOfWeek: [Int] = Array(1...7)
    var active = true

    var isEveryDay: Bool { Set(daysOfWeek) == Set(1...7) }
}

enum DoseStatus: String, Codable, Hashable { case taken, skipped }

/// One dose the family marked as taken or skipped.
struct DoseRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var householdId: UUID?
    var medicationId: UUID
    var memberId: UUID
    var dueAt: Date
    var status: DoseStatus
    var takenAt = Date()
}

/// A dose that is due at a set time on a given day, and where it stands.
struct ScheduledDose: Identifiable, Hashable {
    enum State: Hashable {
        /// Not due yet.
        case upcoming
        /// Due now, or within the last hour: time to take it.
        case due
        /// More than an hour ago and nobody marked it.
        case missed
        case taken
        case skipped
    }

    let medication: Medication
    let dueAt: Date
    var record: DoseRecord?
    var state: State
    var id: String { "\(medication.id.uuidString)-\(Int(dueAt.timeIntervalSince1970))" }
}
