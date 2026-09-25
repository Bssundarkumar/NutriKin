import SwiftUI

/// Nutri-Score (A to E) and NOVA (1 to 4) as reported by Open Food Facts.
/// These are general grades, not personalised: the family scores stay separate.
struct QualityBadges: View {
    let nutriScore: String?
    let novaGroup: Int?

    static let nutriColors: [String: Color] = [
        "a": Color(red: 0.01, green: 0.51, blue: 0.25), "b": Color(red: 0.52, green: 0.73, blue: 0.18),
        "c": Color(red: 0.95, green: 0.76, blue: 0.0), "d": Color(red: 0.93, green: 0.51, blue: 0.0),
        "e": Color(red: 0.90, green: 0.24, blue: 0.07),
    ]
    static let novaColors: [Int: Color] = [
        1: Color(red: 0.01, green: 0.51, blue: 0.25), 2: Color(red: 0.52, green: 0.73, blue: 0.18),
        3: Color(red: 0.93, green: 0.51, blue: 0.0), 4: Color(red: 0.90, green: 0.24, blue: 0.07),
    ]
    static func novaName(_ group: Int) -> String {
        switch group {
        case 1: "Unprocessed or minimally processed"
        case 2: "Processed culinary ingredient"
        case 3: "Processed food"
        default: "Ultra-processed food"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let grade = nutriScore, let color = Self.nutriColors[grade] {
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        ForEach(["a", "b", "c", "d", "e"], id: \.self) { letter in
                            Text(letter.uppercased())
                                .font(.system(size: letter == grade ? 20 : 12, weight: .bold))
                                .frame(width: letter == grade ? 34 : 24, height: letter == grade ? 34 : 24)
                                .background(Self.nutriColors[letter]!.opacity(letter == grade ? 1 : 0.35),
                                            in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.white)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Nutri-Score \(grade.uppercased())").font(.subheadline.weight(.semibold))
                        Text("Overall nutrition quality").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Nutri-Score \(grade.uppercased()) out of A to E")
                .tint(color)
            }
            if let group = novaGroup, let color = Self.novaColors[group] {
                HStack(spacing: 10) {
                    Text("\(group)")
                        .font(.headline)
                        .frame(width: 34, height: 34)
                        .background(color, in: Circle())
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("NOVA \(group)").font(.subheadline.weight(.semibold))
                        Text(Self.novaName(group)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// "Try this instead": better products for the whole family. Combines the AI's ideas (looked up and scored
/// by the app) with popular products from the same category.
struct AlternativesSection: View {
    enum Phase { case loading, loaded([Alternative]), unavailable }
    enum IdeasPhase { case idle, loading, loaded([Alternative]), failed(String) }

    let phase: Phase
    let ideas: IdeasPhase
    let canAskAI: Bool
    let onRetry: () -> Void

    private var categoryItems: [Alternative] { if case .loaded(let items) = phase { items } else { [] } }
    private var aiItems: [Alternative] { if case .loaded(let items) = ideas { items } else { [] } }
    private var isLoading: Bool {
        if case .loading = phase { return true }
        if case .loading = ideas { return true }
        return false
    }
    private var aiIsLoading: Bool { if case .loading = ideas { true } else { false } }
    private var applies: Bool {
        if case .unavailable = phase, case .idle = ideas { return false }
        return true
    }

    var body: some View {
        let merged = aiItems + categoryItems.filter { c in !aiItems.contains { $0.id == c.id } }
        if applies {
            Section {
                ForEach(merged.prefix(4)) { item in
                    NavigationLink { ResultView(product: item.product) } label: { AlternativeRow(item: item) }
                }
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(aiIsLoading ? "Asking your AI, then checking real products\u{2026}" : "Looking for better options\u{2026}")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if merged.isEmpty {
                    Label("No clearly better match found", systemImage: "magnifyingglass").font(.subheadline)
                    Text("Nothing that's safe for everyone in your family scored meaningfully better.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if canAskAI, case .failed = ideas {
                        Button(action: onRetry) { Label("Try the AI again", systemImage: "arrow.clockwise") }
                    }
                }
            } header: {
                Text("Try this instead")
            } footer: {
                if !merged.isEmpty {
                    Text("Real products scored for everyone in your family, compared per 100 g. Ideas marked in green come from your AI. Categories can occasionally be off, so check the label.")
                }
            }
        }
    }
}

private struct AlternativeRow: View {
    let item: Alternative

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.product.imageURL) { $0.resizable().scaledToFit() } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.product.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let brand = item.product.brand {
                    Text(brand).font(.caption).foregroundStyle(.secondary)
                }
                if let why = item.why, !why.isEmpty {
                    Text(why).font(.caption2).foregroundStyle(Theme.brand).lineLimit(2)
                }
            }
            Spacer()
            if let grade = item.product.nutriScore, let color = QualityBadges.nutriColors[grade] {
                Text(grade.uppercased())
                    .font(.footnote.weight(.bold))
                    .frame(width: 26, height: 26)
                    .background(color, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 0) {
                Text("\(item.worstScore)").font(.headline.monospacedDigit())
                Text("lowest").font(.caption2)
            }
            .foregroundStyle(.green)
        }
    }
}

/// Plain-language explanation of the two grades, opened from the "i" next to "Quality grades".
struct GradesInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let novaRows: [(Int, String, String)] = [
        (1, "Unprocessed or minimally processed", "Fruit, vegetables, eggs, plain milk, rice, fresh meat"),
        (2, "Processed culinary ingredients", "Oil, butter, sugar, salt, honey"),
        (3, "Processed foods", "Canned vegetables, cheese, fresh bread, salted nuts"),
        (4, "Ultra-processed foods", "Soft drinks, packaged snacks, instant noodles, most sweet spreads"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A to E, from best to worst. It looks at what's in 100 g: calories, sugar, saturated fat and salt count against a product; fibre, protein and fruit or vegetables count for it.")
                        .font(.subheadline)
                    HStack(spacing: 4) {
                        ForEach(["a", "b", "c", "d", "e"], id: \.self) { letter in
                            Text(letter.uppercased()).font(.footnote.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 30)
                                .background(QualityBadges.nutriColors[letter]!, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.white)
                        }
                    }
                } header: { Text("Nutri-Score") }

                Section {
                    Text("NOVA sorts food by how much it has been industrially processed, not by its nutrients. Group 4 usually means added flavours, sweeteners or emulsifiers you wouldn't use at home. Studies link eating a lot of these with weight gain and heart disease.")
                        .font(.subheadline)
                    ForEach(novaRows, id: \.0) { group, title, examples in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(group)").font(.headline)
                                .frame(width: 32, height: 32)
                                .background(QualityBadges.novaColors[group]!, in: Circle())
                                .foregroundStyle(.white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).font(.subheadline.weight(.semibold))
                                Text(examples).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("NOVA") }

                Section {
                    Text("Both grades come from Open Food Facts and are general: they don't know your family's health needs. That's what the family scores are for. They aren't shown for dietary supplements.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About these grades")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
