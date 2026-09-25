import SwiftUI

/// Add or edit a family member: their vitals, conditions, allergies
/// (built-in or custom) and daily goals.
struct MemberEditView: View {
    enum Mode {
        case add
        case edit(Member)
    }

    let mode: Mode
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isManagedByParent: Bool
    @State private var thisIsMe = false
    @State private var age: String
    @State private var heightCm: String
    @State private var weightKg: String
    @State private var sex: Sex?

    @State private var hasDiabetes: Bool
    @State private var hasHypertension: Bool
    @State private var hasHighCholesterol: Bool
    @State private var isPregnant: Bool
    @State private var customConditions: [String]
    @State private var newCustomCondition = ""

    @State private var allergies: Set<Allergen>
    @State private var customAllergies: [String]
    @State private var newCustomAllergy = ""

    @State private var calories: String
    @State private var sugar: String
    @State private var sodium: String
    @State private var satFat: String
    @State private var isSaving = false

    init(mode: Mode) {
        self.mode = mode
        let existing: Member? = if case .edit(let m) = mode { m } else { nil }
        _name = State(initialValue: existing?.name ?? "")
        _isManagedByParent = State(initialValue: existing?.isManagedByParent ?? false)
        _age = State(initialValue: existing?.age.map(String.init) ?? "")
        _heightCm = State(initialValue: existing?.heightCm.map { String(Int($0)) } ?? "")
        _weightKg = State(initialValue: existing?.weightKg.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String(format: "%.1f", $0) } ?? "")
        _sex = State(initialValue: existing?.sex)

        _hasDiabetes = State(initialValue: existing?.has(.diabetes) ?? false)
        _hasHypertension = State(initialValue: existing?.has(.hypertension) ?? false)
        _hasHighCholesterol = State(initialValue: existing?.has(.highCholesterol) ?? false)
        _isPregnant = State(initialValue: existing?.isPregnant ?? false)
        _customConditions = State(initialValue: existing?.customConditionNames ?? [])

        _allergies = State(initialValue: Set(existing?.allergies ?? []))
        _customAllergies = State(initialValue: existing?.customAllergyNames ?? [])

        _calories = State(initialValue: existing?.goals.dailyCalories.map { String(Int($0)) } ?? "")
        _sugar = State(initialValue: existing?.goals.dailySugarGrams.map { String(Int($0)) } ?? "")
        _sodium = State(initialValue: existing?.goals.dailySodiumMg.map { String(Int($0)) } ?? "")
        _satFat = State(initialValue: existing?.goals.dailySatFatGrams.map { String(Int($0)) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $name)
                    Toggle("Managed by a parent", isOn: $isManagedByParent)
                    if !isEditing && family.myMember == nil {
                        Toggle("This is me", isOn: $thisIsMe)
                            .onChange(of: thisIsMe) { _, on in if on { isManagedByParent = false } }
                    }
                }

                Section {
                    Picker("Sex", selection: $sex) {
                        Text("Not set").tag(Sex?.none)
                        ForEach(Sex.allCases) { s in
                            Text(s.displayName).tag(Sex?.some(s))
                        }
                    }
                    numericField("Age", suffix: "years", text: $age)
                    numericField("Height", suffix: "cm", text: $heightCm)
                    numericField("Weight", suffix: "kg", text: $weightKg, allowsDecimal: true)
                } header: {
                    Text("Vitals")
                } footer: {
                    Text("Sex is used only to pick a more accurate default daily target (calories, added sugar) when no goal is set below — it's optional.")
                }

                Section("Conditions") {
                    Toggle("Diabetes", isOn: $hasDiabetes)
                    Toggle("High blood pressure", isOn: $hasHypertension)
                    Toggle("High cholesterol", isOn: $hasHighCholesterol)
                    if sex != .male {
                        Toggle("Pregnant", isOn: $isPregnant)
                        if isPregnant {
                            Text("NutriKin will flag foods commonly advised against in pregnancy, such as alcohol, raw fish or eggs, unpasteurised dairy and liver, and won't suggest weight plans. It's general guidance, not medical advice: ask your midwife or doctor.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    ForEach(customConditions, id: \.self) { condition in
                        Text(condition)
                    }
                    .onDelete { customConditions.remove(atOffsets: $0) }

                    HStack {
                        TextField("Add a condition (e.g. Celiac disease)", text: $newCustomCondition)
                        Button("Add") { addCustomCondition() }
                            .disabled(newCustomCondition.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section {
                    ForEach(Allergen.allCases) { allergen in
                        Toggle(allergen.displayName, isOn: Binding(
                            get: { allergies.contains(allergen) },
                            set: { isOn in
                                if isOn { allergies.insert(allergen) } else { allergies.remove(allergen) }
                            }
                        ))
                    }

                    ForEach(customAllergies, id: \.self) { allergy in
                        Text(allergy)
                    }
                    .onDelete { customAllergies.remove(atOffsets: $0) }

                    HStack {
                        TextField("Add an allergy (e.g. kiwi)", text: $newCustomAllergy)
                        Button("Add") { addCustomAllergy() }
                            .disabled(newCustomAllergy.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Allergies")
                } footer: {
                    Text("A custom allergy is matched against the product's ingredient text, not the stricter allergen-tag lookup the built-in list uses.")
                }

                Section {
                    numericField("Calories", suffix: "kcal/day", text: $calories)
                    numericField("Sugar", suffix: "g/day", text: $sugar)
                    numericField("Sodium", suffix: "mg/day", text: $sodium)
                    numericField("Saturated fat", suffix: "g/day", text: $satFat)
                } header: {
                    Text("Daily goals")
                } footer: {
                    Text("Leave blank if this doesn't apply.")
                }

                if case .edit(let existing) = mode {
                    Section {
                        Button("Remove from family", role: .destructive) {
                            Task {
                                await family.deleteMember(existing)
                                dismiss()
                            }
                        }
                    }
                }

                if let errorMessage = family.errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit member" : "Add member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    private func numericField(_ title: String, suffix: String, text: Binding<String>, allowsDecimal: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: text)
                .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text(suffix).foregroundStyle(.secondary).font(.footnote)
        }
    }

    private func addCustomCondition() {
        let trimmed = newCustomCondition.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !customConditions.contains(trimmed) else { return }
        customConditions.append(trimmed)
        newCustomCondition = ""
    }

    private func addCustomAllergy() {
        let trimmed = newCustomAllergy.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !customAllergies.contains(trimmed) else { return }
        customAllergies.append(trimmed)
        newCustomAllergy = ""
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        var conditions: [Condition] = []
        if hasDiabetes { conditions.append(.diabetes) }
        if hasHypertension { conditions.append(.hypertension) }
        if hasHighCholesterol { conditions.append(.highCholesterol) }
        if isPregnant && sex != .male { conditions.append(.pregnancy) }
        conditions.append(contentsOf: allergies.map(Condition.allergy))
        conditions.append(contentsOf: customAllergies.map(Condition.customAllergy))
        conditions.append(contentsOf: customConditions.map(Condition.custom))

        let goals = Goals(
            dailyCalories: Double(calories),
            dailySugarGrams: Double(sugar),
            dailySodiumMg: Double(sodium),
            dailySatFatGrams: Double(satFat)
        )

        let ageValue = Int(age)
        let heightValue = Double(heightCm)
        let weightValue = Double(weightKg)

        switch mode {
        case .add:
            let added = await family.addMember(
                name: name.trimmingCharacters(in: .whitespaces),
                conditions: conditions,
                goals: goals,
                isManagedByParent: isManagedByParent,
                age: ageValue,
                heightCm: heightValue,
                weightKg: weightValue,
                sex: sex
            )
            if thisIsMe, let added { await family.claimMember(added) }
        case .edit(var existing):
            existing.name = name.trimmingCharacters(in: .whitespaces)
            existing.conditions = conditions
            existing.goals = goals
            existing.isManagedByParent = isManagedByParent
            existing.age = ageValue
            existing.heightCm = heightValue
            existing.weightKg = weightValue
            existing.sex = sex
            await family.updateMember(existing)
        }

        if family.errorMessage == nil { dismiss() }
    }
}
