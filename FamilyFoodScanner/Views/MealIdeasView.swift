import SwiftUI

/// One day of meals sized to a person's calorie plan, written by their linked AI and
/// checked against their allergies by the app.
struct MealIdeasView: View {
    let member: Member
    let plan: NutritionPlan?
    @Environment(AIConnection.self) private var ai
    @Environment(\.dismiss) private var dismiss
    @AppStorage private var preferences: String
    @State private var phase: Phase = Demo.opensMeals ? .loaded(Demo.mealIdeas) : .idle
    @State private var showConnect = false

    private enum Phase { case idle, loading, loaded(MealIdeas), failed(String) }

    init(member: Member, plan: NutritionPlan?) {
        self.member = member
        self.plan = plan
        _preferences = AppStorage(wrappedValue: "", "mealprefs-\(member.id.uuidString)")
    }

    private var target: Int {
        plan?.dailyKcal ?? Int(member.goals.dailyCalories ?? ScoringEngine.defaultCalorieGoal(for: member.sex))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Preferences (optional): vegetarian, South Indian, no fish\u{2026}", text: $preferences, axis: .vertical)
                        .lineLimit(1...3)
                    Button {
                        generate()
                    } label: {
                        HStack {
                            Label(buttonTitle, systemImage: "sparkles")
                            if case .loading = phase { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isLoading)
                } header: {
                    Text("A day of meals for \(member.name)")
                } footer: {
                    Text("About \(target) kcal, matched to \(member.name)'s plan, conditions and allergies. "
                         + (ai.textProvider == .apple ? "Written on your iPhone; nothing is sent anywhere. " : "")
                         + "Ideas are suggestions to adapt.")
                }

                switch phase {
                case .idle, .loading: EmptyView()
                case .failed(let message):
                    Section { Text(message).font(.footnote).foregroundStyle(.red) }
                case .loaded(let ideas): results(ideas)
                }

                Section {
                    Text("AI suggestions can be wrong. Check every ingredient against allergies, and follow your doctor's or dietitian's advice. Guidance only, not medical advice.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .softList()
            .navigationTitle("Meal ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showConnect) { ConnectAIView { generate() } }
            .onAppear { ai.refreshApple() }
            .animation(.snappy, value: isLoading)
        }
    }

    private var isLoading: Bool { if case .loading = phase { true } else { false } }

    private var buttonTitle: String {
        if isLoading { return "Planning\u{2026}" }
        if case .loaded = phase { return "Plan another day" }
        return ai.textProvider != nil ? "Plan today's meals" : "Link an AI to plan meals"
    }

    @ViewBuilder
    private func results(_ ideas: MealIdeas) -> some View {
        Section {
            HStack {
                Text("\(ideas.totalKcal) kcal planned").font(.headline)
                Spacer()
                Text("goal \(target)").font(.subheadline).foregroundStyle(.secondary)
            }
            ProgressView(value: min(Double(ideas.totalKcal) / Double(max(target, 1)), 1.2), total: 1.2)
                .tint(abs(ideas.totalKcal - target) <= target / 8 ? .green : .orange)
        }
        if ideas.removedForAllergy > 0 {
            Section {
                Label("Removed \(ideas.removedForAllergy) idea\(ideas.removedForAllergy == 1 ? "" : "s") that may contain \(member.name)'s allergen.",
                      systemImage: "shield.lefthalf.filled")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
        ForEach(Array(ideas.slots.enumerated()), id: \.element.id) { i, slot in
            Section {
                ForEach(slot.dishes) { dish in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(dish.name).font(.headline)
                            Spacer()
                            Text("\(dish.kcal) kcal").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        if !dish.why.isEmpty { Text(dish.why).font(.footnote) }
                        if !dish.ingredients.isEmpty {
                            Text(dish.ingredients.joined(separator: " \u{00B7} ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("\(slot.name) \u{00B7} \(slot.kcal) kcal")
            }
            .staggeredAppear(i)
        }
        if !ideas.tips.isEmpty {
            Section("Tips") { ForEach(ideas.tips, id: \.self) { Label($0, systemImage: "lightbulb.fill").font(.subheadline) } }
        }
    }

    private func generate() {
        guard let provider = ai.textProvider else { showConnect = true; return }
        phase = .loading
        let key = ai.apiKey
        Task {
            do {
                let ideas = try await MealIdeasService.generate(member: member, plan: plan, preferences: preferences,
                                                                provider: provider, apiKey: key)
                phase = ideas.slots.isEmpty ? .failed("The AI didn't return usable meals. Try again.") : .loaded(ideas)
                if !ideas.slots.isEmpty { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
