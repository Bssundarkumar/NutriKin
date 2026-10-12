import SwiftUI

/// One logged item (a meal or a workout): icon, title, detail, a trailing figure, and a menu to edit or remove it.
struct LogRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let trailing: String
    let tint: Color
    var onTap: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: Circle()).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).readableFont(17, weight: .semibold, relativeTo: .subheadline).lineLimit(2)
                Text(subtitle).readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            if onTap != nil { Image(systemName: "chevron.right").readableFont(15, weight: .regular, relativeTo: .caption2).foregroundStyle(.tertiary) }
            Text(trailing).readableFont(17, weight: .regular, relativeTo: .subheadline).monospacedDigit().foregroundStyle(.secondary)
            Menu {
                if let onEdit { Button("Edit", systemImage: "pencil", action: onEdit) }
                Button("Remove", systemImage: "trash", role: .destructive, action: onDelete)
            } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 44, height: 44) }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .padding(.vertical, 8)
    }
}

/// Swipe actions for cards inside a ScrollView. A swipe reveals Delete; a tap confirms it.
/// Vertical drags continue to scroll, and the same action is available to VoiceOver.
private struct SlideDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var isOpen = false
    @GestureState private var drag: CGFloat = 0
    private let actionWidth: CGFloat = 88

    private var offset: CGFloat { min(max((isOpen ? -actionWidth : 0) + drag, -actionWidth), 0) }

    var body: some View {
        content()
            .background(Color(.secondarySystemGroupedBackground))
            .offset(x: offset)
            .background(alignment: .trailing) {
                Button(role: .destructive) {
                    withAnimation(.snappy) { isOpen = false; onDelete() }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "trash")
                        Text("Delete").readableFont(15, weight: .semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(width: actionWidth).frame(maxHeight: .infinity)
                    .frame(minHeight: 44)
                    .background(Color.red)
                }
                .buttonStyle(.plain)
                .opacity(offset < 0 ? 1 : 0)
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)
            }
            .clipped()
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .updating($drag) { value, state, _ in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        state = value.translation.width
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        withAnimation(.snappy) {
                            if value.translation.width < -30 { isOpen = true }
                            else if value.translation.width > 30 { isOpen = false }
                        }
                    }
            )
            .accessibilityAction(named: Text(isOpen ? "Hide Delete" : "Show Delete")) {
                withAnimation(.snappy) { isOpen.toggle() }
            }
            .accessibilityAction(named: Text("Delete"), onDelete)
    }
}

extension View {
    @ViewBuilder
    func slideToDelete(enabled: Bool = true, action: @escaping () -> Void) -> some View {
        if enabled { SlideDeleteRow(onDelete: action) { self } }
        else { self }
    }
}
