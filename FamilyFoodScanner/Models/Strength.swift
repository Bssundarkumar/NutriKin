import Foundation

/// One set: how many reps at what weight (always stored in kilograms).
struct StrengthSet: Codable, Hashable {
    var reps: Int
    var weightKg: Double
    /// nil for older workouts; saved sets can be unlocked and edited.
    var isSaved: Bool? = nil
}

struct StrengthExercise: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var sets: [StrengthSet]

    private enum CodingKeys: String, CodingKey { case name, sets }

    init(name: String, sets: [StrengthSet]) { self.name = name; self.sets = sets }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        sets = try c.decode([StrengthSet].self, forKey: .sets)
    }

    var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }
    /// Weight times reps, summed over the sets.
    var volumeKg: Double { sets.reduce(0) { $0 + Double($1.reps) * $1.weightKg } }
}

enum StrengthMath {
    static let commonExercises = ["Bench press", "Squat", "Deadlift", "Overhead press", "Barbell row", "Pull-up", "Push-up",
                                  "Lat pulldown", "Bicep curl", "Tricep extension", "Lunge", "Leg press", "Plank"]
    static let kgPerLb = 0.45359237

    static func adjustedReps(_ value: Int, by delta: Int) -> Int { min(max(value + delta, 0), 999) }

    static func adjustedWeight(_ value: Double, by delta: Double, pounds: Bool) -> Double {
        min(max(((value + delta) * 100).rounded() / 100, 0), pounds ? 1000 / kgPerLb : 1000)
    }

    /// A new session uses the values from the source, with every set editable.
    static func forReuse(_ exercises: [StrengthExercise]) -> [StrengthExercise] {
        exercises.map { ex in
            StrengthExercise(name: ex.name, sets: ex.sets.map { StrengthSet(reps: $0.reps, weightKg: $0.weightKg) })
        }
    }

    /// About 2.5 minutes a set counts the lift and the rest after it, rounded to 5 minutes, at least 5.
    static func estimatedMinutes(sets: Int) -> Int { max(5, Int((Double(sets) * 2.5 / 5).rounded()) * 5) }

    static func totalSets(_ e: [StrengthExercise]) -> Int { e.reduce(0) { $0 + $1.sets.count } }
    static func totalReps(_ e: [StrengthExercise]) -> Int { e.reduce(0) { $0 + $1.totalReps } }
    static func volumeKg(_ e: [StrengthExercise]) -> Double { e.reduce(0) { $0 + $1.volumeKg } }

    /// Drops blank names and empty sets, clamps values and caps the list, so what is stored is always sane.
    static func cleaned(_ e: [StrengthExercise]) -> [StrengthExercise] {
        e.compactMap { ex in
            let name = AIGuardrails.sanitize(ex.name, max: 60)
            let sets = ex.sets.filter { $0.reps > 0 }.prefix(30).map {
                StrengthSet(reps: min($0.reps, 999), weightKg: min(max($0.weightKg, 0), 1000), isSaved: $0.isSaved)
            }
            return name.isEmpty || sets.isEmpty ? nil : StrengthExercise(name: name, sets: Array(sets))
        }.prefix(30).map { $0 }
    }

    static func display(kg: Double, pounds: Bool) -> String {
        let v = pounds ? kg / kgPerLb : kg
        return v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}

/// A saved set of exercises (with the sets, reps and weights used last time) to start a strength workout from.
struct WorkoutTemplate: Identifiable, Codable, Hashable {
    var id = UUID()
    var householdId: UUID?
    var memberId: UUID
    var name: String
    var exercises: [StrengthExercise]
}

/// A protected, account-scoped local draft. Saving a set doesn't publish an unfinished workout.
enum StrengthDraftStore {
    struct Draft: Codable {
        var exercises: [StrengthExercise]
        var intensity: WorkoutIntensity
        var note: String
    }

    static func url(user: UUID, member: UUID, workout: UUID?) -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StrengthDrafts", isDirectory: true)
        return root.appendingPathComponent("\(user)-\(member)-\(workout?.uuidString ?? "new").json")
    }

    static func load(from url: URL) -> Draft? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Draft.self, from: data)
    }

    static func save(_ draft: Draft, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func remove(at url: URL) { try? FileManager.default.removeItem(at: url) }
}
