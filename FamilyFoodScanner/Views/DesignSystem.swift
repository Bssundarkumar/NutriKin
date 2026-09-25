import SwiftUI

/// Shared building blocks so every screen looks and behaves the same way.
/// Cards use `card()`, headings use `SectionTitle`, and empty screens use `EmptyState`.

struct SectionTitle: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 4)
    }
}

/// A small tile with one number, used in rows of two or three.
struct StatTile: View {
    let title: String
    let value: String
    var symbol: String?
    var tint: Color = Theme.brand

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.semibold)).foregroundStyle(tint) }
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                .minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(Theme.brandGradient)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).buttonBorderShape(.capsule).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24).padding(.horizontal, 16)
    }
}

/// A round icon button with a label under it, for the row of quick actions on Today.
struct QuickAction: View {
    let title: String
    let symbol: String
    var tint: Color = Theme.brand
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 58, height: 58)
                    .background(tint.opacity(0.14), in: Circle())
                    .foregroundStyle(tint)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableStyle())
    }
}

/// One nutrient against its daily limit: green, then orange from 80%, red once passed.
struct NutrientBar: View {
    let title: String
    let share: Double
    let detail: String

    private var color: Color { share >= 1 ? .red : share >= 0.8 ? .orange : .green }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule().fill(color.gradient).frame(width: geo.size.width * min(max(share, 0.02), 1))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int((share * 100).rounded())) percent of the daily limit")
    }
}

/// Avatar chips for choosing which family member a screen is about.
struct MemberStrip: View {
    let members: [Member]
    let selectedID: UUID?
    let onSelect: (Member) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(members) { m in
                    let selected = m.id == selectedID
                    Button { onSelect(m) } label: {
                        HStack(spacing: 8) {
                            Avatar(name: m.name, size: 30)
                            Text(m.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        }
                        .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
                        .background(selected ? Theme.brand.opacity(0.16) : Color(.secondarySystemGroupedBackground), in: Capsule())
                        .overlay(Capsule().strokeBorder(selected ? Theme.brand : .clear, lineWidth: 2))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2).padding(.vertical, 4)
        }
    }
}
