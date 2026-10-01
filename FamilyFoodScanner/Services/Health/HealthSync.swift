import Foundation
import HealthKit

/// Data in Health belongs to the person linked to this iPhone, never the selected family tab.
enum HealthSync {
    static let waterMlPerGlass = 250.0
    static let entryKey = "NutriKinEntryID"
    static let memberKey = "NutriKinMemberID"

    struct Quantity: Codable, Equatable {
        var type: String
        var unit: String
        var value: Double
    }

    struct Write: Codable, Equatable {
        var memberID: UUID
        var key: String
        var version: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        var date: Date
        var quantities: [Quantity] = []
        var workout: Workout?
        var deleted = false
    }

    static func food(_ entry: FoodEntry, deleted: Bool = false) -> Write {
        Write(memberID: entry.memberId, key: "food-\(entry.id)", date: entry.eatenAt, quantities: [
            Quantity(type: HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue, unit: "kcal", value: entry.calories),
            Quantity(type: HKQuantityTypeIdentifier.dietaryCarbohydrates.rawValue, unit: "g", value: entry.carbsG),
            Quantity(type: HKQuantityTypeIdentifier.dietaryProtein.rawValue, unit: "g", value: entry.proteinG),
            Quantity(type: HKQuantityTypeIdentifier.dietaryFatTotal.rawValue, unit: "g", value: entry.fatG),
            Quantity(type: HKQuantityTypeIdentifier.dietarySugar.rawValue, unit: "g", value: entry.sugarG),
            Quantity(type: HKQuantityTypeIdentifier.dietaryFiber.rawValue, unit: "g", value: entry.fiberG),
            Quantity(type: HKQuantityTypeIdentifier.dietaryFatSaturated.rawValue, unit: "g", value: entry.satFatG),
            Quantity(type: HKQuantityTypeIdentifier.dietarySodium.rawValue, unit: "mg", value: entry.sodiumMg),
        ], deleted: deleted)
    }

    static func workout(_ workout: Workout, deleted: Bool = false) -> Write? {
        guard workout.source != "health" else { return nil }
        return Write(memberID: workout.memberId, key: "workout-\(workout.id)", date: workout.doneAt, workout: workout, deleted: deleted)
    }

    static func water(memberID: UUID, day: Date, glasses: Int) -> Write {
        let date = Calendar.current.isDateInToday(day) ? Date() : Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        return Write(memberID: memberID, key: "water-\(memberID)-\(BodyMeasurement.day(day))", date: date,
                     quantities: [Quantity(type: HKQuantityTypeIdentifier.dietaryWater.rawValue, unit: "mL", value: Double(max(glasses, 0)) * waterMlPerGlass)])
    }

    static func measurement(_ row: BodyMeasurement, at date: Date? = nil, deleted: Bool = false) -> Write {
        var values: [Quantity] = []
        if let weight = row.weightKg { values.append(Quantity(type: HKQuantityTypeIdentifier.bodyMass.rawValue, unit: "kg", value: weight)) }
        if let height = row.heightCm { values.append(Quantity(type: HKQuantityTypeIdentifier.height.rawValue, unit: "cm", value: height)) }
        return Write(memberID: row.memberId, key: "measurement-\(row.id)", date: date ?? row.date, quantities: values, deleted: deleted)
    }

    static func metadata(_ write: Write, suffix: String = "") -> [String: Any] {
        [HKMetadataKeySyncIdentifier: "nutrikin.\(write.memberID).\(write.key)\(suffix)",
         HKMetadataKeySyncVersion: NSNumber(value: write.version),
         HKMetadataKeyWasUserEntered: true, entryKey: write.key, memberKey: write.memberID.uuidString]
    }

    static func workoutType(_ kind: WorkoutKind) -> HKWorkoutActivityType {
        switch kind {
        case .walking: .walking
        case .running: .running
        case .cycling: .cycling
        case .swimming: .swimming
        case .yoga: .yoga
        case .strength: .traditionalStrengthTraining
        case .hiit: .highIntensityIntervalTraining
        case .dance: .cardioDance
        case .sports: .other
        default: .other
        }
    }

    /// Merge intervals from overlapping sleep sources instead of counting the same sleep twice.
    static func sleepHours(_ intervals: [DateInterval]) -> Double? {
        let ordered = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard var current = ordered.first else { return nil }
        var seconds = 0.0
        for interval in ordered.dropFirst() {
            if interval.start <= current.end { current = DateInterval(start: current.start, end: max(current.end, interval.end)) }
            else { seconds += current.duration; current = interval }
        }
        return (seconds + current.duration) / 3600
    }

    static func outboxURL(userID: UUID, memberID: UUID) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HealthSync", isDirectory: true).appendingPathComponent("\(userID)-\(memberID).json")
    }

    static func load(from url: URL) -> [String: Write] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Write].self, from: data)) ?? [:]
    }

    static func persist(_ writes: [String: Write], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(writes).write(to: url, options: [.atomic, .completeFileProtection])
    }
}
