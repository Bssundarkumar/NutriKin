import Foundation
import Observation
import Supabase

/// The family's shared grocery list. Anyone can add; buying an item removes it for everyone.
@MainActor
@Observable
final class GroceryStore {
    enum AddResult: Equatable { case added, duplicate, failed }

    private(set) var items: [GroceryItem] = []
    var isLoading = false
    var errorMessage: String?
    /// The most recently removed items, so a mistaken tap can be undone.
    private(set) var lastRemoved: [GroceryItem] = []

    private var householdId: UUID?
    private var client: SupabaseClient { Backend.client }

    func load(householdId: UUID?) async {
        if Demo.isOn { if items.isEmpty { items = Demo.groceries }; return }
        self.householdId = householdId
        guard let householdId else { items = []; return }
        isLoading = items.isEmpty
        defer { isLoading = false }
        do {
            items = try await Backend.withRetry {
                try await client.from("grocery_items").select()
                    .eq("household_id", value: householdId).order("added_at").execute().value
            }
            errorMessage = nil
        } catch {
            if items.isEmpty { errorMessage = "Couldn't load the grocery list. \(error.localizedDescription)" }
        }
    }

    private struct NewItem: Encodable {
        var householdId: UUID, name: String, quantity: String?, note: String?, barcode: String?
    }

    @discardableResult
    func add(name raw: String, quantity: String? = nil, note: String? = nil, barcode: String? = nil) async -> AddResult {
        let name = GroceryRules.cleanName(raw)
        guard !name.isEmpty else { return .failed }
        guard !GroceryRules.isDuplicate(name, in: items) else { return .duplicate }
        errorMessage = nil
        let qty = quantity.map { AIGuardrails.sanitize($0, max: 40) }
        let item = GroceryItem(householdId: householdId, name: name, quantity: (qty?.isEmpty == false) ? qty : nil,
                               note: note.map { AIGuardrails.sanitize($0, max: 200) }, barcode: barcode)
        if Demo.isOn { items.append(item); return .added }
        guard let householdId else { return .failed }
        do {
            let saved: GroceryItem = try await Backend.withRetry {
                try await client.from("grocery_items")
                    .insert(NewItem(householdId: householdId, name: item.name, quantity: item.quantity, note: item.note, barcode: item.barcode))
                    .select().single().execute().value
            }
            items.append(saved)
            return .added
        } catch {
            errorMessage = "Couldn't add that. \(error.localizedDescription)"
            return .failed
        }
    }

    /// Adds several names at once (for example a meal plan's ingredients). Returns how many were new.
    func addMany(_ names: [String]) async -> Int {
        var added = 0
        for name in GroceryRules.newNames(from: names, existing: items) {
            if await add(name: name) == .added { added += 1 }
        }
        return added
    }

    /// Buying an item removes it from the list for everyone.
    func markBought(_ item: GroceryItem) async { await remove([item]) }

    func remove(_ removing: [GroceryItem]) async {
        guard !removing.isEmpty else { return }
        errorMessage = nil
        let ids = Set(removing.map(\.id))
        items.removeAll { ids.contains($0.id) }
        lastRemoved = removing
        if Demo.isOn { return }
        do {
            let list = Array(ids)
            try await Backend.withRetry { try await client.from("grocery_items").delete().in("id", values: list).execute() }
        } catch {
            items.append(contentsOf: removing)
            items.sort { $0.addedAt < $1.addedAt }
            lastRemoved = []
            errorMessage = "Couldn't remove that. \(error.localizedDescription)"
        }
    }

    func undoLastRemoval() async {
        let restore = lastRemoved
        lastRemoved = []
        for item in restore { _ = await add(name: item.name, quantity: item.quantity, note: item.note, barcode: item.barcode) }
    }

    func dismissUndo() { lastRemoved = [] }

    func setHousehold(_ id: UUID?) { householdId = id }

    func reset() { items = []; lastRemoved = []; householdId = nil; errorMessage = nil }
}
