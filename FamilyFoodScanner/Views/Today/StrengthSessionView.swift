import SwiftUI

/// The strength panel: everything about one strength session on its own screen. Start from a template or a past
/// session, build it exercise by exercise (by muscle group), edit sets, reps and weight, and save.
struct StrengthSessionView: View {
    let member: Member
    var editing: Workout? = nil
    /// Exercises to start from, for example copied from a buddy's workout.
    var prefill: [StrengthExercise]? = nil
    /// Called after a new session is saved, so the caller can show the cheer.
    var onSaved: ((Workout) -> Void)? = nil
    @Environment(TrackingStore.self) private var tracking
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @AppStorage("strengthUsesPounds") private var pounds = false

    @State private var exercises: [StrengthExercise] = []
    @State private var intensity: WorkoutIntensity = .moderate
    @State private var note = ""
    @State private var prefilled = false
    @State private var isSaving = false
    @State private var message: String?

    private var clean: [StrengthExercise] { StrengthMath.cleaned(exercises) }
    private var sets: Int { StrengthMath.totalSets(clean) }
    private var minutes: Int { StrengthMath.estimatedMinutes(sets: sets) }
    private var kcal: Int { WorkoutEstimator.calories(kind: .strength, intensity: intensity, minutes: minutes, weightKg: member.weightKg) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 0) {
                        stat("\(clean.count)", "exercises")
                        stat("\(sets)", "sets")
                        stat("\(StrengthMath.totalReps(clean))", "reps")
                        stat(StrengthMath.display(kg: StrengthMath.volumeKg(clean), pounds: pounds), pounds ? "lb lifted" : "kg lifted")
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                }

                StrengthEditor(member: member, exercises: $exercises)

                Section {
                    Picker("Effort", selection: $intensity) { ForEach(WorkoutIntensity.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    LabeledContent("Time", value: sets == 0 ? "\u{2013}" : "about \(minutes) min")
                    if !TodayLayout.isChild(member) { LabeledContent("Calories", value: sets == 0 ? "\u{2013}" : "about \(kcal) kcal") }
                    TextField("Note (optional)", text: $note)
                } header: { Text("This session") } footer: {
                    Text("Time comes from your sets and rest between them. Calories are an estimate from your weight\(member.weightKg == nil ? " (70 kg assumed; add it in the Family tab)" : "") and effort.")
                }
                if let message { Section { Text(message).font(.footnote).foregroundStyle(.red) } }
            }
            .softList()
            .navigationTitle(editing == nil ? "Strength" : "Edit strength")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(isSaving ? "Saving\u{2026}" : "Save") { save() }.disabled(isSaving || sets == 0) }
            }
            .onAppear {
                guard !prefilled else { return }
                prefilled = true
                if let e = editing { exercises = e.exercises ?? []; intensity = e.intensity; note = e.note ?? "" }
                else if let prefill { exercises = prefill }
                else if let sample = Demo.strengthSample { exercises = sample }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        guard sets > 0 else { return }
        isSaving = true
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        if var changed = editing {
            changed.kind = WorkoutKind.strength.rawValue; changed.minutes = minutes; changed.intensity = intensity
            changed.caloriesBurned = kcal; changed.note = trimmed.isEmpty ? nil : trimmed; changed.exercises = clean
            Task {
                if await tracking.update(changed) { UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss() }
                else { message = tracking.errorMessage; isSaving = false }
            }
            return
        }
        let workout = Workout(householdId: family.householdId, memberId: member.id, doneAt: tracking.timestampForNewItem,
                              kind: WorkoutKind.strength.rawValue, minutes: minutes, intensity: intensity, caloriesBurned: kcal,
                              note: trimmed.isEmpty ? nil : trimmed, exercises: clean)
        Task {
            if await tracking.add(workout) { UINotificationFeedbackGenerator().notificationOccurred(.success); onSaved?(workout); dismiss() }
            else { message = tracking.errorMessage; isSaving = false }
        }
    }
}
