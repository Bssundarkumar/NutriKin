import SwiftUI

/// A member's healthy weight range and suggested daily intake, from their BMI.
struct NutritionPlanView: View {
    let member: Member
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @AppStorage private var activityRaw: String
    @State private var applied = false

    init(member: Member) {
        self.member = member
        _activityRaw = AppStorage(wrappedValue: ActivityLevel.light.rawValue, "activity-\(member.id.uuidString)")
    }

    private var activity: ActivityLevel { ActivityLevel(rawValue: activityRaw) ?? .light }

    var body: some View {
        NavigationStack {
            Group {
                switch NutritionPlanner.plan(for: member, activity: activity) {
                case .needsInfo(let missing): message(
                    "Add \(missing.joined(separator: ", ")) to see a plan",
                    "Open this person from the Family tab and fill in their age, height and weight. It stays private to your family.",
                    symbol: "ruler")
                case .notForChildren: message(
                    "Plans are for adults",
                    "Children need growth charts, not adult BMI rules. Ask a pediatrician for a target, and use each scan's alerts in the meantime.",
                    symbol: "figure.and.child.holdinghands")
                case .plan(let plan): planList(plan)
                }
            }
            .background(AppBackground())
            .navigationTitle("\(member.name)'s plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func message(_ title: String, _ text: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 48)).foregroundStyle(Theme.brandGradient)
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private func planList(_ plan: NutritionPlan) -> some View {
        List {
            Section { bmiCard(plan) }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)

            Section {
                Picker("Activity", selection: $activityRaw) {
                    ForEach(ActivityLevel.allCases) { Text($0.shortTitle).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Text(activity.title).font(.footnote).foregroundStyle(.secondary)
            } header: { Text("How active are they?") }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(plan.dailyKcal)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: Double(plan.dailyKcal)))
                    Text("kcal a day").foregroundStyle(.secondary)
                    Spacer()
                }
                Text(paceText(plan)).font(.footnote).foregroundStyle(.secondary)
                HStack {
                    macro("Protein", "\(plan.proteinG) g"); macro("Carbs", "\(plan.carbsG) g")
                    macro("Fat", "\(plan.fatG) g"); macro("Fibre", "\(plan.fiberG) g")
                }
                Button {
                    var updated = member
                    updated.goals.dailyCalories = Double(plan.dailyKcal)
                    Task { await family.updateMember(updated); applied = true }
                } label: {
                    Label(applied ? "Saved as \(member.name)'s calorie goal" : "Use as daily calorie goal",
                          systemImage: applied ? "checkmark.circle.fill" : "target")
                }
                .disabled(applied)
            } header: { Text("Suggested daily intake") } footer: {
                Text("Scans compare foods with this goal once you save it.")
            }

            Section("A day, split up") {
                ForEach(plan.meals, id: \.name) { meal in
                    LabeledContent(meal.name, value: "\(meal.kcal) kcal")
                }
            }

            Section {
                LabeledContent("Added sugar", value: "under \(plan.sugarLimitG) g")
                LabeledContent("Saturated fat", value: "under \(plan.satFatLimitG) g")
                LabeledContent("Sodium", value: "under \(plan.sodiumLimitMg) mg")
            } header: { Text("Daily limits") }

            Section {
                ForEach(foodIdeas(plan), id: \.self) { Label($0, systemImage: "leaf.fill").font(.subheadline) }
            } header: { Text("What to fill the plate with") }

            Section {
                ForEach(plan.notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                Text("Guidance only, not medical advice. Reviewing it with a doctor or dietitian is wise.")
                    .font(.footnote.weight(.semibold))
            }
        }
        .softList()
        .animation(.snappy, value: activityRaw)
    }

    private func macro(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func paceText(_ plan: NutritionPlan) -> String {
        switch plan.direction {
        case .maintain: return "Keeps weight steady at about \(kg(plan.currentKg))."
        case .lose, .gain:
            let pace = String(format: "%.2f", abs(plan.weeklyChangeKg))
            let verb = plan.direction == .lose ? "Lose" : "Gain"
            let when = plan.weeksToTarget.map { " Roughly \($0) weeks to reach \(kg(plan.targetKg))." } ?? ""
            return "\(verb) about \(pace) kg a week.\(when) Maintenance would be \(plan.maintenanceKcal) kcal."
        }
    }

    private func foodIdeas(_ plan: NutritionPlan) -> [String] {
        var ideas = [
            "Half the plate vegetables and fruit, a quarter lean protein (dal, eggs, fish, chicken, tofu), a quarter whole grains.",
            "Cook with small amounts of unsaturated oil; choose nuts, seeds and legumes for snacks.",
            "Swap sugary drinks and sweets for water, tea or fruit.",
        ]
        switch plan.direction {
        case .lose: ideas.append("Fill up on fibre and protein: they keep you full on fewer calories.")
        case .gain: ideas.append("Add healthy energy: nuts, nut butters, olive oil, whole milk or yoghurt, and an extra snack.")
        case .maintain: break
        }
        return ideas
    }

    private func kg(_ v: Double) -> String { String(format: "%.1f kg", v) }

    private func bmiCard(_ plan: NutritionPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "BMI %.1f", plan.bmi)).font(.title2.bold())
                    Text(plan.category.label).font(.subheadline.weight(.semibold)).foregroundStyle(color(plan.category))
                }
                Spacer()
                Avatar(name: member.name, size: 44)
            }
            BMIBar(bmi: plan.bmi)
            HStack {
                weightBlock("Now", kg(plan.currentKg))
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                weightBlock("Target", kg(plan.targetKg))
                Spacer()
                weightBlock("Healthy range", "\(Int(plan.healthyRangeKg.lowerBound.rounded()))\u{2013}\(Int(plan.healthyRangeKg.upperBound.rounded())) kg")
            }
        }
        .card()
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    private func weightBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
    }

    private func color(_ c: BMICategory) -> Color {
        switch c {
        case .healthy: .green
        case .underweight: .blue
        case .overweight: .orange
        case .obese: .red
        }
    }
}

/// A scale from 15 to 40 with the healthy band highlighted and a marker that slides to the BMI.
private struct BMIBar: View {
    let bmi: Double
    @State private var shown = 15.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let lo = 15.0, hi = 40.0
    private func x(_ v: Double, _ width: CGFloat) -> CGFloat { CGFloat((min(max(v, lo), hi) - lo) / (hi - lo)) * width }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(Color.green.opacity(0.35))
                    .frame(width: x(24.9, w) - x(18.5, w)).offset(x: x(18.5, w))
                Circle().fill(.white).frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Theme.brand, lineWidth: 4))
                    .shadow(radius: 3)
                    .offset(x: x(shown, w) - 10)
            }
            .frame(height: 20)
        }
        .frame(height: 20)
        .onAppear {
            if reduceMotion { shown = bmi } else { withAnimation(.spring(response: 0.9, dampingFraction: 0.7).delay(0.2)) { shown = bmi } }
        }
        .accessibilityLabel("BMI \(String(format: "%.1f", bmi)) on a scale from 15 to 40")
    }
}
