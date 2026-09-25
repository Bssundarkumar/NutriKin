import SwiftUI

/// What was done in one workout: each exercise with its sets, reps and weight, and the totals.
struct WorkoutDetailView: View {
    let workout: Workout
    let onEdit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("strengthUsesPounds") private var pounds = false

    private var exercises: [StrengthExercise] { workout.exercises ?? [] }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("When", value: workout.doneAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Time", value: "\(workout.minutes) min \u{00B7} \(workout.intensity.title)")
                    LabeledContent("Calories", value: "about \(workout.caloriesBurned) kcal")
                    if !exercises.isEmpty {
                        LabeledContent("Totals", value: "\(StrengthMath.totalSets(exercises)) sets \u{00B7} \(StrengthMath.totalReps(exercises)) reps \u{00B7} \(StrengthMath.display(kg: StrengthMath.volumeKg(exercises), pounds: pounds)) \(pounds ? "lb" : "kg")")
                    }
                    if let note = workout.note { LabeledContent("Note", value: note) }
                }
                ForEach(exercises) { ex in
                    Section(ex.name) {
                        ForEach(Array(ex.sets.enumerated()), id: \.offset) { i, set in
                            HStack {
                                Text("Set \(i + 1)").foregroundStyle(.secondary)
                                Spacer()
                                Text("\(set.reps) reps \u{00B7} \(StrengthMath.display(kg: set.weightKg, pounds: pounds)) \(pounds ? "lb" : "kg")")
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .softList()
            .navigationTitle(workout.workoutKind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if workout.source != "health" {
                    ToolbarItem(placement: .confirmationAction) { Button("Edit") { dismiss(); onEdit() } }
                }
            }
        }
    }
}
