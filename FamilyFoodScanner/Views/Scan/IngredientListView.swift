import SwiftUI

/// The ingredient list. With amounts, each ingredient is a row with a bar sized
/// to its share of the product (tap a flagged one for why); without amounts it
/// falls back to compact chips. Ingredients worth limiting are orange and
/// allergens in the family are red. Long lists start collapsed.
struct IngredientListView: View {
    let rows: [IngredientRow]
    /// Turn off to show the finished state at once (previews and snapshots).
    var animate = true
    private let collapsedCount = 8
    @State private var showAll = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasAmounts: Bool { rows.contains { $0.percent != nil } }
    private var canCollapse: Bool { rows.count > collapsedCount + 2 }
    private var visible: [IngredientRow] { showAll || !canCollapse ? rows : Array(rows.prefix(collapsedCount)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasAmounts { CompositionBar(rows: rows, animate: animate) }

            if hasAmounts {
                VStack(spacing: 2) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { position, row in
                        AmountRow(row: row, position: position, animate: animate)
                    }
                }
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(visible) { ChipView(row: $0) }
                }
            }

            if canCollapse {
                Button(showAll ? "Show fewer" : "Show all \(rows.count) ingredients") {
                    withAnimation(reduceMotion ? nil : .snappy) { showAll.toggle() }
                }
                .font(.footnote.weight(.semibold))
            }

            HStack(spacing: 12) {
                if rows.contains(where: { $0.kind == .limit }) { legend(.orange, "Worth limiting") }
                if rows.contains(where: { $0.kind == .allergen }) { legend(.red, "Allergen in your family") }
                Spacer(minLength: 0)
            }
            Text(hasAmounts
                 ? "In label order. \u{201C}~\u{201D} amounts are estimates; the rest are printed on the label."
                 : "Listed from largest to smallest amount.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Composition bar

/// One bar showing what the product is made of, coloured by what's in it,
/// with a plain-language line about how much is worth limiting.
private struct CompositionBar: View {
    let rows: [IngredientRow]
    @State private var grown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(rows: [IngredientRow], animate: Bool) {
        self.rows = rows
        _grown = State(initialValue: !animate)
    }

    private struct Segment: Identifiable { let id: Int; let fraction: Double; let color: Color }

    private var segments: [Segment] {
        var used = 0.0
        var out: [Segment] = []
        var greenIndex = 0
        let shades: [Color] = [Color(red: 0.12, green: 0.35, blue: 0.24), Color(red: 0.25, green: 0.55, blue: 0.35),
                               Color(red: 0.45, green: 0.72, blue: 0.45), Color(red: 0.65, green: 0.82, blue: 0.6)]
        for row in rows {
            guard let p = row.percent, p >= 2, used < 100 else { continue }
            let f = min(p, 100 - used) / 100
            used += p
            let color: Color
            switch row.kind {
            case .limit: color = .orange
            case .allergen: color = .red
            case .plain: color = shades[greenIndex % shades.count]; greenIndex += 1
            }
            out.append(Segment(id: row.id, fraction: f, color: color))
        }
        if used < 99 { out.append(Segment(id: -1, fraction: (100 - used) / 100, color: .secondary.opacity(0.25))) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(segments) { seg in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(seg.color)
                            .frame(width: grown ? max(seg.fraction * (geo.size.width - 2 * CGFloat(segments.count - 1)), 2) : 0)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            if let share = IngredientRows.flaggedShare(rows), share >= 1 {
                Text("About \(Int(share.rounded()))% of this product is made of ingredients worth limiting or allergens.")
                    .font(.footnote)
                    .foregroundStyle(share >= 50 ? Color.orange : Color.secondary)
            }
        }
        .onAppear {
            if reduceMotion { grown = true } else { withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.1)) { grown = true } }
        }
    }
}

// MARK: - Rows and chips

private struct AmountRow: View {
    let row: IngredientRow
    let position: Int
    @State private var expanded = false
    @State private var grown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(row: IngredientRow, position: Int, animate: Bool) {
        self.row = row
        self.position = position
        _grown = State(initialValue: !animate)
    }

    private var tint: Color {
        switch row.kind { case .plain: .secondary; case .limit: .orange; case .allergen: .red }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle().fill(row.kind == .plain ? Color.secondary.opacity(0.35) : tint).frame(width: 8, height: 8)
                Text(row.text)
                    .font(.subheadline)
                    .foregroundStyle(row.kind == .plain ? Color.primary : tint)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let label = row.amountLabel {
                    Text(label).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                if row.note != nil {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }

            if let percent = row.percent {
                GeometryReader { geo in
                    Capsule().fill(Color.secondary.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule().fill(row.kind == .plain ? Color(red: 0.25, green: 0.55, blue: 0.35) : tint)
                                .frame(width: grown ? max(geo.size.width * min(percent, 100) / 100, percent > 0 ? 3 : 0) : 0)
                        }
                }
                .frame(height: 5)
            }

            if expanded, let note = row.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard row.note != nil else { return }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { expanded.toggle() }
        }
        .onAppear {
            if reduceMotion { grown = true }
            else { withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.04 * Double(min(position, 12)))) { grown = true } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(row.note != nil ? "Double tap to \(expanded ? "hide" : "show") details" : "")
    }
}

private struct ChipView: View {
    let row: IngredientRow

    var body: some View {
        Text(row.text)
            .font(.footnote)
            .lineLimit(4)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch row.kind { case .plain: Color.secondary.opacity(0.12); case .limit: Color.orange.opacity(0.18); case .allergen: Color.red.opacity(0.18) }
    }
    private var foreground: Color {
        switch row.kind { case .plain: .primary; case .limit: .orange; case .allergen: .red }
    }
}

/// Wraps its children onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                                  proposal: ProposedViewSize(result.sizes[index]))
        }
    }

    private func layout(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint], sizes: [CGSize]) {
        var origins: [CGPoint] = [], sizes: [CGSize] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > maxWidth { size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil)) }
            if x > 0, x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y)); sizes.append(size)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: min(widest, maxWidth.isFinite ? maxWidth : widest), height: y + rowHeight), origins, sizes)
    }
}
