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
            Section { header.staggeredAppear(0) }

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

            Section("Nutrition \(product.nutrition.basis)") { nutritionGrid.staggeredAppear(1) }

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
                    ForEach(Array(ingredientAlerts.enumerated()), id: \.element.id) { i, alert in
                        IngredientAlertRow(alert: alert).staggeredAppear(i + 2)
                    }
                } header: {
                    Text("Ingredient alerts")
                } footer: {
                    Text("Ingredients often flagged as worth limiting. Alerts inform you; they don't change the scores above.")
                }
            }

            Section("Who can eat this") {
                ForEach(Array(results.enumerated()), id: \.element.id) { i, s in
                    DisclosureGroup {
                        ForEach(s.reasons, id: \.self) { Text($0).font(.subheadline) }
                    } label: {
                        MemberScoreRow(score: s)
                    }
                    .staggeredAppear(i + 3)
                }
            }

            let ingredientRows = IngredientRows.make(product: product, alerts: ingredientAlerts, members: family.members)
            if !ingredientRows.isEmpty {
                Section("Ingredients") { IngredientListView(rows: ingredientRows) }
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
        .onAppear {
            // The scanner already gave a success tap; only add one when there's something to heed.
            if allergyHits.isEmpty == false {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } else if results.contains(where: { $0.verdict == .avoid }) {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
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
    /// Counts up from 0 when the row appears.
    @State private var shownScore = 0
    @State private var popped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                Text("\(shownScore)")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText(value: Double(shownScore)))
                Text(score.verdict.label).font(.caption.weight(.semibold))
            }
            .frame(minWidth: 60)
            .padding(.vertical, 6)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(color)
            .scaleEffect(popped ? 1 : 0.7)
            .opacity(popped ? 1 : 0)
        }
        .onAppear {
            guard !popped else { return }
            if reduceMotion { shownScore = score.score; popped = true; return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.15)) { popped = true }
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) { shownScore = score.score }
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
