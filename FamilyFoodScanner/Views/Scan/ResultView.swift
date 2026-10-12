import SwiftUI

struct ResultView: View {
    /// A `@State` copy (not `let`) so an AI nutrition estimate can be applied in place once the person
    /// asks for one - see `estimateNutrition()`.
    @State private var product: Product
    @ScaledMetric(relativeTo: .body) private var nutritionTileWidth = 96.0
    @Environment(FamilyStore.self) private var family
    @Environment(HistoryStore.self) private var history
    @Environment(AIConnection.self) private var ai
    @Environment(GroceryStore.self) private var groceries
    private let engine = ScoringEngine()
    private let analyzer = IngredientAnalyzer()
    @State private var alternatives: AlternativesSection.Phase = .unavailable
    @State private var showGradesInfo = false
    @State private var ideas: AlternativesSection.IdeasPhase = .idle
    @State private var showAsk = Demo.opensAsk
    @State private var showLog = Demo.opensLogProduct
    @State private var groceryNote: String?
    @State private var isEstimatingNutrition = false
    @State private var estimateError: String?
    @State private var confirmingEstimate = false

    init(product: Product) {
        _product = State(initialValue: product)
    }

    private var scores: [MemberScore] {
        engine.scoreFamily(product, members: family.members)
    }

    var body: some View {
        let results = scores
        let allergyHits = results.filter(\.blockedByAllergy)
        let ingredientAlerts = analyzer.alerts(for: product, members: family.members)
        let isAlcoholic = AlcoholGuidance.isAlcoholic(product)

        List {
            Section { ResultHero(product: product, results: results) }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

            if !product.dataWarnings.isEmpty {
                Section {
                    Label("Some information is missing", systemImage: "questionmark.diamond.fill")
                        .readableFont(17, weight: .semibold, relativeTo: .subheadline)
                        .foregroundStyle(.orange)
                    ForEach(product.dataWarnings, id: \.self) { Text($0).readableFont(16, weight: .regular, relativeTo: .footnote) }
                    Text("Scores can't be fully trusted without it. Check the package, or go back and photograph the label.")
                        .readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary)
                    if !product.hasAnyNutrition && !product.nutritionIsAIEstimate && AppleAI.status.isAvailable {
                        Button {
                            confirmingEstimate = true
                        } label: {
                            if isEstimatingNutrition {
                                HStack(spacing: 6) { ProgressView(); Text("Estimating\u{2026}") }
                            } else {
                                Label("Estimate nutrition with AI", systemImage: "sparkles")
                            }
                        }
                        .disabled(isEstimatingNutrition)
                        if let estimateError { Text(estimateError).readableFont(14).foregroundStyle(.secondary) }
                    }
                }
                .listRowBackground(Color.orange.opacity(0.12))
            }

            if product.barcode.hasPrefix("photo-") {
                Section {
                    Label("Read from a photo", systemImage: "camera.viewfinder")
                        .readableFont(17, weight: .semibold, relativeTo: .subheadline)
                    Text("This uses the text you confirmed, not a database. Compare it with the package, especially for allergies.")
                        .readableFont(16, weight: .regular, relativeTo: .footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let failed = history.failedSave, failed.barcode == product.barcode {
                Section {
                    Label("Not saved to History", systemImage: "exclamationmark.icloud.fill")
                        .readableFont(17, weight: .semibold, relativeTo: .subheadline)
                        .foregroundStyle(.orange)
                    Text(failed.message).readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary)
                    Button(history.isRetrying ? "Trying\u{2026}" : "Try again") {
                        Task { await history.retryFailedSave() }
                    }
                    .disabled(history.isRetrying)
                }
            }

            if product.isSupplement {
                Section {
                    Label("Dietary supplement", systemImage: "pills.fill")
                        .readableFont(17, weight: .semibold, relativeTo: .subheadline)
                    Text("Nutri-Score and NOVA grades are designed for everyday foods, so they're not shown for supplements. Follow the dose on the label and ask a doctor or pharmacist if you're unsure.")
                        .readableFont(16, weight: .regular, relativeTo: .footnote)
                        .foregroundStyle(.secondary)
                }
            } else if product.nutriScore != nil || product.novaGroup != nil {
                Section {
                    QualityBadges(nutriScore: product.nutriScore, novaGroup: product.novaGroup)
                        .padding(.vertical, 4)
                } header: {
                    HStack {
                        Text("Quality grades")
                        Spacer()
                        Button { showGradesInfo = true } label: {
                            Label("What do these mean?", systemImage: "info.circle")
                                .readableFont(15, weight: .semibold, relativeTo: .caption)
                                .textCase(nil)
                        }
                    }
                } footer: {
                    Text("General grades from Open Food Facts, not personalised. The family scores below take each person's needs into account.")
                }
            }

            Section {
                nutritionGrid.staggeredAppear(1)
            } header: {
                if product.nutritionIsAIEstimate {
                    Label("Nutrition \(product.nutrition.basis) \u{2014} AI estimate, not from the package", systemImage: "sparkles")
                        .foregroundStyle(.orange)
                        .textCase(nil)
                } else {
                    Text("Nutrition \(product.nutrition.basis)")
                }
            }

            if !allergyHits.isEmpty {
                Section {
                    Label {
                        Text("Allergy alert for \(allergyHits.map(\.member.name).joined(separator: ", "))")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .symbolEffect(.pulse, options: .repeat(4))
                    }
                    .foregroundStyle(.red)
                    .fontWeight(.semibold)
                }
                .listRowBackground(Color.red.opacity(0.12))
            }

            if isAlcoholic {
                Section {
                    Label {
                        Text("Contains alcohol")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .symbolEffect(.pulse, options: .repeat(4))
                    }
                    .foregroundStyle(.red)
                    .fontWeight(.semibold)
                    Text("Never appropriate for children, regardless of its nutrition. Capped for everyone else too.")
                        .readableFont(16, weight: .regular, relativeTo: .footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.red.opacity(0.12))
            }

            if !ingredientAlerts.isEmpty {
                Section {
                    ForEach(Array(ingredientAlerts.enumerated()), id: \.element.id) { i, alert in
                        IngredientAlertRow(alert: alert).staggeredAppear(i + 2)
                    }
                } header: {
                    Text("Ingredient alerts")
                } footer: {
                    Text("Ingredients often flagged as worth limiting. Alerts inform you; they don't change the scores above.")
                }
            }

            Section {
                Button { showLog = true } label: { Label("Log as eaten", systemImage: "plus.circle.fill") }
                Button { addToGroceries() } label: { Label(groceryNote ?? "Add to grocery list", systemImage: groceryNote == nil ? "cart.badge.plus" : "checkmark.circle.fill") }
                    .disabled(groceryNote != nil)
            } footer: {
                Text("Log it in Today's tracker, or put it on the family's shopping list.")
            }

            Section("Who can eat this") {
                ForEach(Array(results.enumerated()), id: \.element.id) { i, s in
                    DisclosureGroup {
                        ForEach(s.reasons, id: \.self) { Text($0).readableFont(17, weight: .regular, relativeTo: .subheadline) }
                    } label: {
                        MemberScoreRow(score: s)
                    }
                    .staggeredAppear(i + 3)
                }
            }

            AlternativesSection(phase: alternatives, ideas: ideas, canAskAI: ai.textProvider != nil && !product.isSupplement,
                                onRetry: { askForIdeas() })

            Section {
                Button { showAsk = true } label: {
                    Label("Ask AI about this product", systemImage: "sparkles")
                        .readableFont(17, weight: .semibold, relativeTo: .subheadline)
                }
            } footer: {
                Text(ai.textProvider == .apple ? "AI requests run on this iPhone." : "When you ask, this product and relevant family details are sent to your selected AI provider.")
            }

            let ingredientRows = IngredientRows.make(product: product, alerts: ingredientAlerts, members: family.members)
            if !ingredientRows.isEmpty {
                Section("Ingredients") { IngredientListView(rows: ingredientRows) }
            } else if let raw = product.ingredientsText, !raw.isEmpty {
                Section("Ingredients") { Text(raw).readableFont(16, weight: .regular, relativeTo: .footnote) }
            }

            Section {
                Text("Guidance only, not medical advice.")
                    .readableFont(16, weight: .regular, relativeTo: .footnote)
                    .foregroundStyle(.secondary)
                Text("Product data from [Open Food Facts](https://world.openfoodfacts.org/product/\(product.barcode)) (ODbL). Photos CC BY-SA.")
                    .readableFont(15, weight: .regular, relativeTo: .caption)
                    .foregroundStyle(.secondary)
            }
        }
        .softList()
        .sheet(isPresented: $showGradesInfo) { GradesInfoSheet() }
        .sheet(isPresented: $showAsk) { AskAIView(product: product) }
        .sheet(isPresented: $showLog) { LogProductSheet(product: product) }
        .navigationTitle("Scan result")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "This is a general AI guess, not real data from this package",
            isPresented: $confirmingEstimate, titleVisibility: .visible
        ) {
            Button("Estimate anyway") { Task { await estimateNutrition() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apple's on-device AI will guess typical nutrition for \"\(product.name)\" from its name alone. It can be wrong - always check the real package, especially for a condition like diabetes.")
        }
        .task(id: product.barcode) { await loadAlternatives(for: results) }
        .onAppear {
            // The scanner already gave a success tap; only add one when there's something to heed.
            if allergyHits.isEmpty == false {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } else if results.contains(where: { $0.verdict == .avoid }) {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
    }

    /// Finds public-database category alternatives. AI ideas are requested separately by the person.
    private func loadAlternatives(for results: [MemberScore]) async {
        let couldBeBetter = results.contains(where: { $0.verdict != .okay })
            || ["c", "d", "e"].contains(product.nutriScore ?? "") || product.novaGroup == 4
        guard !product.barcode.hasPrefix("photo-"), !product.isSupplement, product.normalizedTo100g != nil,
              couldBeBetter, !family.members.isEmpty else {
            alternatives = .unavailable
            ideas = .idle
            return
        }
        ideas = .idle
        if product.categoryTags.isEmpty {
            alternatives = .unavailable
        } else {
            alternatives = .loading
            do {
                let candidates = try await ProductService().similarProducts(to: product)
                let ranked = AlternativeRanker().rank(current: product, candidates: candidates, members: family.members)
                alternatives = .loaded(ranked)
            } catch {
                alternatives = .unavailable
            }
        }
        // AI suggestions require an explicit action, including paid/cloud providers.
    }

    /// Fills in a nutrition-only estimate from Apple's on-device AI when the database has none. Never
    /// touches ingredients/allergens, so the allergy warnings and safety blocks above are unaffected.
    private func estimateNutrition() async {
        estimateError = nil
        isEstimatingNutrition = true
        defer { isEstimatingNutrition = false }
        do {
            let result = try await NutritionEstimator.estimate(name: product.name, brand: product.brand)
            product = NutritionEstimator.apply(result, to: product)
        } catch {
            estimateError = error.localizedDescription
        }
    }

    private func addToGroceries() {
        let label = ((product.brand.map { "\($0) " } ?? "") + product.name)
        Task {
            switch await groceries.add(name: label, barcode: product.barcode.hasPrefix("photo-") ? nil : product.barcode) {
            case .added: groceryNote = "Added to the grocery list"
            case .duplicate: groceryNote = "Already on the grocery list"
            case .failed: groceryNote = nil
            }
        }
    }

    /// Asks the person's AI for kinds of better products, then finds and scores real ones.
    private func askForIdeas() {
        guard let provider = ai.textProvider else { return }
        ideas = .loading
        let llm = provider == .apple ? ai.keyClient : ai.client(for: provider)
        let members = family.members
        Task {
            do {
                let suggestions = try await AlternativeIdeasService.ideas(for: product, members: members, provider: provider, client: llm)
                let found = await AlternativeIdeasService.resolve(ideas: suggestions, current: product, members: members)
                ideas = .loaded(found)
            } catch {
                ideas = .failed(error.localizedDescription)
            }
        }
    }

    private var nutritionGrid: some View {
        let n = product.nutrition
        let items: [(String, String)] = [
            ("Calories", n.calories.map { "\(Int($0))" } ?? "–"),
            ("Sugar", n.sugarG.map { String(format: "%.1f g", $0) } ?? "–"),
            ("Carbs", n.carbsG.map { String(format: "%.1f g", $0) } ?? "–"),
            ("Sodium", n.sodiumMg.map { "\(Int($0)) mg" } ?? "–"),
            ("Sat. fat", n.satFatG.map { String(format: "%.1f g", $0) } ?? "–"),
            ("Protein", n.proteinG.map { String(format: "%.1f g", $0) } ?? "–"),
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: nutritionTileWidth), spacing: 12)], spacing: 12) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.0).readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary)
                    Text(item.1).readableFont(19, weight: .semibold, relativeTo: .headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct MemberScoreRow: View {
    let score: MemberScore

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: score.member.name, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(score.member.name).readableFont(19, weight: .semibold, relativeTo: .headline)
                Text(conditionsText)
                    .readableFont(15, weight: .regular, relativeTo: .caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 2) {
                ScoreRing(score: score.score, color: color, size: 46, lineWidth: 5)
                Text(score.verdict.label).readableFont(15, weight: .semibold, relativeTo: .caption2).foregroundStyle(color)
            }
        }
    }

    private var conditionsText: String {
        let text = score.member.conditions.map(\.displayName).joined(separator: " \u{00B7} ")
        return text.isEmpty ? "No conditions" : text
    }

    private var color: Color { Theme.color(for: score.verdict) }
}


struct IngredientAlertRow: View {
    let alert: IngredientAlert

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(alert.flag.title, systemImage: icon)
                .readableFont(17, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(color)
            Text(alert.flag.reason)
                .readableFont(16, weight: .regular, relativeTo: .footnote)
            Text(alert.members.isEmpty ? "Relevant to everyone" : "Matters most for \(alert.members.joined(separator: ", "))")
                .readableFont(15, weight: .regular, relativeTo: .caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        alert.flag.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill"
    }

    private var color: Color {
        alert.flag.severity == .warning ? .orange : .blue
    }
}
