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

enum WorkoutIntensity: String, Codable, CaseIterable, Identifiable {
    case light, moderate, vigorous
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum WorkoutKind: String, Codable, CaseIterable, Identifiable {
    case walking, running, cycling, swimming, yoga, strength, hiit, dance, sports, housework, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hiit: "HIIT"
        case .housework: "Housework"
        default: rawValue.capitalized
        }
    }

    var symbol: String {
        switch self {
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .yoga: "figure.yoga"
        case .strength: "dumbbell.fill"
        case .hiit: "bolt.heart.fill"
        case .dance: "figure.dance"
        case .sports: "sportscourt.fill"
        case .housework: "house.fill"
        case .other: "figure.mixed.cardio"
        }
    }

    /// Metabolic equivalents (MET) for light, moderate and vigorous effort, rounded from the
    /// Compendium of Physical Activities. Estimates, not measurements.
    func met(_ intensity: WorkoutIntensity) -> Double {
        let (light, moderate, vigorous): (Double, Double, Double) = switch self {
        case .walking: (2.8, 3.5, 5.0)
        case .running: (7.0, 9.8, 11.5)
        case .cycling: (4.0, 6.8, 10.0)
        case .swimming: (5.0, 6.0, 9.8)
        case .yoga: (2.5, 3.0, 4.0)
        case .strength: (3.5, 5.0, 6.0)
        case .hiit: (6.0, 8.0, 10.0)
        case .dance: (4.5, 5.5, 7.0)
        case .sports: (5.0, 7.0, 9.0)
        case .housework: (2.5, 3.5, 5.0)
        case .other: (3.0, 5.0, 7.0)
        }
        switch intensity { case .light: return light; case .moderate: return moderate; case .vigorous: return vigorous }
    }
}

struct Workout: Identifiable, Codable, Hashable {
    var id = UUID()
    var householdId: UUID?
    var memberId: UUID
    var doneAt = Date()
    var kind: String
    var minutes: Int
    var intensity: WorkoutIntensity = .moderate
    var caloriesBurned: Int
    var note: String?
    /// "health" for workouts imported from Apple Health; nil for ones typed in.
    var source: String? = nil
    /// The Health app's id for an imported workout, so it's never added twice.
    var externalId: String? = nil

    var workoutKind: WorkoutKind { WorkoutKind(rawValue: kind) ?? .other }
}

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
