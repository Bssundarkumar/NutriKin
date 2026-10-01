import SwiftUI

/// The top of the result screen: the product, and one clear answer for the family.
struct ResultHero: View {
    let product: Product
    let results: [MemberScore]

    @State private var imageShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var worst: Verdict? { results.map(\.verdict).min() }
    private var lowest: Int? { results.map(\.score).min() }
    private var allergyNames: [String] { results.filter(\.blockedByAllergy).map(\.member.name) }
    private var tint: Color { worst.map(Theme.color(for:)) ?? Theme.brand }

    private var headline: String {
        if !allergyNames.isEmpty { return "Allergy alert" }
        switch worst {
        case .okay: return "Good for everyone"
        case .caution: return "Fine with some care"
        case .avoid: return "Not great for someone"
        case nil: return "Product details"
        }
    }

    private var subline: String {
        if !allergyNames.isEmpty { return "Contains something \(allergyNames.joined(separator: ", ")) is allergic to." }
        let flagged = results.filter { $0.verdict != .okay }.map(\.member.name)
        if flagged.isEmpty { return results.isEmpty ? "Add family members to see scores." : "Every family member scores well." }
        return "Look closer for \(flagged.joined(separator: ", "))."
    }

    private var symbol: String {
        if !allergyNames.isEmpty { return "exclamationmark.triangle.fill" }
        switch worst {
        case .okay: return "checkmark.seal.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .avoid: return "xmark.octagon.fill"
        case nil: return "fork.knife"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            ReadableStack(spacing: 14) {
                AsyncImage(url: product.imageURL) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "fork.knife").readableFont(24, weight: .regular, relativeTo: .title2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.12))
                }
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .scaleEffect(imageShown ? 1 : 0.6)
                .rotationEffect(.degrees(imageShown ? 0 : -6))
                .opacity(imageShown ? 1 : 0)

                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name).readableFont(22, weight: .bold, relativeTo: .title3).lineLimit(3)
                    if let brand = product.brand {
                        Text(brand).readableFont(17, weight: .regular, relativeTo: .subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let lowest {
                ReadableStack(spacing: 16) {
                    ScoreRing(score: lowest, color: tint, size: 72, lineWidth: 8)
                    VStack(alignment: .leading, spacing: 4) {
                        Label {
                            Text(headline).readableFont(19, weight: .semibold, relativeTo: .headline)
                        } icon: {
                            Image(systemName: symbol)
                                .symbolEffect(.bounce, options: .nonRepeating, value: imageShown)
                        }
                        .foregroundStyle(tint)
                        Text(subline).readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.secondary)
                        Text("Lowest score in the family").readableFont(15, weight: .regular, relativeTo: .caption2).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .card(tint: tint)
        .onAppear {
            if reduceMotion { imageShown = true }
            else { withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) { imageShown = true } }
        }
    }
}
