import Foundation

/// A group of adult friends who share their workouts with each other (up to 20).
struct BuddyGroup: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var inviteCode: String
}

/// One person in a group. `displayName` is what buddies see; nothing else about them is shared except their workouts.
struct Buddy: Identifiable, Codable, Hashable {
    var groupId: UUID
    var userId: UUID
    var memberId: UUID
    var displayName: String
    var id: String { "\(groupId.uuidString)-\(userId.uuidString)" }
}

/// A buddy's workout, with the name to show.
struct BuddyPost: Identifiable, Hashable {
    var workout: Workout
    var name: String
    var id: UUID { workout.id }
}

enum BuddyMath {
    static let maxGroupSize = 20

    struct Line: Identifiable, Equatable {
        var name: String
        var sessions: Int
        var minutes: Int
        var volumeKg: Double
        var id: String { name }
    }

    /// Sessions, minutes and total weight lifted since `start`, per person, busiest first. Encouragement only: no ranking words.
    static func week(_ posts: [BuddyPost], since start: Date) -> [Line] {
        Dictionary(grouping: posts.filter { $0.workout.doneAt >= start }, by: \.name).map { name, list in
            Line(name: name, sessions: list.count, minutes: list.reduce(0) { $0 + $1.workout.minutes },
                 volumeKg: list.reduce(0) { $0 + StrengthMath.volumeKg($1.workout.exercises ?? []) })
        }
        .sorted { ($0.minutes, $1.name) > ($1.minutes, $0.name) }
    }

    /// Strength sessions that share at least one exercise with what you did, so you can spot a workout to copy.
    static func sharedExercises(_ post: BuddyPost, with mine: [StrengthExercise]) -> [String] {
        let names = Set(mine.map { $0.name.lowercased() })
        return (post.workout.exercises ?? []).map(\.name).filter { names.contains($0.lowercased()) }
    }
}
