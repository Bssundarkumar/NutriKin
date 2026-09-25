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
    // Activities children do. Older app versions read these as "other".
    case play, playground, ballGames, martialArts, schoolPE
    var id: String { rawValue }

    private static let kidOnly: [WorkoutKind] = [.play, .playground, .ballGames, .martialArts, .schoolPE]
    /// What the activity picker offers: kid-friendly choices for children, the usual list for everyone else.
    static func choices(forChild child: Bool) -> [WorkoutKind] {
        child ? [.play, .playground, .ballGames, .cycling, .swimming, .running, .walking, .dance, .martialArts, .schoolPE, .yoga, .other]
              : allCases.filter { !kidOnly.contains($0) }
    }

    var title: String {
        switch self {
        case .hiit: "HIIT"
        case .housework: "Housework"
        case .play: "Free play"
        case .playground: "Playground"
        case .ballGames: "Ball games"
        case .martialArts: "Martial arts"
        case .schoolPE: "School PE"
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
        case .play: "figure.play"
        case .playground: "figure.climbing"
        case .ballGames: "soccerball"
        case .martialArts: "figure.martial.arts"
        case .schoolPE: "figure.run.circle"
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
        case .play: (3.5, 4.5, 6.0)
        case .playground: (3.5, 5.0, 6.5)
        case .ballGames: (4.0, 6.0, 8.0)
        case .martialArts: (4.0, 6.0, 10.0)
        case .schoolPE: (4.0, 5.5, 7.5)
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
    /// Strength workouts: the exercises done, each with its sets. Nil for everything else.
    var exercises: [StrengthExercise]? = nil

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

/// One set: how many reps at what weight (always stored in kilograms).
struct StrengthSet: Codable, Hashable {
    var reps: Int
    var weightKg: Double
}

struct StrengthExercise: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var sets: [StrengthSet]

    private enum CodingKeys: String, CodingKey { case name, sets }

    init(name: String, sets: [StrengthSet]) { self.name = name; self.sets = sets }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        sets = try c.decode([StrengthSet].self, forKey: .sets)
    }

    var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }
    /// Weight times reps, summed over the sets.
    var volumeKg: Double { sets.reduce(0) { $0 + Double($1.reps) * $1.weightKg } }
}

enum StrengthMath {
    static let commonExercises = ["Bench press", "Squat", "Deadlift", "Overhead press", "Barbell row", "Pull-up", "Push-up",
                                  "Lat pulldown", "Bicep curl", "Tricep extension", "Lunge", "Leg press", "Plank"]
    static let kgPerLb = 0.45359237

    /// About 2.5 minutes a set counts the lift and the rest after it, rounded to 5 minutes, at least 5.
    static func estimatedMinutes(sets: Int) -> Int { max(5, Int((Double(sets) * 2.5 / 5).rounded()) * 5) }

    static func totalSets(_ e: [StrengthExercise]) -> Int { e.reduce(0) { $0 + $1.sets.count } }
    static func totalReps(_ e: [StrengthExercise]) -> Int { e.reduce(0) { $0 + $1.totalReps } }
    static func volumeKg(_ e: [StrengthExercise]) -> Double { e.reduce(0) { $0 + $1.volumeKg } }

    /// Drops blank names and empty sets, clamps values and caps the list, so what is stored is always sane.
    static func cleaned(_ e: [StrengthExercise]) -> [StrengthExercise] {
        e.compactMap { ex in
            let name = AIGuardrails.sanitize(ex.name, max: 60)
            let sets = ex.sets.filter { $0.reps > 0 }.prefix(30).map {
                StrengthSet(reps: min($0.reps, 999), weightKg: min(max($0.weightKg, 0), 1000))
            }
            return name.isEmpty || sets.isEmpty ? nil : StrengthExercise(name: name, sets: Array(sets))
        }.prefix(30).map { $0 }
    }

    static func display(kg: Double, pounds: Bool) -> String {
        let v = pounds ? kg / kgPerLb : kg
        return v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}

/// Step and workout goals: the person's own, or a general starting point they can accept.
enum ActivityGoals {
    /// General guidance only (roughly WHO / common public-health targets), not a prescription.
    static func suggested(for member: Member) -> (steps: Int, weeklyMinutes: Int) {
        let age = member.age ?? (member.isManagedByParent ? 10 : 35)
        if age < 18 { return (10_000, 420) }          // about an hour of play a day
        if age >= 65 { return (6_000, 150) }
        return (8_000, 150)
    }

    /// Monday 00:00 of the week containing `date`.
    static func weekStart(_ date: Date = Date(), calendar: Calendar = .current) -> Date {
        var cal = calendar; cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    static func weeklyMinutes(_ workouts: [Workout], since start: Date) -> Int {
        workouts.filter { $0.doneAt >= start }.reduce(0) { $0 + $1.minutes }
    }

    /// 0...1 for a progress bar; nil when there's no goal.
    static func fraction(done: Int, goal: Int?) -> Double? {
        guard let goal, goal > 0 else { return nil }
        return min(Double(max(done, 0)) / Double(goal), 1)
    }
}

/// A saved set of exercises (with the sets, reps and weights used last time) to start a strength workout from.
struct WorkoutTemplate: Identifiable, Codable, Hashable {
    var id = UUID()
    var householdId: UUID?
    var memberId: UUID
    var name: String
    var exercises: [StrengthExercise]
}

/// A child's day of active play against the usual one-hour-a-day guidance, and a week of stars.
enum KidActivity {
    static let dailyGoalMinutes = 60

    static func minutes(_ workouts: [Workout], on day: Date, calendar: Calendar = .current) -> Int {
        workouts.filter { calendar.isDate($0.doneAt, inSameDayAs: day) }.reduce(0) { $0 + $1.minutes }
    }

    struct Day: Identifiable, Equatable {
        var date: Date
        var minutes: Int
        var id: Date { date }
        var earnedStar: Bool { minutes >= KidActivity.dailyGoalMinutes }
    }

    /// Monday to Sunday of the week containing `today`; days that haven't happened yet have no minutes.
    static func week(_ workouts: [Workout], today: Date = Date(), calendar: Calendar = .current) -> [Day] {
        let start = ActivityGoals.weekStart(today, calendar: calendar)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map {
            Day(date: $0, minutes: minutes(workouts, on: $0, calendar: calendar))
        }
    }

    static func stars(_ days: [Day]) -> Int { days.filter(\.earnedStar).count }

    /// A friendly line: always encouraging, never a failure.
    static func message(name: String, todayMinutes: Int) -> String {
        let left = max(dailyGoalMinutes - todayMinutes, 0)
        if left == 0 { return "\(name) got today's star! An hour of play is a big win." }
        if todayMinutes == 0 { return "A little play today? \(dailyGoalMinutes) minutes earns a star." }
        return "\(todayMinutes) minutes so far. \(left) more for today's star."
    }
}
