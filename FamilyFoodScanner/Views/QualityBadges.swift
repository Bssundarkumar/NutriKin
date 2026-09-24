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

/// "Try this instead": better-scoring products from the same category.
struct AlternativesSection: View {
    enum Phase { case loading, loaded([Alternative]), unavailable }
    let phase: Phase

    var body: some View {
        switch phase {
        case .unavailable:
            EmptyView()
        case .loading:
            Section("Try this instead") {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Looking for better options\u{2026}").font(.footnote).foregroundStyle(.secondary)
                }
            }
        case .loaded(let items):
            if !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        NavigationLink { ResultView(product: item.product) } label: {
                            AlternativeRow(item: item)
                        }
                    }
                } header: {
                    Text("Try this instead")
                } footer: {
                    Text("Popular products filed in the same category that score better for everyone in your family, compared per 100 g. Categories come from Open Food Facts and can occasionally be off, so check that it suits what you need, and check the label.")
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
