import SwiftUI

/// Shared building blocks so every screen looks and behaves the same way.
/// Cards use `card()`, headings use `SectionTitle`, and empty screens use `EmptyState`.

struct SectionTitle: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?
    /// An optional small colored icon chip before the title, for a screen with several sections where a
    /// touch of color per heading makes them easier to tell apart at a glance.
    var symbol: String? = nil
    var tint: Color = Theme.brand
    /// A smaller icon, title and action, for use in a half-width (two-column) card — the full-size title
    /// wraps letter by letter once the icon and action button are also competing for that little width.
    var compact: Bool = false
    /// Adds a trailing chevron after the action text, e.g. "See all ›" — used for actions that open
    /// another screen; left off for an action like "Add +" that does something right on this card.
    var actionShowsChevron: Bool = false

    var body: some View {
        ReadableStack(spacing: 8) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol).readableFont(16, weight: .bold)
                        .foregroundStyle(tint)
                        .frame(width: 30, height: 30)
                        .background(tint.opacity(0.12), in: Circle())
                }
                Text(title).readableFont(compact ? 18 : 22, weight: .bold, relativeTo: .headline)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                        if actionShowsChevron { Image(systemName: "chevron.right").readableFont(14, weight: .semibold) }
                    }.frame(minHeight: 44)
                }
                .readableFont(17, weight: .semibold)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

/// A small tile with one number, used in rows of two or three.
struct StatTile: View {
    let title: String
    let value: String
    var symbol: String?
    var tint: Color = Theme.brand
    @ScaledMetric(relativeTo: .caption) private var labelHeight: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 5) {
                if let symbol { Image(systemName: symbol).readableFont(15, weight: .semibold, relativeTo: .caption).foregroundStyle(tint) }
                Text(title).readableFont(15, relativeTo: .caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: labelHeight, alignment: .topLeading)
            Text(value).readableFont(22, weight: .bold, design: .rounded, relativeTo: .title3).monospacedDigit()
                .minimumScaleFactor(0.85).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Three of these sit side by side: past this size there's no room to grow further without breaking
        // (wrapping letter by letter), so the shrink-to-fit above takes over instead of the text growing more.
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
            Text(title).readableFont(19, weight: .semibold, relativeTo: .headline)
            Text(message).readableFont(17, weight: .regular, relativeTo: .subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                    .readableFont(24, weight: .semibold, design: .default)
                    .frame(width: 58, height: 58)
                    .background(tint.opacity(0.14), in: Circle())
                    .foregroundStyle(tint)
                Text(title).readableFont(15, weight: .semibold, relativeTo: .caption).foregroundStyle(.primary)
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
    /// For things like fibre, where reaching the target is good and falling short is what needs a nudge.
    var goodWhenHigh = false

    private var color: Color {
        if goodWhenHigh { return share >= 0.7 ? .green : share >= 0.35 ? .orange : .red.opacity(0.75) }
        return share >= 1 ? .red : share >= 0.8 ? .orange : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).readableFont(17, weight: .medium).fixedSize(horizontal: false, vertical: true)
                Text(detail).readableFont(15, relativeTo: .caption).foregroundStyle(.secondary).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityValue(goodWhenHigh ? "\(Int((share * 100).rounded())) percent of the daily target" : "\(Int((share * 100).rounded())) percent of the daily limit")
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
                            Image(systemName: (m.age.map { $0 < 18 } ?? false) ? "face.smiling.fill" : "person.fill")
                                .readableFont(22, weight: .semibold, relativeTo: .subheadline)
                                .accessibilityHidden(true)
                            Text(m.name).readableFont(17, weight: selected ? .bold : .medium, relativeTo: .subheadline)
                                .lineLimit(1).fixedSize()
                        }
                        .foregroundStyle(selected ? Theme.brand : .secondary)
                        .frame(minWidth: 86, minHeight: 48)
                        .padding(.horizontal, 12)
                        .background(selected ? Theme.brand.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.bottom, 7)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(selected ? Theme.brand : .clear).frame(height: 3)
                                .padding(.horizontal, 5)
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2).padding(.vertical, 4)
        }
    }
}

/// Comfortable base sizes that continue to follow the user's preferred iPhone text size.
private struct ReadableFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    func readableFont(_ size: CGFloat = 18, weight: Font.Weight = .regular,
                      design: Font.Design = .default, relativeTo: Font.TextStyle = .body) -> some View {
        modifier(ReadableFont(size: size, weight: weight, design: design, relativeTo: relativeTo))
    }
}

/// Related content stays side by side normally and stacks when larger text needs the space.
struct ReadableStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        let layout = textSize >= .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
        layout { content() }
    }
}

/// Small descriptive badges wrap into another line instead of shrinking or hiding their text.
struct ReadableTagFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                  proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrangement(width: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let available = width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        var frames: [CGRect] = []
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: available, height: nil))
            if x > 0 && x + size.width > available {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: width ?? usedWidth, height: y + rowHeight), frames)
    }
}

/// Always one row; larger accessibility text gets room through horizontal scrolling.
struct SingleRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .body) private var itemWidth: CGFloat = 105
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        if textSize.isAccessibilitySize {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    Group { content() }.frame(width: itemWidth)
                }
            }
        } else {
            EqualWidthRow(spacing: spacing) { content() }
        }
    }
}

/// Gives every tile the same width and the tallest tile's height.
private struct EqualWidthRow: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width } + spacing * CGFloat(max(0, subviews.count - 1))
        let itemWidth = max(0, (width - spacing * CGFloat(max(0, subviews.count - 1))) / CGFloat(max(1, subviews.count)))
        let height = subviews.map { $0.sizeThatFits(.init(width: itemWidth, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = max(0, (bounds.width - spacing * CGFloat(max(0, subviews.count - 1))) / CGFloat(max(1, subviews.count)))
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.minY), proposal: .init(width: width, height: bounds.height))
        }
    }
}
