import Foundation

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
            "Dumbbell fly", "Cable fly", "Machine chest press", "Push-up", "Chest dip"]),
        Group(name: "Back", symbol: "figure.rower", exercises: [
            "Deadlift", "Barbell row", "Dumbbell row", "T-bar row", "Seated cable row", "Lat pulldown",
            "Pull-up", "Chin-up", "Back extension"]),
        Group(name: "Shoulders", symbol: "figure.arms.open", exercises: [
            "Overhead press", "Dumbbell shoulder press", "Arnold press", "Lateral raise", "Front raise",
            "Rear delt fly", "Face pull", "Upright row", "Shrug"]),
        Group(name: "Arms", symbol: "dumbbell.fill", exercises: [
            "Bicep curl", "Hammer curl", "Preacher curl", "Concentration curl", "Tricep pushdown",
            "Overhead tricep extension", "Skull crusher", "Close-grip bench press", "Tricep dip"]),
        Group(name: "Legs", symbol: "figure.step.training", exercises: [
            "Squat", "Front squat", "Goblet squat", "Hack squat", "Leg press", "Lunge", "Walking lunge",
            "Bulgarian split squat", "Step-up", "Leg extension", "Leg curl", "Romanian deadlift", "Calf raise", "Wall sit"]),
        Group(name: "Glutes", symbol: "figure.flexibility", exercises: [
            "Hip thrust", "Glute bridge", "Cable kickback", "Sumo deadlift", "Donkey kick", "Good morning"]),
        Group(name: "Core", symbol: "figure.core.training", exercises: [
            "Plank", "Side plank", "Crunch", "Sit-up", "Leg raise", "Russian twist", "Cable crunch",
            "Ab wheel", "Mountain climber", "Dead bug"]),
        Group(name: "Full body", symbol: "figure.highintensity.intervaltraining", exercises: [
            "Burpee", "Kettlebell swing", "Clean and press", "Thruster", "Farmer's carry", "Turkish get-up"]),
    ]

    static var all: [String] { groups.flatMap(\.exercises) }
}
