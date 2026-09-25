import Foundation

enum WorkoutIntensity: String, Codable, CaseIterable, Identifiable {
    case light, moderate, vigorous
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum WorkoutKind: String, Codable, CaseIterable, Identifiable {
    case walking, running, cycling, swimming, yoga, strength, hiit, dance, sports, housework, other
    // Activities children do. Older app versions read these as "other".
    case play, playground, ballGames, martialArts, schoolPE
    // Gentle activities for older adults. Older app versions read these as "other".
    case taiChi, chairExercise, gardening, stretching
    var id: String { rawValue }

    private static let kidOnly: [WorkoutKind] = [.play, .playground, .ballGames, .martialArts, .schoolPE]
    private static let gentleOnly: [WorkoutKind] = [.taiChi, .chairExercise, .gardening, .stretching]
    /// What the activity picker offers: kid-friendly choices for children, the usual list for everyone else.
    static func choices(forChild child: Bool) -> [WorkoutKind] {
        child ? [.play, .playground, .ballGames, .cycling, .swimming, .running, .walking, .dance, .martialArts, .schoolPE, .yoga, .other]
              : allCases.filter { !kidOnly.contains($0) && !gentleOnly.contains($0) }
    }

    /// The picker for one person: play for children, gentle options first for older adults, the usual list otherwise.
    static func choices(for member: Member) -> [WorkoutKind] {
        if TodayLayout.isChild(member) { return choices(forChild: true) }
        if TodayLayout.isOlderAdult(member) {
            return [.walking, .taiChi, .chairExercise, .stretching, .gardening, .yoga, .swimming, .cycling, .dance, .strength, .housework, .other]
        }
        return choices(forChild: false)
    }

    var title: String {
        switch self {
        case .hiit: "HIIT"
        case .housework: "Housework"
        case .taiChi: "Tai chi"
        case .chairExercise: "Chair exercises"
        case .stretching: "Stretching"
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
        case .taiChi: "figure.mind.and.body"
        case .chairExercise: "figure.seated.side.right"
        case .gardening: "leaf.fill"
        case .stretching: "figure.flexibility"
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
        case .taiChi: (2.0, 3.0, 4.0)
        case .chairExercise: (1.8, 2.5, 3.5)
        case .gardening: (2.5, 3.8, 5.0)
        case .stretching: (2.0, 2.3, 3.0)
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
