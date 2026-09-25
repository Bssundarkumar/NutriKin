import SwiftUI

private func number(_ text: String) -> Double? {
    Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
}

/// Log something a person ate: describe it and let the AI estimate, or type the numbers.
struct LogFoodSheet: View {
    let member: Member
    @Environment(TrackingStore.self) private var tracking
    @Environment(FamilyStore.self) private var family
    @Environment(AIConnection.self) private var ai
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable { case describe = "Describe", manual = "Type it in" }
    @State private var mode: Mode = .manual
    @State private var showPlate = false
    @State private var description = ""
    @State private var estimate: PlateAnalysis?
    @State private var isEstimating = false
    @State private var message: String?
    @State private var isSaving = false
    @State private var name = ""
    @State private var calories = ""
    @State private var sugar = ""
    @State private var carbs = ""
    @State private var sodium = ""
    @State private var satFat = ""
    @State private var protein = ""
    @State private var fiber = ""
    @State private var fat = ""

    private var canDescribe: Bool { ai.textProvider != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showPlate = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "camera.viewfinder").font(.title2).foregroundStyle(Theme.brand)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan a plate").font(.headline)
                                Text("Take a photo and get calories and nutrients estimated").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                } footer: { Text("Or describe the meal, or type the numbers in below.") }
                if canDescribe {
                    Picker("How", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                }
                if mode == .describe && canDescribe { describeSection } else { manualSection }
                if let message { Section { Text(message).font(.footnote).foregroundStyle(.red) } }
            }
            .softList()
            .navigationTitle("Log food for \(member.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving\u{2026}" : "Log") { save() }.disabled(!canSave || isSaving)
                }
            }
            .onAppear { ai.refreshApple(); if canDescribe { mode = .describe } }
            .sheet(isPresented: $showPlate) { PlateScanView(logFor: member, onLogged: { dismiss() }) }
        }
    }

    private var describeSection: some View {
        Group {
            Section {
                TextField("e.g. 2 rotis, a bowl of dal and a glass of buttermilk", text: $description, axis: .vertical)
                    .lineLimit(3...6)
                Button {
                    estimateNow()
                } label: {
                    HStack { Label(isEstimating ? "Estimating\u{2026}" : "Estimate calories", systemImage: "sparkles"); if isEstimating { Spacer(); ProgressView() } }
                }
                .disabled(isEstimating || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: { Text("What did \(member.name) eat?") } footer: {
                Text("Estimated by \(ai.textProvider == .apple ? "Apple Intelligence on your iPhone" : "your AI"). Check it before logging.")
            }
            if let estimate {
                Section("Estimate") {
                    ForEach(estimate.items) { item in
                        HStack { Text("\(item.name) \u{00B7} \(Int(item.grams)) g"); Spacer(); Text("\(Int(item.calories.rounded())) kcal").foregroundStyle(.secondary) }
                            .font(.subheadline)
                    }
                    let total = MealTotals.of(estimate.items)
                    HStack { Text("Total").fontWeight(.semibold); Spacer(); Text("\(Int(total.calories.rounded())) kcal").fontWeight(.semibold) }
                    if let note = estimate.note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private var manualSection: some View {
        Group {
            Section("Food") {
                TextField("Name, e.g. Banana", text: $name)
                HStack { Text("Calories"); Spacer(); TextField("kcal", text: $calories).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110) }
            }
            Section {
                fieldRow("Sugar", "g", $sugar); fieldRow("Carbs", "g", $carbs); fieldRow("Sodium", "mg", $sodium)
                fieldRow("Saturated fat", "g", $satFat); fieldRow("Total fat", "g", $fat)
                fieldRow("Protein", "g", $protein); fieldRow("Fibre", "g", $fiber)
            } header: { Text("More detail (optional)") } footer: { Text("Leave blank anything you don't know.") }
        }
    }

    private func fieldRow(_ title: String, _ unit: String, _ text: Binding<String>) -> some View {
        HStack { Text(title); Spacer(); TextField(unit, text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110) }
    }

    private var canSave: Bool {
        if mode == .describe && canDescribe { return !(estimate?.items.isEmpty ?? true) }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty && number(calories) != nil
    }

    private func estimateNow() {
        guard let provider = ai.textProvider else { return }
        isEstimating = true; message = nil; estimate = nil
        let llm = provider == .apple ? ai.keyClient : ai.client(for: provider)
        let text = description
        Task {
            defer { isEstimating = false }
            do {
                let result = try await PlateService.estimateFromDescription(text, provider: provider, client: llm)
                if result.items.isEmpty { message = "The AI couldn't find any food in that. Try describing it differently." }
                else { estimate = result }
            } catch { message = error.localizedDescription }
        }
    }

    private func save() {
        isSaving = true
        var entry: FoodEntry
        if mode == .describe && canDescribe, let estimate {
            entry = PortionScaler.entry(for: estimate.items, memberId: member.id, householdId: family.householdId, at: tracking.timestampForNewItem)
            entry.source = .ai
        } else {
            entry = FoodEntry(householdId: family.householdId, memberId: member.id, eatenAt: tracking.timestampForNewItem,
                              label: name.trimmingCharacters(in: .whitespaces), source: .manual,
                              calories: number(calories) ?? 0, sugarG: number(sugar) ?? 0, carbsG: number(carbs) ?? 0,
                              sodiumMg: number(sodium) ?? 0, satFatG: number(satFat) ?? 0, proteinG: number(protein) ?? 0,
                              fiberG: number(fiber) ?? 0, fatG: number(fat) ?? 0)
        }
        Task {
            if await tracking.add(entry) { UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss() }
            else { message = tracking.errorMessage; isSaving = false }
        }
    }
}

/// Log a workout with a calorie estimate the person can adjust.
struct LogWorkoutSheet: View {
    let member: Member
    /// Set to change a workout that's already logged (for example to add another set).
    var editing: Workout? = nil
    @Environment(TrackingStore.self) private var tracking
    @Environment(FamilyStore.self) private var family
    @Environment(AIConnection.self) private var ai
    @Environment(\.dismiss) private var dismiss

    @State private var kind: WorkoutKind = .walking
    @State private var minutes = 30
    @State private var intensity: WorkoutIntensity = .moderate
    @State private var override: Int?
    @State private var note = ""
    @State private var exercises: [StrengthExercise] = []
    @State private var isSaving = false
    @State private var message: String?
    @State private var saved: Workout?
    @State private var cheer = ""
    @State private var cheerIsAI = false
    @State private var idea: String?
    @State private var prefilled = false
    @State private var ideaLoading = false

    /// A strength session is timed by its sets, so the person only enters exercises, not how long each took.
    private var setsDriveTime: Bool { kind == .strength && StrengthMath.totalSets(StrengthMath.cleaned(exercises)) > 0 }
    private var effectiveMinutes: Int {
        setsDriveTime ? StrengthMath.estimatedMinutes(sets: StrengthMath.totalSets(StrengthMath.cleaned(exercises))) : minutes
    }
    private var estimate: Int { WorkoutEstimator.calories(kind: kind, intensity: intensity, minutes: effectiveMinutes, weightKg: member.weightKg) }
    private var burned: Int { override ?? estimate }

    var body: some View {
        if let saved { cheerView(saved) } else {
            formView.onAppear {
                guard let e = editing, !prefilled else { return }
                prefilled = true
                kind = e.workoutKind; minutes = e.minutes; intensity = e.intensity; note = e.note ?? ""
                exercises = e.exercises ?? []; override = e.caloriesBurned
            }
        }
    }

    private var formView: some View {
        NavigationStack {
            Form {
                if ai.textProvider != nil {
                    Section {
                        if let idea { Text(idea).font(.subheadline) }
                        Button {
                            ideaLoading = true
                            Task {
                                idea = await AIQuick.text(rules: DayCoach.workoutIdeaRules,
                                                          user: DayCoach.workoutPrompt(member: member, weekMinutes: tracking.weeklyMinutes(for: member), steps: nil),
                                                          members: family.members, ai: ai)
                                    ?? "Couldn't get an idea right now. A walk you enjoy is always a good start."
                                ideaLoading = false
                            }
                        } label: {
                            Label(ideaLoading ? "Thinking\u{2026}" : (idea == nil ? "Not sure what to do? Get an idea" : "Another idea"), systemImage: "sparkles")
                        }
                        .disabled(ideaLoading)
                    } footer: { if idea != nil { Text("Written by AI. A general idea, not medical advice.") } }
                }
                Section("Activity") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                        ForEach(WorkoutKind.allCases) { k in
                            Button { kind = k; override = nil } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: k.symbol).font(.title3).frame(height: 24)
                                    Text(k.title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(kind == k ? Color.orange.opacity(0.22) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(kind == k ? Color.orange : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(kind == k ? .isSelected : [])
                        }
                    }
                }
                if kind == .strength {
                    StrengthEditor(exercises: $exercises)
                }
                if setsDriveTime {
                    Section {
                        Picker("Effort", selection: $intensity) { ForEach(WorkoutIntensity.allCases) { Text($0.title).tag($0) } }
                            .pickerStyle(.segmented).onChange(of: intensity) { _, _ in override = nil }
                    } header: { Text("How hard") } footer: {
                        Text("Saved as about \(effectiveMinutes) minutes in total, worked out from your sets and rest between them.")
                    }
                } else {
                Section("How long and how hard") {
                    Stepper("\(minutes) minutes", value: $minutes, in: 5...300, step: 5).onChange(of: minutes) { _, _ in override = nil }
                    HStack { ForEach([15, 30, 45, 60], id: \.self) { m in
                        Button("\(m)") { minutes = m; override = nil }.buttonStyle(.bordered).buttonBorderShape(.capsule).tint(minutes == m ? .orange : .gray)
                    } }
                    Picker("Effort", selection: $intensity) { ForEach(WorkoutIntensity.allCases) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented).onChange(of: intensity) { _, _ in override = nil }
                }
                }
                Section {
                    Stepper("\(burned) kcal burned", value: Binding(get: { burned }, set: { override = $0 }), in: 0...3000, step: 10)
                } header: { Text("Calories") } footer: {
                    Text(member.weightKg == nil
                         ? "An estimate for a 70 kg adult. Add \(member.name)'s weight in the Family tab for a better one."
                         : "An estimate for \(Int(member.weightKg ?? 0)) kg. Change it if your watch says otherwise.")
                }
                Section("Note (optional)") { TextField("e.g. Morning walk in the park", text: $note) }
                if let message { Section { Text(message).font(.footnote).foregroundStyle(.red) } }
            }
            .softList()
            .navigationTitle(editing == nil ? "Log workout" : "Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(isSaving ? "Saving\u{2026}" : "Save") { save() }.disabled(isSaving) }
            }
        }
    }

    private func save() {
        isSaving = true
        if var changed = editing {
            changed.kind = kind.rawValue; changed.minutes = effectiveMinutes; changed.intensity = intensity; changed.caloriesBurned = burned
            changed.note = note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note
            changed.exercises = kind == .strength ? StrengthMath.cleaned(exercises) : nil
            Task {
                if await tracking.update(changed) { UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss() }
                else { message = tracking.errorMessage; isSaving = false }
            }
            return
        }
        let workout = Workout(householdId: family.householdId, memberId: member.id, doneAt: tracking.timestampForNewItem,
                              kind: kind.rawValue, minutes: effectiveMinutes, intensity: intensity, caloriesBurned: burned,
                              note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note,
                              exercises: kind == .strength ? StrengthMath.cleaned(exercises) : nil)
        Task {
            if await tracking.add(workout) { UINotificationFeedbackGenerator().notificationOccurred(.success); showCheer(for: workout) }
            else { message = tracking.errorMessage; isSaving = false }
        }
    }

    private func showCheer(for workout: Workout) {
        cheer = WorkoutCoach.fallback(workout: workout, member: member)
        withAnimation(.spring(duration: 0.4)) { saved = workout }
        let minutesToday = tracking.workouts(for: member).reduce(0) { $0 + $1.minutes }
        Task {
            if let text = await WorkoutCoach.aiCheer(workout: workout, member: member, minutesToday: minutesToday, weekMinutes: tracking.weeklyMinutes(for: member), ai: ai, family: family.members) {
                withAnimation(.smooth) { cheer = text; cheerIsAI = true }
            }
        }
    }

    private func cheerView(_ workout: Workout) -> some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "party.popper.fill").font(.system(size: 54)).foregroundStyle(.orange).popIn()
                Text("Workout saved").font(.title2.bold())
                Text(cheer)
                    .font(.body).multilineTextAlignment(.center).padding(.horizontal, 24)
                    .contentTransition(.opacity)
                if cheerIsAI {
                    Label("Written by AI", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).controlSize(.large).padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .background(AppBackground())
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// "I ate this": log a scanned product for one or more family members, with the amount eaten.
struct LogProductSheet: View {
    let product: Product
    @Environment(FamilyStore.self) private var family
    @Environment(TrackingStore.self) private var tracking
    @Environment(\.dismiss) private var dismiss
    @AppStorage("todayMemberID") private var lastMemberID = ""

    @State private var chosen = Set<UUID>()
    @State private var amount = 1.0
    @State private var isSaving = false
    @State private var message: String?

    private var portion: Portion {
        switch PortionScaler.defaultPortion(for: product) { case .servings: .servings(amount); case .grams: .grams(amount) }
    }
    private var isServings: Bool { if case .servings = PortionScaler.defaultPortion(for: product) { true } else { false } }
    private var preview: FoodEntry? { PortionScaler.entry(for: product, portion: portion, memberId: UUID(), householdId: nil) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Who ate it?") {
                    ForEach(family.members) { m in
                        Button {
                            if chosen.contains(m.id) { chosen.remove(m.id) } else { chosen.insert(m.id) }
                        } label: {
                            HStack { Avatar(name: m.name, size: 30); Text(m.name); Spacer()
                                Image(systemName: chosen.contains(m.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(chosen.contains(m.id) ? Theme.brand : .secondary) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section {
                    if isServings {
                        Stepper(String(format: "%.1f serving%@", amount, amount == 1 ? "" : "s"), value: $amount, in: 0.5...10, step: 0.5)
                    } else {
                        Stepper("\(Int(amount)) g", value: $amount, in: 10...2000, step: 10)
                    }
                    if let preview {
                        Text("About \(Int(preview.calories.rounded())) kcal \u{00B7} \(Int(preview.sugarG.rounded())) g sugar \u{00B7} \(Int(preview.sodiumMg.rounded())) mg sodium")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("This product's figures can't be worked out for an amount. Use Log food to type it in.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                } header: { Text(product.name) } footer: {
                    if !product.hasAnyNutrition { Text("This product has no nutrition information, so it will be logged with zero calories.") }
                }
                if let message { Section { Text(message).font(.footnote).foregroundStyle(.red) } }
            }
            .softList()
            .navigationTitle("Log as eaten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving\u{2026}" : "Log") { save() }.disabled(chosen.isEmpty || preview == nil || isSaving)
                }
            }
            .onAppear {
                amount = { if case .grams(let g) = PortionScaler.defaultPortion(for: product) { g } else { 1 } }()
                if chosen.isEmpty, let first = family.members.first(where: { $0.id.uuidString == lastMemberID }) ?? family.members.first { chosen = [first.id] }
            }
        }
    }

    private func save() {
        isSaving = true
        let when = tracking.timestampForNewItem
        Task {
            var failed = false
            for id in chosen {
                guard let entry = PortionScaler.entry(for: product, portion: portion, memberId: id, householdId: family.householdId, at: when) else { continue }
                if await !tracking.add(entry) { failed = true }
            }
            if failed { message = tracking.errorMessage; isSaving = false }
            else { UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss() }
        }
    }
}
