import SwiftUI

struct ResultView: View {
    let product: Product
    @Environment(FamilyStore.self) private var family
    private let engine = ScoringEngine()

    private var scores: [MemberScore] {
        engine.scoreFamily(product, members: family.members)
    }

    var body: some View {
        let results = scores
        let allergyHits = results.filter(\.blockedByAllergy)

        List {
            Section { header }

            Section("Nutrition \(product.nutrition.basis)") { nutritionGrid }

            if !allergyHits.isEmpty {
                Section {
                    Label("Allergy alert for \(allergyHits.map(\.member.name).joined(separator: ", "))",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fontWeight(.semibold)
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

            if let ingredients = product.ingredientsText, !ingredients.isEmpty {
                Section("Ingredients") { Text(ingredients).font(.footnote) }
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
