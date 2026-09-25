import SwiftUI

/// Exercises, sets, reps and weight for a strength workout.
struct StrengthEditor: View {
    let member: Member
    @Binding var exercises: [StrengthExercise]
    @Environment(TrackingStore.self) private var tracking
    @State private var savingTemplate = false
    @State private var templateName = ""
    @AppStorage("strengthUsesPounds") private var pounds = false
    @State private var newName = ""

    var body: some View {
        Section {
            Picker("Weight unit", selection: $pounds) {
                Text("kg").tag(false)
                Text("lb").tag(true)
            }
            .pickerStyle(.segmented)
        } header: { Text("Strength") }

        Section {
            let mine = tracking.templates(for: member)
            Menu {
                if mine.isEmpty { Text("No templates yet") }
                ForEach(mine) { t in
                    Button("\(t.name) (\(t.exercises.count) exercises)") { exercises = t.exercises.map { StrengthExercise(name: $0.name, sets: $0.sets) } }
                }
            } label: { Label("Start from a template", systemImage: "square.on.square") }
            if !exercises.isEmpty {
                Button { templateName = ""; savingTemplate = true } label: { Label("Save these exercises as a template", systemImage: "square.and.arrow.down") }
            }
            if !mine.isEmpty {
                Menu {
                    ForEach(mine) { t in Button(t.name, role: .destructive) { Task { await tracking.deleteTemplate(t) } } }
                } label: { Label("Delete a template", systemImage: "trash") }
            }
        } footer: {
            Text("A template keeps the exercises, sets, reps and weights. Apply it on any day, then change, add or remove exercises for that day.")
        }
        .alert("Name this template", isPresented: $savingTemplate) {
            TextField("e.g. Push day", text: $templateName)
            Button("Save") { Task { await tracking.saveTemplate(name: templateName, exercises: exercises, for: member) } }
            Button("Cancel", role: .cancel) {}
        }

        ForEach($exercises) { $exercise in
            Section {
                ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, _ in
                    HStack(spacing: 10) {
                        Text("Set \(index + 1)").font(.subheadline).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                        TextField("Reps", value: repsBinding($exercise, index), format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: .infinity)
                        Text("reps").font(.footnote).foregroundStyle(.secondary)
                        TextField("Weight", value: weightBinding($exercise, index), format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: .infinity)
                        Text(pounds ? "lb" : "kg").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .onDelete { exercise.sets.remove(atOffsets: $0) }
                Button {
                    let last = exercise.sets.last ?? StrengthSet(reps: 10, weightKg: 0)
                    exercise.sets.append(last)
                } label: { Label("Add set", systemImage: "plus.circle") }
            } header: {
                HStack {
                    Text(exercise.name)
                    Spacer()
                    Button(role: .destructive) { exercises.removeAll { $0.id == exercise.id } } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Remove \(exercise.name)")
                }
            }
        }

        Section {
            HStack {
                TextField("Add an exercise", text: $newName).textInputAutocapitalization(.words)
                Button("Add") { add(newName) }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(StrengthMath.commonExercises.filter { name in !exercises.contains { $0.name == name } }, id: \.self) { name in
                        Button(name) { add(name) }.buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                    }
                }
            }
        } footer: {
            if !exercises.isEmpty {
                let sets = StrengthMath.totalSets(exercises), reps = StrengthMath.totalReps(exercises)
                let volume = StrengthMath.display(kg: StrengthMath.volumeKg(exercises), pounds: pounds)
                Text("\(sets) sets \u{00B7} \(reps) reps \u{00B7} \(volume) \(pounds ? "lb" : "kg") lifted in total")
            }
        }
    }

    private func add(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, exercises.count < 30 else { return }
        exercises.append(StrengthExercise(name: trimmed, sets: [StrengthSet(reps: 10, weightKg: 0)]))
        newName = ""
    }

    private func repsBinding(_ e: Binding<StrengthExercise>, _ i: Int) -> Binding<Int> {
        Binding(get: { i < e.wrappedValue.sets.count ? e.wrappedValue.sets[i].reps : 0 },
                set: { if i < e.wrappedValue.sets.count { e.wrappedValue.sets[i].reps = max($0, 0) } })
    }

    private func weightBinding(_ e: Binding<StrengthExercise>, _ i: Int) -> Binding<Double> {
        Binding(get: {
            guard i < e.wrappedValue.sets.count else { return 0 }
            let kg = e.wrappedValue.sets[i].weightKg
            return pounds ? (kg / StrengthMath.kgPerLb * 10).rounded() / 10 : kg
        }, set: {
            guard i < e.wrappedValue.sets.count else { return }
            e.wrappedValue.sets[i].weightKg = max(pounds ? $0 * StrengthMath.kgPerLb : $0, 0)
        })
    }
}

enum StrengthSummary {
    /// " · 3 exercises, 9 sets" for the workout row on Today, or nothing.
    static func text(_ exercises: [StrengthExercise]?) -> String {
        guard let exercises, !exercises.isEmpty else { return "" }
        let n = exercises.count
        return " \u{00B7} \(n) exercise\(n == 1 ? "" : "s"), \(StrengthMath.totalSets(exercises)) sets"
    }
}
