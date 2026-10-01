import Foundation
import Observation

/// Built-in exercises grouped by what they work, so picking "Legs" shows every leg exercise.
enum ExerciseLibrary {
    struct Group: Identifiable, Hashable {
        let name: String
        let symbol: String
        let exercises: [String]
        var id: String { name }
    }

    static let groups: [Group] = [
        Group(name: "Chest", symbol: "figure.strengthtraining.traditional", exercises: [
            "Bench press", "Incline bench press", "Decline bench press", "Dumbbell press", "Incline dumbbell press",
            "Dumbbell fly", "Cable fly", "Machine chest press", "Push-up", "Chest dip", "Incline push-up", "Decline push-up", "Knee push-up", "Wide-grip bench press", "Close-grip dumbbell press", "Single-arm cable chest press", "Low-to-high cable fly", "High-to-low cable fly", "Dumbbell floor press", "Squeeze press"]),
        Group(name: "Back", symbol: "figure.rower", exercises: [
            "Deadlift", "Barbell row", "Dumbbell row", "T-bar row", "Seated cable row", "Lat pulldown",
            "Pull-up", "Chin-up", "Back extension", "Assisted pull-up", "Neutral-grip pull-up", "Wide-grip lat pulldown", "Underhand lat pulldown", "Single-arm lat pulldown", "Chest-supported row", "Seal row", "Single-arm cable row", "Inverted row", "Straight-arm pulldown"]),
        Group(name: "Shoulders", symbol: "figure.arms.open", exercises: [
            "Overhead press", "Dumbbell shoulder press", "Arnold press", "Lateral raise", "Front raise",
            "Rear delt fly", "Face pull", "Upright row", "Shrug", "Seated dumbbell shoulder press", "Standing dumbbell shoulder press", "Landmine press", "Single-arm overhead press", "Cable lateral raise", "Lean-away lateral raise", "Reverse pec deck", "Plate front raise", "Pike push-up"]),
        Group(name: "Arms", symbol: "dumbbell.fill", exercises: [
            "Bicep curl", "Hammer curl", "Preacher curl", "Concentration curl", "Tricep pushdown",
            "Overhead tricep extension", "Skull crusher", "Close-grip bench press", "Tricep dip", "EZ-bar curl", "Incline dumbbell curl", "Cable curl", "Spider curl", "Reverse curl", "Zottman curl", "Rope tricep pushdown", "Single-arm tricep pushdown", "Dumbbell tricep kickback", "Diamond push-up"]),
        Group(name: "Legs", symbol: "figure.step.training", exercises: [
            "Squat", "Front squat", "Goblet squat", "Hack squat", "Leg press", "Lunge", "Walking lunge",
            "Bulgarian split squat", "Step-up", "Leg extension", "Leg curl", "Romanian deadlift", "Calf raise", "Wall sit", "Reverse lunge", "Lateral lunge", "Split squat", "Smith machine squat", "Single-leg press", "Seated leg curl", "Lying leg curl", "Single-leg Romanian deadlift", "Seated calf raise", "Single-leg calf raise", "Heel-elevated goblet squat"]),
        Group(name: "Glutes", symbol: "figure.flexibility", exercises: [
            "Hip thrust", "Glute bridge", "Cable kickback", "Sumo deadlift", "Donkey kick", "Good morning", "Single-leg hip thrust", "Single-leg glute bridge", "Banded glute bridge", "Frog pump", "Fire hydrant", "Banded lateral walk", "Hip abduction machine", "Cable pull-through", "Dumbbell hip thrust"]),
        Group(name: "Core", symbol: "figure.core.training", exercises: [
            "Plank", "Side plank", "Crunch", "Sit-up", "Leg raise", "Russian twist", "Cable crunch",
            "Ab wheel", "Mountain climber", "Dead bug", "Bicycle crunch", "Reverse crunch", "Hanging knee raise", "Hanging leg raise", "Pallof press", "Bird dog", "Hollow hold", "Heel tap", "Cable woodchop", "Weighted plank", "Side plank hip lift"]),
        Group(name: "Full body", symbol: "figure.highintensity.intervaltraining", exercises: [
            "Burpee", "Kettlebell swing", "Clean and press", "Thruster", "Farmer's carry", "Turkish get-up", "Dumbbell thruster", "Kettlebell clean and press", "Single-arm kettlebell swing", "Suitcase carry", "Overhead carry", "Bear crawl", "Battle ropes", "Medicine ball slam", "Sled push", "Sled pull"]),
    ]

    /// Only the exercises that belong to this muscle group. Pass in anyone's custom additions to it too
    /// (e.g. from `CustomExerciseStore`), so a past session built from one still groups correctly even
    /// after the on-device library changes.
    static func only(_ exercises: [StrengthExercise], in group: Group, customNames: [String] = []) -> [StrengthExercise] {
        let names = Set(group.exercises + customNames)
        return exercises.filter { names.contains($0.name) }
    }

    static var all: [String] { groups.flatMap(\.exercises) }
}

/// Exercises someone added themselves under a muscle group that isn't in the built-in library — e.g. a
/// machine specific to their gym. Kept on-device (UserDefaults), since the built-in groups aren't backed
/// by the household's data at all; each person's additions are their own.
@MainActor
@Observable
final class CustomExerciseStore {
    private static let key = "customExercisesByGroup"
    /// Group name -> the names someone's added to it, in the order added.
    private var byGroup: [String: [String]]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            byGroup = decoded
        } else {
            byGroup = [:]
        }
    }

    func exercises(for groupName: String) -> [String] { byGroup[groupName] ?? [] }

    /// Adds a custom exercise to a group, unless it's already there (built-in or custom) under that name.
    func add(_ name: String, to group: ExerciseLibrary.Group) {
        let trimmed = AIGuardrails.sanitize(name, max: 60)
        guard !trimmed.isEmpty else { return }
        let existing = group.exercises + exercises(for: group.name)
        guard !existing.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        byGroup[group.name, default: []].append(trimmed)
        persist()
    }

    func remove(_ name: String, from groupName: String) {
        byGroup[groupName]?.removeAll { $0 == name }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(byGroup) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
