import Foundation

/// One set: how many reps at what weight (always stored in kilograms).
struct StrengthSet: Codable, Hashable {
    var reps: Int
    var weightKg: Double
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
                StrengthSet(reps: min($0.reps, 999), weightKg: min(max($0.weightKg, 0), 1000))
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
