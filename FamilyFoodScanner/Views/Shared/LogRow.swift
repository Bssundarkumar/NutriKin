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
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if onTap != nil { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
            Text(trailing).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            Menu {
                if let onEdit { Button("Edit", systemImage: "pencil", action: onEdit) }
                Button("Remove", systemImage: "trash", role: .destructive, action: onDelete)
            } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 30, height: 34) }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .padding(.vertical, 8)
    }
}
