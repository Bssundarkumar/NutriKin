import SwiftUI

struct ResultView: View {
    let product: Product
    @Environment(FamilyStore.self) private var family
    @Environment(HistoryStore.self) private var history
    private let engine = ScoringEngine()
    private let analyzer = IngredientAnalyzer()

    private var scores: [MemberScore] {
        engine.scoreFamily(product, members: family.members)
    }

    var body: some View {
        let results = scores
        let allergyHits = results.filter(\.blockedByAllergy)
        let ingredientAlerts = analyzer.alerts(for: product, members: family.members)

        List {
            Section { header }

            if let failed = history.failedSave, failed.barcode == product.barcode {
                Section {
                    Label("Not saved to History", systemImage: "exclamationmark.icloud.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(failed.message).font(.footnote).foregroundStyle(.secondary)
                    Button(history.isRetrying ? "Trying\u{2026}" : "Try again") {
                        Task { await history.retryFailedSave() }
                    }
                    .disabled(history.isRetrying)
                }
            }

            Section("Nutrition \(product.nutrition.basis)") { nutritionGrid }

            if !allergyHits.isEmpty {
                Section {
                    Label("Allergy alert for \(allergyHits.map(\.member.name).joined(separator: ", "))",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fontWeight(.semibold)
                }
            }

            if !ingredientAlerts.isEmpty {
                Section {
                    ForEach(ingredientAlerts) { IngredientAlertRow(alert: $0) }
                } header: {
                    Text("Ingredient alerts")
                } footer: {
                    Text("Ingredients often flagged as worth limiting. Alerts inform you; they don't change the scores above.")
                }
            }

            Section("Who can eat this") {
                ForEach(results) { s in
                    DisclosureGroup {
                        ForEach(s.reasons, id: \.self) { Text($0).font(.subheadline) }
                    } label: {
                        MemberScoreRow(score: s)
                    }
                }
            }

            let ingredientItems = ingredientItems(alerts: ingredientAlerts)
            if !ingredientItems.isEmpty {
                Section("Ingredients") { IngredientListView(items: ingredientItems) }
            } else if let raw = product.ingredientsText, !raw.isEmpty {
                Section("Ingredients") { Text(raw).font(.footnote) }
            }

            Section {
                Text("Guidance only, not medical advice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Scan result")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The label's ingredients as chips, each marked if it's worth limiting or
    /// is an allergen for someone in the family.
    private func ingredientItems(alerts: [IngredientAlert]) -> [IngredientListView.Item] {
        guard let raw = product.ingredientsText else { return [] }
        let familyAllergens = Set(family.members.flatMap(\.allergies))
        let customAllergies = family.members.flatMap(\.customAllergyNames)

        return IngredientParser.items(from: raw).enumerated().map { index, text in
            let lower = text.lowercased()
            let isAllergen = familyAllergens.contains { $0.keywords.contains { lower.contains($0) } }
                || customAllergies.contains { lower.contains($0.lowercased()) }
            if isAllergen { return .init(id: index, text: text, kind: .allergen) }
            if analyzer.flag(for: text, among: alerts) != nil { return .init(id: index, text: text, kind: .limit) }
            return .init(id: index, text: text, kind: .plain)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AsyncImage(url: product.imageURL) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(product.name).font(.title3.weight(.semibold))
                if let brand = product.brand {
                    Text(brand).font(.subheadline).foregroundStyle(.secondary)
                }
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
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.0).font(.caption).foregroundStyle(.secondary)
                    Text(item.1).font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct MemberScoreRow: View {
    let score: MemberScore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(score.member.name).font(.headline)
                Text(conditionsText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 0) {
                Text("\(score.score)").font(.headline)
                Text(score.verdict.label).font(.caption.weight(.semibold))
            }
            .frame(minWidth: 60)
            .padding(.vertical, 6)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(color)
        }
    }

    private var conditionsText: String {
        let text = score.member.conditions.map(\.displayName).joined(separator: " · ")
        return text.isEmpty ? "No conditions" : text
    }

    private var color: Color {
        switch score.verdict {
        case .okay: .green
        case .caution: .orange
        case .avoid: .red
        }
    }
}


struct IngredientAlertRow: View {
    let alert: IngredientAlert

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(alert.flag.title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(alert.flag.reason)
                .font(.footnote)
            Text(alert.members.isEmpty ? "Relevant to everyone" : "Matters most for \(alert.members.joined(separator: ", "))")
                .font(.caption)
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
