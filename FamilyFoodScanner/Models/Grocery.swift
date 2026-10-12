import Foundation

struct GroceryItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var householdId: UUID?
    var name: String
    var quantity: String?
    var note: String?
    var barcode: String?
    var addedBy: UUID?
    var addedAt = Date()
}
