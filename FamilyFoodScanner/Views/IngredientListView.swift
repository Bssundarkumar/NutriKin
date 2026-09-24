import SwiftUI

/// The ingredient list as tidy chips in label order (largest to smallest
/// amount). Ingredients worth limiting turn orange, and an ingredient that is
/// an allergen for someone in the family turns red. Long lists start collapsed.
struct IngredientListView: View {
    struct Item: Identifiable {
        enum Kind { case plain, limit, allergen }
        let id: Int
        let text: String
        let kind: Kind
        var note: String?
    }

    let items: [Item]
    private let collapsedCount = 8
    @State private var showAll = false

    private var visible: [Item] {
        showAll || items.count <= collapsedCount + 2 ? items : Array(items.prefix(collapsedCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 6) {
                ForEach(visible) { IngredientChip(item: $0) }
            }

            if items.count > collapsedCount + 2 {
                Button(showAll ? "Show fewer" : "Show all \(items.count) ingredients") {
                    withAnimation(.easeInOut(duration: 0.2)) { showAll.toggle() }
                }
                .font(.footnote.weight(.semibold))
            }

            HStack(spacing: 12) {
                if items.contains(where: { $0.kind == .limit }) { legend(.orange, "Worth limiting") }
                if items.contains(where: { $0.kind == .allergen }) { legend(.red, "Allergen in your family") }
                Spacer(minLength: 0)
            }
            Text("Listed from largest to smallest amount.")
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

private struct IngredientChip: View {
    let item: IngredientListView.Item

    var body: some View {
        Text(item.text)
            .font(.footnote)
            .lineLimit(4)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(foreground)
            .accessibilityLabel(accessibility)
    }

    private var background: Color {
        switch item.kind {
        case .plain: Color.secondary.opacity(0.12)
        case .limit: Color.orange.opacity(0.18)
        case .allergen: Color.red.opacity(0.18)
        }
    }

    private var foreground: Color {
        switch item.kind {
        case .plain: .primary
        case .limit: .orange
        case .allergen: .red
        }
    }

    private var accessibility: String {
        switch item.kind {
        case .plain: item.text
        case .limit: "\(item.text), worth limiting"
        case .allergen: "\(item.text), allergen for someone in your family"
        }
    }
}

/// Wraps its children onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return layout(in: width, subviews: subviews).size
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
            // Never let one chip be wider than the row; long ones wrap onto extra lines.
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
