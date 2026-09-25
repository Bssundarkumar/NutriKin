import Foundation
import HealthKit

/// One workout found in the Health app (from an Apple Watch, the iPhone or any fitness app that saves to Health).
struct HealthWorkout: Identifiable, Hashable {
    let id: UUID
    let kind: WorkoutKind
    let start: Date
    let minutes: Int
    let activeKcal: Int?
    let sourceName: String?
}

/// A day's activity as Health has it. Steps and calories are the totals from every source Health knows about.
struct HealthActivity: Equatable {
    var steps: Int?
    var activeKcal: Double?
    var exerciseMinutes: Int?
    var workouts: [HealthWorkout] = []

    var isEmpty: Bool { steps == nil && activeKcal == nil && exerciseMinutes == nil && workouts.isEmpty }
}

enum HealthImport {
    /// The closest of NutriKin's activity types for one of Apple's.
    static func kind(for type: HKWorkoutActivityType) -> WorkoutKind {
        switch type {
        case .walking, .hiking: .walking
        case .running: .running
        case .cycling, .handCycling: .cycling
        case .swimming, .waterPolo: .swimming
        case .yoga, .pilates, .flexibility, .mindAndBody: .yoga
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining, .crossTraining: .strength
        case .highIntensityIntervalTraining: .hiit
        case .dance, .socialDance, .cardioDance: .dance
        case .soccer, .basketball, .tennis, .badminton, .cricket, .baseball, .volleyball, .tableTennis, .rugby, .hockey, .golf, .squash, .handball:
            .sports
        default: .other
        }
    }

    /// Health workouts that haven't been added to the family's log yet. A workout counts as already there if it
    /// was imported from Health before, or if the same kind of activity was typed in starting within 10 minutes.
    static func newWorkouts(from found: [HealthWorkout], existing: [Workout]) -> [HealthWorkout] {
        let imported = Set(existing.compactMap(\.externalId))
        return found.filter { hw in
            if imported.contains(hw.id.uuidString) { return false }
            return !existing.contains { $0.workoutKind == hw.kind && abs($0.doneAt.timeIntervalSince(hw.start)) < 10 * 60 }
        }
    }

    /// A NutriKin workout for a Health one. Uses Health's calories, or an estimate from the person's weight if it has none.
    static func workout(from hw: HealthWorkout, memberId: UUID, householdId: UUID?, weightKg: Double?) -> Workout {
        let kcal = hw.activeKcal ?? WorkoutEstimator.calories(kind: hw.kind, intensity: .moderate, minutes: hw.minutes, weightKg: weightKg)
        return Workout(householdId: householdId, memberId: memberId, doneAt: hw.start, kind: hw.kind.rawValue, minutes: max(hw.minutes, 1),
                       intensity: .moderate, caloriesBurned: kcal, note: hw.sourceName.map { "From \($0)" } ?? "From Apple Health",
                       source: "health", externalId: hw.id.uuidString)
    }
}
