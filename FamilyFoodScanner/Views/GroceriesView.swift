import SwiftUI

/// The family's shared grocery list. Anyone adds items; tapping the circle when you've bought something
/// removes it for everyone, with a few seconds to undo.
struct GroceriesView: View {
    @Environment(FamilyStore.self) private var family
    @Environment(GroceryStore.self) private var groceries
    @State private var name = ""
    @State private var quantity = ""
    @State private var justBought = Set<UUID>()
    @State private var notice: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section { addCard }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                if groceries.items.isEmpty && !groceries.isLoading {
                    EmptyState(symbol: "cart", title: "Nothing to buy", message: "Add what the family needs. Everyone sees the same list on their own iPhone.")
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(groceries.items) { item in row(item) }
                            .onDelete { offsets in
                                let removing = offsets.map { groceries.items[$0] }
                                Task { await groceries.remove(removing) }
                            }
                    } header: {
                        Text("To buy \u{00B7} \(groceries.items.count)")
                    } footer: {
                        Text("Tap the circle when you've bought it. It's removed for everyone.")
                    }
                }
                if let message = groceries.errorMessage { Section { Text(message).font(.footnote).foregroundStyle(.red) } }
            }
            .softList()
            .navigationTitle("Groceries")
            .overlay { if groceries.isLoading && groceries.items.isEmpty { ProgressView() } }
            .refreshable { await groceries.load(householdId: family.householdId) }
            .animation(.snappy, value: groceries.items)
            .safeAreaInset(edge: .bottom) { undoBanner }
            // Keeps the list fresh while it's on screen, so items added on another phone show up.
            .task(id: family.householdId) {
                while !Task.isCancelled {
                    await groceries.load(householdId: family.householdId)
                    try? await Task.sleep(for: .seconds(15))
                }
            }
        }
    }

    private var addCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.brand).font(.title3)
                TextField("Add an item", text: $name).focused($focused).submitLabel(.done).onSubmit { add() }
                TextField("Qty", text: $quantity).frame(width: 64).multilineTextAlignment(.trailing).foregroundStyle(.secondary)
                Button("Add") { add() }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    private func row(_ item: GroceryItem) -> some View {
        let bought = justBought.contains(item.id)
        return Button { buy(item) } label: {
            HStack(spacing: 12) {
                Image(systemName: bought ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(bought ? Theme.brand : .secondary)
                    .symbolEffect(.bounce, value: bought)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.body.weight(.medium)).strikethrough(bought).foregroundStyle(bought ? .secondary : .primary)
                    if let note = item.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if let q = item.quantity { Text(q).font(.subheadline).foregroundStyle(.secondary) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name)\(item.quantity.map { ", \($0)" } ?? ""). Double tap when bought.")
        .listRowBackground(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)).padding(.vertical, 3))
        .listRowSeparator(.hidden)
    }

    private func buy(_ item: GroceryItem) {
        guard !justBought.contains(item.id) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy) { _ = justBought.insert(item.id) }
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            await groceries.markBought(item)
            justBought.remove(item.id)
        }
    }

    private func add() {
        let text = name
        let qty = quantity
        notice = nil
        Task {
            switch await groceries.add(name: text, quantity: qty) {
            case .added: name = ""; quantity = ""; UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .duplicate: notice = "\u{201C}\(GroceryRules.cleanName(text))\u{201D} is already on the list."
            case .failed: break
            }
        }
    }

    @ViewBuilder
    private var undoBanner: some View {
        if let last = groceries.lastRemoved.first {
            HStack {
                Text("Removed \u{201C}\(last.name)\u{201D}").font(.subheadline).lineLimit(1)
                Spacer()
                Button("Undo") { Task { await groceries.undoLastRemoval() } }.font(.subheadline.weight(.bold))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .padding(.horizontal, 16).padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: last.id) {
                try? await Task.sleep(for: .seconds(6))
                groceries.dismissUndo()
            }
        }
    }
}
