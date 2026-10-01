import SwiftUI

/// A short multi-step setup for the person creating a family, run right after the household is made.
/// Collects just enough (name, vitals, a weight goal) to link them as a member and show a real
/// nutrition plan immediately, instead of landing on an empty "add a member" form. Adding other family
/// members, or editing any of this later, still goes through MemberEditView as before.
struct GoalOnboardingView: View {
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    private let totalSteps = 3

    @State private var name = ""
    @State private var sex: Sex?
    @State private var heightCm = ""
    @State private var weightKg = ""
    @State private var birthdate = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    @State private var targetWeightKg = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                header
                Group {
                    switch step {
                    case 1: nameStep
                    case 2: vitalsStep
                    default: goalStep
                    }
                }
                .padding(.horizontal, 24)
                }
                footer
            }
            .background(AppBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { Task { await finish(skipped: true) } }
                        .readableFont(16, weight: .regular, relativeTo: .footnote)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(1...totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Theme.brand : Color.secondary.opacity(0.2))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            Text("\(step)/\(totalSteps)")
                .readableFont(15, weight: .regular, relativeTo: .caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 12)
    }

    private var nameStep: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 12)
            Text("Welcome! What should we call you?")
                .readableFont(24, weight: .bold, relativeTo: .title2)
                .multilineTextAlignment(.center)
            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
            Picker("Sex", selection: $sex) {
                Text("Prefer not to say").tag(Sex?.none)
                ForEach(Sex.allCases) { Text($0.displayName).tag(Sex?.some($0)) }
            }
            .pickerStyle(.segmented)
            Text("Used only to pick a more accurate default calorie goal — optional.")
                .readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary)
        }
    }

    private var vitalsStep: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 12)
            Text("A few vitals")
                .readableFont(24, weight: .bold, relativeTo: .title2)
            DatePicker("Birthdate", selection: $birthdate, in: ...Date.now, displayedComponents: .date)
            numericField("Height", suffix: "cm", text: $heightCm)
            numericField("Current weight", suffix: "kg", text: $weightKg, allowsDecimal: true)
            Text("Used to work out a daily calorie goal, BMI and a healthy weight range. Stays private to your family.")
                .readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary)
        }
    }

    private var goalStep: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 12)
            Text("Weight goal")
                .readableFont(24, weight: .bold, relativeTo: .title2)
            Text("What is your target weight?")
                .readableFont(17, weight: .regular, relativeTo: .subheadline).foregroundStyle(.secondary)
            numericField("Target weight", suffix: "kg", text: $targetWeightKg, allowsDecimal: true)
            Text("Optional — leave blank and NutriKin will suggest a healthy target from your BMI instead.")
                .readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let error = family.errorMessage {
                Text(error).readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Button(step < totalSteps ? "Continue" : "Done") {
                if step < totalSteps { step += 1 } else { Task { await finish(skipped: false) } }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(step == 1 && name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            if step > 1 {
                Button("Back") { step -= 1 }.readableFont(16, weight: .regular, relativeTo: .footnote)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .animation(.smooth(duration: 0.2), value: step)
    }

    private func numericField(_ title: String, suffix: String, text: Binding<String>, allowsDecimal: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: text)
                .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text(suffix).foregroundStyle(.secondary).readableFont(16, weight: .regular, relativeTo: .footnote)
        }
    }

    private func finish(skipped: Bool) async {
        isSaving = true
        defer { isSaving = false }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { dismiss(); return }

        let goals = skipped ? Goals() : Goals(targetWeightKg: Double(targetWeightKg))
        let added = await family.addMember(
            name: trimmedName,
            conditions: [],
            goals: goals,
            isManagedByParent: false,
            age: skipped ? nil : age,
            heightCm: skipped ? nil : Double(heightCm),
            weightKg: skipped ? nil : Double(weightKg),
            sex: skipped ? nil : sex
        )
        if let added { await family.claimMember(added) }
        if family.errorMessage == nil { dismiss() }
    }

    private var age: Int? {
        Calendar.current.dateComponents([.year], from: birthdate, to: .now).year
    }
}

#Preview {
    GoalOnboardingView()
        .environment(FamilyStore())
}
