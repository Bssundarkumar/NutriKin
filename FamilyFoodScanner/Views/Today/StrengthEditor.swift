import SwiftUI

/// Exercises, sets, reps and weight for a strength workout.
struct StrengthEditor: View {
    let member: Member
    @Binding var exercises: [StrengthExercise]
    @Environment(TrackingStore.self) private var tracking
    @Environment(CustomExerciseStore.self) private var customExercises
    @State private var savingTemplate = false
    @State private var templateName = ""
    @State private var group: ExerciseLibrary.Group? = ExerciseLibrary.groups.first { $0.name == "Chest" }
    @AppStorage("strengthUsesPounds") private var pounds = false
    @State private var applied: WorkoutTemplate?
    @State private var pendingTemplate: WorkoutTemplate?
    @State private var addingExercise = false
    @AppStorage("strengthWeightIncrement") private var weightIncrement = 2.5

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 10) {
                Menu {
                    ForEach(tracking.templates(for: member)) { t in
                        Button(t.name) { if exercises.isEmpty { use(t, replacing: true) } else { pendingTemplate = t } }
                    }
                    ForEach(tracking.recentStrength(for: member).prefix(10)) { w in
                        Button(pastLabel(w)) { exercises = StrengthMath.forReuse(w.exercises ?? []) }
                    }
                    if tracking.templates(for: member).isEmpty && tracking.recentStrength(for: member).isEmpty {
                        Text("Your saved workouts will appear here")
                    }
                } label: {
                    shortcut("Reuse a past workout", "Apply exercises, sets and weights", "clock.arrow.circlepath")
                }
                Menu {
                    Button("Save as a template", systemImage: "square.and.arrow.down") { templateName = ""; savingTemplate = true }
                        .disabled(exercises.isEmpty)
                    if let applied, !sameTemplate(applied) {
                        Button("Update \"\(applied.name)\"") {
                            Task { await tracking.updateTemplate(applied, exercises: exercises); self.applied = tracking.templates.first { $0.id == applied.id } }
                        }
                    }
                    ForEach(tracking.templates(for: member)) { t in
                        Button("Delete \"\(t.name)\"", role: .destructive) { Task { await tracking.deleteTemplate(t) } }
                    }
                } label: { shortcut("Manage templates", "Create and edit your workout templates", "list.bullet.rectangle") }
            }.buttonStyle(.plain)

            HStack(spacing: 16) {
                Text("Weight unit").readableFont(15, weight: .semibold, design: .default)
                unitPicker
            }.strengthSurface(padding: 6)
            Menu {
                ForEach([0.5, 1.0, 2.5, 5.0, 10.0], id: \.self) { step in
                    Button("\(step.formatted()) \(pounds ? "lb" : "kg")") { weightIncrement = step }
                }
            } label: {
                Label("Weight step: \(weightIncrement.formatted()) \(pounds ? "lb" : "kg")", systemImage: "plusminus")
                    .readableFont(15).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }

            Button { addingExercise = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "plus").readableFont(26, weight: .regular, design: .default).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(StrengthStyle.green.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add exercise").readableFont(17, weight: .bold, design: .default)
                        Text("Search or pick from muscle groups").readableFont(15, weight: .regular, design: .default).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary)
                }.strengthSurface()
            }.buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ExerciseLibrary.groups) { g in
                        Button { group = g; addingExercise = true } label: {
                            Text(g.name).readableFont(15, weight: .semibold, design: .default)
                                .foregroundStyle(group == g ? .white : Color.secondary)
                                .padding(.horizontal, 17).padding(.vertical, 9)
                                .background(group == g ? StrengthStyle.green : Color(.secondarySystemFill), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }

            ForEach($exercises) { $exercise in
                VStack(spacing: 7) {
                    HStack(spacing: 14) {
                        HStack(spacing: 2) {
                            Image(systemName: "ellipsis").rotationEffect(.degrees(90))
                            Image(systemName: "ellipsis").rotationEffect(.degrees(90))
                        }.readableFont(15, weight: .bold, design: .default).foregroundStyle(.secondary).frame(width: 12)
                        Text(exercise.name).readableFont(17, weight: .bold, design: .default).lineLimit(2)
                        Spacer(minLength: 0)
                        Menu {
                            Button("Move up", systemImage: "arrow.up") { move(exercise.id, by: -1) }
                            Button("Move down", systemImage: "arrow.down") { move(exercise.id, by: 1) }
                            ForEach(exercise.sets.indices, id: \.self) { index in
                                Button("Remove set \(index + 1)", role: .destructive) { exercise.sets.remove(at: index) }
                            }
                        } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 44, height: 44) }
                        Button(role: .destructive) { exercises.removeAll { $0.id == exercise.id } } label: {
                            Image(systemName: "trash").foregroundStyle(.red).frame(width: 44, height: 44)
                        }.accessibilityLabel("Remove \(exercise.name)")
                    }
                    ForEach(exercise.sets.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Set \(index + 1)").readableFont(15, weight: .semibold)
                                Spacer()
                                Button {
                                    exercise.sets[index].isSaved = exercise.sets[index].isSaved == true ? false : true
                                } label: {
                                    Label(exercise.sets[index].isSaved == true ? "Edit" : "Save set",
                                          systemImage: exercise.sets[index].isSaved == true ? "pencil" : "checkmark.circle")
                                        .readableFont(15, weight: .semibold)
                                        .frame(minHeight: 44)
                                }.buttonStyle(.plain).foregroundStyle(Theme.brand)
                                    .disabled(exercise.sets[index].isSaved != true && exercise.sets[index].reps <= 0)
                                    .accessibilityLabel("\(exercise.sets[index].isSaved == true ? "Edit" : "Save") \(exercise.name), set \(index + 1)")
                                Button(role: .destructive) { exercise.sets.remove(at: index) } label: {
                                    Image(systemName: "trash").frame(width: 44, height: 44)
                                }.buttonStyle(.plain).foregroundStyle(.red)
                                    .accessibilityLabel("Delete \(exercise.name), set \(index + 1)")
                            }
                            if exercise.sets[index].isSaved == true {
                                Label("\(exercise.sets[index].reps) reps · \(StrengthMath.display(kg: exercise.sets[index].weightKg, pounds: pounds)) \(pounds ? "lb" : "kg") · Saved",
                                      systemImage: "checkmark.circle.fill")
                                    .readableFont(17, weight: .semibold).foregroundStyle(Theme.brand)
                            } else {
                                ReadableStack(spacing: 8) {
                                    numberControl("Reps", value: repsBinding($exercise, index), exercise: exercise.name, set: index + 1)
                                    weightControl(value: weightBinding($exercise, index), exercise: exercise.name, set: index + 1)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(.tertiarySystemFill).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        .slideToDelete { exercise.sets.remove(at: index) }
                        .id("\(exercise.id)-\(index)-\(exercise.sets.count)")
                    }
                    Button {
                        guard exercise.sets.count < 30 else { return }
                        var next = exercise.sets.last ?? StrengthSet(reps: 10, weightKg: 0)
                        next.isSaved = nil
                        exercise.sets.append(next)
                    } label: {
                        Label("Add set", systemImage: "plus.circle.fill").readableFont(15, weight: .semibold, design: .default)
                            .foregroundStyle(.green).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color.green.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }.strengthSurface()
            }
            if group?.name == "Chest", !exercises.contains(where: { $0.name == "Push-up" }) {
                Button { add("Push-up") } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "ellipsis").rotationEffect(.degrees(90)).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Push-up").readableFont(17, weight: .bold, design: .default)
                            Text("Bodyweight exercise").readableFont(15, weight: .regular, design: .default).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary)
                    }.strengthSurface()
                }.buttonStyle(.plain)
            }

        }
        .confirmationDialog("You already have exercises in this workout", isPresented: Binding(get: { pendingTemplate != nil }, set: { if !$0 { pendingTemplate = nil } }), titleVisibility: .visible) {
            Button("Replace them") { if let t = pendingTemplate { use(t, replacing: true) } }
            Button("Add to them") { if let t = pendingTemplate { use(t, replacing: false) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Name this template", isPresented: $savingTemplate) {
            TextField("e.g. Push day", text: $templateName)
            Button("Save") { Task { await tracking.saveTemplate(name: templateName, exercises: exercises, for: member) } }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            if Demo.isOn && CommandLine.arguments.contains("-demoExercisePicker") {
                try? await Task.sleep(for: .milliseconds(700))
                addingExercise = true
            }
        }
        .fullScreenCover(isPresented: $addingExercise) {
            ExercisePickerView(member: member, exercises: $exercises, initialGroup: group ?? ExerciseLibrary.groups[0])
        }
    }

    private var unitPicker: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { value in
                Button { pounds = value } label: {
                    Text(value ? "lb" : "kg").readableFont(15, weight: .semibold, design: .default)
                        .foregroundStyle(pounds == value ? .white : Color.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(pounds == value ? StrengthStyle.green : .clear, in: Capsule())
                }.buttonStyle(.plain)
            }
        }.background(Color(.secondarySystemFill), in: Capsule())
    }

    private func shortcut(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).readableFont(21, weight: .regular, design: .default).foregroundStyle(.green)
                .frame(width: 35, height: 35).background(Color.green.opacity(0.05), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).readableFont(17, weight: .semibold).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).readableFont(15).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").readableFont(15, weight: .regular, design: .default).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .strengthSurface(tint: .green)
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = exercises.firstIndex(where: { $0.id == id }), exercises.indices.contains(index + offset) else { return }
        exercises.swapAt(index, index + offset)
    }

    private func use(_ t: WorkoutTemplate, replacing: Bool) {
        let fresh = StrengthMath.forReuse(t.exercises)
        if replacing { exercises = fresh } else { exercises += fresh.filter { f in !exercises.contains { $0.name == f.name } } }
        applied = t; pendingTemplate = nil
    }

    /// Whether the workout still matches the template it started from.
    private func sameTemplate(_ t: WorkoutTemplate) -> Bool {
        let a = StrengthMath.cleaned(exercises).map { [$0.name] + $0.sets.map { "\($0.reps)x\($0.weightKg)" } }
        let b = StrengthMath.cleaned(t.exercises).map { [$0.name] + $0.sets.map { "\($0.reps)x\($0.weightKg)" } }
        return a == b
    }

    private func pastLabel(_ w: Workout) -> String {
        let names = (w.exercises ?? []).map(\.name)
        let list = names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " +\(names.count - 3)" : "")
        return "\(w.doneAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))): \(list)"
    }

    private func add(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, exercises.count < 30 else { return }
        exercises.append(StrengthExercise(name: trimmed, sets: Array(repeating: StrengthSet(reps: 10, weightKg: 0), count: 3)))
    }

    private func numberControl(_ title: String, value: Binding<Int>, exercise: String, set: Int) -> some View {
        VStack(spacing: 4) {
            Text(title).readableFont(15).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                Button { value.wrappedValue = StrengthMath.adjustedReps(value.wrappedValue, by: -1) } label: {
                    Image(systemName: "minus").frame(width: 44, height: 44)
                }.disabled(value.wrappedValue == 0).accessibilityLabel("Decrease reps for \(exercise), set \(set)")
                TextField("Reps", value: value, format: .number).keyboardType(.numberPad)
                    .multilineTextAlignment(.center).frame(minWidth: 34)
                    .accessibilityLabel("\(exercise), set \(set), reps")
                Button { value.wrappedValue = StrengthMath.adjustedReps(value.wrappedValue, by: 1) } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }.disabled(value.wrappedValue >= 999).accessibilityLabel("Increase reps for \(exercise), set \(set)")
            }.buttonStyle(.plain).readableFont(17, weight: .semibold)
        }.frame(maxWidth: .infinity)
    }

    private func weightControl(value: Binding<Double>, exercise: String, set: Int) -> some View {
        VStack(spacing: 4) {
            Text("Weight (\(pounds ? "lb" : "kg"))").readableFont(15).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                Button { value.wrappedValue = StrengthMath.adjustedWeight(value.wrappedValue, by: -weightIncrement, pounds: pounds) } label: {
                    Image(systemName: "minus").frame(width: 44, height: 44)
                }.disabled(value.wrappedValue <= 0).accessibilityLabel("Decrease weight for \(exercise), set \(set)")
                TextField("Weight", value: value, format: .number).keyboardType(.decimalPad)
                    .multilineTextAlignment(.center).frame(minWidth: 34)
                    .accessibilityLabel("\(exercise), set \(set), weight in \(pounds ? "pounds" : "kilograms")")
                Button { value.wrappedValue = StrengthMath.adjustedWeight(value.wrappedValue, by: weightIncrement, pounds: pounds) } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }.accessibilityLabel("Increase weight for \(exercise), set \(set)")
            }.buttonStyle(.plain).readableFont(17, weight: .semibold)
        }.frame(maxWidth: .infinity)
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

/// Searchable exercise catalog, shared by every muscle group.
private struct ExercisePickerView: View {
    let member: Member
    @Binding var exercises: [StrengthExercise]
    let initialGroup: ExerciseLibrary.Group
    @Environment(\.dismiss) private var dismiss
    @Environment(CustomExerciseStore.self) private var customExercises
    @State private var selectedGroup: ExerciseLibrary.Group?
    @State private var search = ""
    @State private var showAll = false
    @State private var detail: String?

    private var group: ExerciseLibrary.Group { selectedGroup ?? initialGroup }
    private let popularChest = ["Bench press", "Incline dumbbell press", "Decline bench press", "Dumbbell fly", "Cable fly", "Machine chest press"]
    private var names: [String] {
        let all = group.exercises + customExercises.exercises(for: group.name)
        return search.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(search) }
    }
    private var popular: [String] {
        let top = group.name == "Chest" ? popularChest : Array(group.exercises.prefix(6))
        return top.filter { names.contains($0) }
    }
    private var other: [String] { names.filter { !popular.contains($0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    groupTabs
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search \(group.name.lowercased()) exercises", text: $search)
                            .readableFont(17, weight: .regular, design: .default).autocorrectionDisabled()
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .accessibilityLabel("Clear search")
                        }
                    }.padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    if !popular.isEmpty {
                        sectionHeader("Popular")
                        ForEach(popular, id: \.self) { exerciseRow($0) }
                    }
                    if !other.isEmpty {
                        sectionHeader("Other \(group.name.lowercased()) exercises")
                        ForEach(showAll || !search.isEmpty ? other : Array(other.prefix(2)), id: \.self) { exerciseRow($0) }
                    }
                    if names.isEmpty {
                        Text("No matching exercises").readableFont(19, weight: .semibold, relativeTo: .headline).padding(.top, 12)
                    }
                    if !search.trimmingCharacters(in: .whitespaces).isEmpty && !names.contains(where: { $0.caseInsensitiveCompare(search) == .orderedSame }) {
                        Button {
                            let name = search.trimmingCharacters(in: .whitespaces)
                            customExercises.add(name, to: group)
                            add(name)
                        } label: { Label("Add \"\(search)\" as a custom exercise", systemImage: "plus.circle.fill") }
                            .readableFont(16, weight: .regular, relativeTo: .footnote).padding(12)
                    }
                }.padding(.horizontal, 12).padding(.bottom, 20)
            }
            .background(AppBackground())
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .toolbar(.hidden, for: .navigationBar)
            .tint(StrengthStyle.green)
            .onAppear {
                if Demo.isOn {
                    let args = CommandLine.arguments
                    if let index = args.firstIndex(of: "-demoExerciseGroup"), args.indices.contains(index + 1) {
                        selectedGroup = ExerciseLibrary.groups.first { $0.name == args[index + 1] }
                    }
                    showAll = args.contains("-demoAllExercises")
                }
            }
            .sheet(isPresented: Binding(get: { detail != nil }, set: { if !$0 { detail = nil } })) {
                if let name = detail {
                    VStack(spacing: 18) {
                        thumbnail(name).frame(width: 200, height: 150).clipShape(RoundedRectangle(cornerRadius: 20))
                        Text(name).readableFont(24, weight: .bold, relativeTo: .title2)
                        Text(group.name).foregroundStyle(.secondary)
                        HStack { ForEach(tags(name), id: \.self) { tag($0) } }
                        Button(exercises.contains { $0.name == name } ? "Added to workout" : "Add to workout") { add(name); detail = nil }
                            .buttonStyle(.borderedProminent).disabled(exercises.contains { $0.name == name })
                        Button("Done") { detail = nil }
                    }.padding().presentationDetents([.medium])
                }
            }
        }
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 4) {
                Text("\(group.name) Exercises").readableFont(24, weight: .bold, design: .default)
                Text("Pick an exercise to add to your workout").readableFont(15, weight: .regular, design: .default).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 14)
            Button { dismiss() } label: {
                Image(systemName: "arrow.left").readableFont(20, weight: .regular, design: .default)
                    .frame(width: 44, height: 44).background(Color(.secondarySystemGroupedBackground), in: Circle())
            }.accessibilityLabel("Back to strength workout").padding(.top, 10)
        }.padding(.horizontal, 12)
    }

    private var groupTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ExerciseLibrary.groups.sorted { lhs, rhs in
                    let order = ["Chest", "Back", "Shoulders", "Arms", "Legs", "Core", "Glutes", "Full body"]
                    return (order.firstIndex(of: lhs.name) ?? 9) < (order.firstIndex(of: rhs.name) ?? 9)
                }) { item in
                    Button { selectedGroup = item; search = ""; showAll = false } label: {
                        VStack(spacing: 6) {
                            Image(systemName: tabSymbol(item.name)).readableFont(21, weight: .semibold, design: .default)
                            Text(item.name).readableFont(15, weight: .semibold, design: .default)
                        }.foregroundStyle(group == item ? .white : Color.secondary)
                            .padding(.horizontal, 12).frame(minWidth: 76, minHeight: 76)
                            .background(group == item ? StrengthStyle.green : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityAddTraits(group == item ? .isSelected : [])
                }
            }.padding(.vertical, 2)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).readableFont(18, weight: .bold, design: .default)
            Spacer()
            Button(showAll ? "Show less" : "See all") { withAnimation { showAll.toggle() } }
                .readableFont(16, weight: .semibold, design: .default)
        }.padding(.horizontal, 4).padding(.top, 6)
    }

    private func exerciseRow(_ name: String) -> some View {
        let added = exercises.contains { $0.name == name }
        return VStack(alignment: .leading, spacing: 10) {
        ReadableStack(spacing: 12) {
            Button { detail = name } label: {
                thumbnail(name).frame(width: 76, height: 62).clipShape(RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityLabel("View \(name)")
            Button { detail = name } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).readableFont(17, weight: .bold, design: .default).foregroundStyle(.primary).lineLimit(2)
                    Text(group.name).readableFont(15, weight: .regular, design: .default).foregroundStyle(.secondary)

                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            HStack(spacing: 4) {
            Button { add(name) } label: {
                Image(systemName: added ? "checkmark" : "plus").readableFont(21, weight: .medium, design: .default).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(StrengthStyle.green.gradient, in: Circle())
            }.buttonStyle(.plain).disabled(added || exercises.count >= 30)
                .accessibilityLabel(added ? "\(name) added" : "Add \(name)")
            Button { detail = name } label: {
                Image(systemName: "chevron.right").readableFont(15, weight: .regular, design: .default).foregroundStyle(.secondary)
            }.buttonStyle(.plain).frame(minWidth: 44, minHeight: 44).accessibilityLabel("View \(name) details")
            }
        }
        ReadableTagFlow(spacing: 5) {
            ForEach(tags(name), id: \.self) { tag($0) }
        }
        }.padding(10).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func tag(_ text: String) -> some View {
        Text(text).readableFont(15, relativeTo: .caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color(.secondarySystemFill), in: Capsule())
    }

    @ViewBuilder private func thumbnail(_ name: String) -> some View {
        if let image = ExerciseIllustrations.image(for: name) {
            Image(uiImage: image).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: UIColor(white: 0.95, alpha: 1)))
        } else {
            // Custom exercises can be added by name without a bundled illustration.
            ZStack {
                Color(.secondarySystemFill)
                Image(systemName: group.symbol).font(.system(size: 32)).foregroundStyle(StrengthStyle.green)
            }
        }
    }

    private func tags(_ name: String) -> [String] {
        let chest: [String: [String]] = [
            "Bench press": ["Barbell", "Compound", "Intermediate"],
            "Incline dumbbell press": ["Dumbbell", "Compound", "Intermediate"],
            "Decline bench press": ["Barbell", "Compound", "Intermediate"],
            "Dumbbell fly": ["Dumbbell", "Isolation", "Beginner"],
            "Cable fly": ["Cable", "Isolation", "Beginner"],
            "Machine chest press": ["Machine", "Compound", "Beginner"],
            "Push-up": ["Bodyweight", "Compound", "Beginner"],
            "Chest dip": ["Bodyweight", "Compound", "Intermediate"]
        ]
        if let tags = chest[name] { return tags }
        let lower = name.lowercased()
        let equipment = lower.contains("dumbbell") ? "Dumbbell" : lower.contains("cable") ? "Cable" : lower.contains("machine") ? "Machine" : lower.contains("kettlebell") ? "Kettlebell" : lower.contains("band") ? "Band" : "Variation"
        return [equipment, group.name]
    }

    private func tabSymbol(_ name: String) -> String {
        switch name {
        case "Chest": "dumbbell.fill"
        case "Back": "figure.rower"
        case "Shoulders": "figure.strengthtraining.traditional"
        case "Arms": "figure.boxing"
        case "Legs": "figure.walk"
        case "Core": "figure.core.training"
        default: "figure.flexibility"
        }
    }

    private func add(_ name: String) {
        guard exercises.count < 30, !exercises.contains(where: { $0.name == name }) else { return }
        exercises.append(StrengthExercise(name: name, sets: Array(repeating: StrengthSet(reps: 10, weightKg: 0), count: 3)))
    }
}

/// Named, cached thumbnails for every built-in exercise. The explicit sheet order stays stable
/// when the catalog is reordered, and only visible thumbnails need to be decoded.
@MainActor
enum ExerciseIllustrations {
    struct Sheet {
        let asset: String
        let columns: Int
        let rows: Int
        let names: [String]
        var rowBreaks: [Double] = []
    }

    static let sheets: [Sheet] = [
        Sheet(asset: "ChestExerciseAtlas", columns: 2, rows: 4, names: [
            "Bench press", "Incline dumbbell press", "Decline bench press", "Dumbbell fly",
            "Cable fly", "Machine chest press", "Push-up", "Chest dip"
        ]),
        Sheet(asset: "StrengthExerciseAtlas", columns: 4, rows: 4, names: [
            "Deadlift", "Barbell row", "Seated cable row", "Lat pulldown",
            "Overhead press", "Lateral raise", "Seated dumbbell shoulder press", "Face pull",
            "Bicep curl", "Hammer curl", "Tricep pushdown", "Overhead tricep extension",
            "Squat", "Lunge", "Leg press", "Hip thrust"
        ], rowBreaks: [0, 307.0 / 1254, 636.0 / 1254, 953.0 / 1254, 1]),
        Sheet(asset: "ExerciseChestVariations", columns: 4, rows: 3, names: [
            "Incline bench press", "Dumbbell press", "Incline push-up", "Decline push-up",
            "Knee push-up", "Wide-grip bench press", "Close-grip dumbbell press", "Single-arm cable chest press",
            "Low-to-high cable fly", "High-to-low cable fly", "Dumbbell floor press", "Squeeze press"
        ]),
        Sheet(asset: "ExerciseBackVariations", columns: 4, rows: 4, names: [
            "Dumbbell row", "T-bar row", "Pull-up", "Chin-up",
            "Back extension", "Assisted pull-up", "Neutral-grip pull-up", "Wide-grip lat pulldown",
            "Underhand lat pulldown", "Single-arm lat pulldown", "Chest-supported row", "Seal row",
            "Single-arm cable row", "Inverted row", "Straight-arm pulldown"
        ]),
        Sheet(asset: "ExerciseShouldersVariations", columns: 4, rows: 4, names: [
            "Dumbbell shoulder press", "Arnold press", "Front raise", "Rear delt fly",
            "Upright row", "Shrug", "Standing dumbbell shoulder press", "Landmine press",
            "Single-arm overhead press", "Cable lateral raise", "Lean-away lateral raise", "Reverse pec deck",
            "Plate front raise", "Pike push-up"
        ]),
        Sheet(asset: "ExerciseArmsVariations", columns: 4, rows: 4, names: [
            "Preacher curl", "Concentration curl", "Skull crusher", "Close-grip bench press",
            "Tricep dip", "EZ-bar curl", "Incline dumbbell curl", "Cable curl",
            "Spider curl", "Reverse curl", "Zottman curl", "Rope tricep pushdown",
            "Single-arm tricep pushdown", "Dumbbell tricep kickback", "Diamond push-up"
        ]),
        Sheet(asset: "ExerciseLegsVariations", columns: 4, rows: 6, names: [
            "Front squat", "Goblet squat", "Hack squat", "Walking lunge",
            "Bulgarian split squat", "Step-up", "Leg extension", "Leg curl",
            "Romanian deadlift", "Calf raise", "Wall sit", "Reverse lunge",
            "Lateral lunge", "Split squat", "Smith machine squat", "Single-leg press",
            "Seated leg curl", "Lying leg curl", "Single-leg Romanian deadlift", "Seated calf raise",
            "Single-leg calf raise", "Heel-elevated goblet squat"
        ], rowBreaks: [0, 254.0 / 1536, 510.0 / 1536, 768.0 / 1536, 1017.0 / 1536, 1260.0 / 1536, 1]),
        Sheet(asset: "ExerciseGlutesVariations", columns: 4, rows: 4, names: [
            "Glute bridge", "Cable kickback", "Sumo deadlift", "Donkey kick",
            "Good morning", "Single-leg hip thrust", "Single-leg glute bridge", "Banded glute bridge",
            "Frog pump", "Fire hydrant", "Banded lateral walk", "Hip abduction machine",
            "Cable pull-through", "Dumbbell hip thrust"
        ]),
        Sheet(asset: "ExerciseCoreVariations", columns: 4, rows: 6, names: [
            "Plank", "Side plank", "Crunch", "Sit-up",
            "Leg raise", "Russian twist", "Cable crunch", "Ab wheel",
            "Mountain climber", "Dead bug", "Bicycle crunch", "Reverse crunch",
            "Hanging knee raise", "Hanging leg raise", "Pallof press", "Bird dog",
            "Hollow hold", "Heel tap", "Cable woodchop", "Weighted plank",
            "Side plank hip lift"
        ], rowBreaks: [0, 237.0 / 1536, 472.0 / 1536, 707.0 / 1536, 951.0 / 1536, 1198.0 / 1536, 1]),
        Sheet(asset: "ExerciseFullbodyVariations", columns: 4, rows: 4, names: [
            "Burpee", "Kettlebell swing", "Clean and press", "Thruster",
            "Farmer's carry", "Turkish get-up", "Dumbbell thruster", "Kettlebell clean and press",
            "Single-arm kettlebell swing", "Suitcase carry", "Overhead carry", "Bear crawl",
            "Battle ropes", "Medicine ball slam", "Sled push", "Sled pull"
        ]),
    ]

    static var names: Set<String> { Set(sheets.flatMap(\.names)) }
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    static func image(for name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let sheet = sheets.first(where: { $0.names.contains(name) }),
              let index = sheet.names.firstIndex(of: name),
              let atlas = UIImage(named: sheet.asset)?.cgImage else { return nil }
        let width = Double(atlas.width) / Double(sheet.columns)
        let row = index / sheet.columns
        let top = sheet.rowBreaks.isEmpty ? Double(row) / Double(sheet.rows) : sheet.rowBreaks[row]
        let bottom = sheet.rowBreaks.isEmpty ? Double(row + 1) / Double(sheet.rows) : sheet.rowBreaks[row + 1]
        // A slight inset removes the dividers without cutting into the exercise itself.
        let frame = CGRect(x: Double(index % sheet.columns) * width,
                           y: top * Double(atlas.height),
                           width: width, height: (bottom - top) * Double(atlas.height))
            .insetBy(dx: 2, dy: 2).integral
        guard let cell = atlas.cropping(to: frame) else { return nil }
        let image = UIImage(cgImage: cell)
        cache.setObject(image, forKey: name as NSString, cost: cell.bytesPerRow * cell.height)
        return image
    }
}
