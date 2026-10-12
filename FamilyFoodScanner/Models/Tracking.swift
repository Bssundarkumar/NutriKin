import Foundation

enum FoodSource: String, Codable, Hashable { case scan, plate, manual, ai }

/// One thing a family member ate. Numbers are for the amount actually eaten, not per 100 g.
struct FoodEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var householdId: UUID?
    var memberId: UUID
    var eatenAt = Date()
    var label: String
    var barcode: String?
    var source: FoodSource = .manual
    var calories = 0.0
    var sugarG = 0.0
    var carbsG = 0.0
    var sodiumMg = 0.0
    var satFatG = 0.0
    var proteinG = 0.0
    var fiberG = 0.0
    var fatG = 0.0
}

/// Rows saved before fibre and total fat were tracked don't have those columns, so they read as zero.
extension FoodEntry {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        householdId = try c.decodeIfPresent(UUID.self, forKey: .householdId)
        memberId = try c.decode(UUID.self, forKey: .memberId)
        eatenAt = try c.decode(Date.self, forKey: .eatenAt)
        label = try c.decode(String.self, forKey: .label)
        barcode = try c.decodeIfPresent(String.self, forKey: .barcode)
        source = try c.decodeIfPresent(FoodSource.self, forKey: .source) ?? .manual
        calories = try c.decodeIfPresent(Double.self, forKey: .calories) ?? 0
        sugarG = try c.decodeIfPresent(Double.self, forKey: .sugarG) ?? 0
        carbsG = try c.decodeIfPresent(Double.self, forKey: .carbsG) ?? 0
        sodiumMg = try c.decodeIfPresent(Double.self, forKey: .sodiumMg) ?? 0
        satFatG = try c.decodeIfPresent(Double.self, forKey: .satFatG) ?? 0
        proteinG = try c.decodeIfPresent(Double.self, forKey: .proteinG) ?? 0
        fiberG = try c.decodeIfPresent(Double.self, forKey: .fiberG) ?? 0
        fatG = try c.decodeIfPresent(Double.self, forKey: .fatG) ?? 0
    }
}
