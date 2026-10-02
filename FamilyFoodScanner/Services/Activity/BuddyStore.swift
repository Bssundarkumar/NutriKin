import Foundation
import Observation
import Supabase

/// Gym buddy groups and the workouts buddies share (see `backend/migration_017_gym_buddies.sql`).
/// Access is enforced in the database: a buddy can read only the workouts of the person who joined, never the rest of their family.
@MainActor
@Observable
final class BuddyStore {
    private(set) var groups: [BuddyGroup] = []
    private(set) var buddies: [Buddy] = []
    private(set) var posts: [BuddyPost] = []
    private(set) var dayPosts: [BuddyPost] = []
    private(set) var activityDay: Date?
    var isLoadingDay = false
    @ObservationIgnored private var dayToken = UUID()
    var isLoading = false
    var errorMessage: String?
    private var client: SupabaseClient { Backend.client }
    @ObservationIgnored private var loadToken = UUID()

    func buddies(in group: BuddyGroup) -> [Buddy] { buddies.filter { $0.groupId == group.id } }

    func load(myUserId: UUID?) async {
        let token = UUID()
        loadToken = token
        guard let myUserId else {
            groups = []; buddies = []; posts = []; dayPosts = []; activityDay = nil; dayToken = UUID(); isLoadingDay = false; isLoading = false; errorMessage = nil
            return
        }
        isLoading = true; errorMessage = nil
        defer { if loadToken == token { isLoading = false } }
        do {
            let loadedGroups: [BuddyGroup] = try await Backend.withRetry { try await client.from("buddy_groups").select().order("created_at").execute().value }
            let loadedBuddies: [Buddy] = try await Backend.withRetry { try await client.from("buddy_members").select().order("joined_at").execute().value }
            let others = Set(loadedBuddies.filter { $0.userId != myUserId }.map(\.memberId))
            var loadedPosts: [BuddyPost] = []
            if !others.isEmpty {
                let since = Calendar.current.date(byAdding: .day, value: -21, to: Date()) ?? Date()
                let rows: [Workout] = try await Backend.withRetry {
                    try await client.from("workouts").select().in("member_id", values: Array(others))
                        .gte("done_at", value: ISO8601DateFormatter().string(from: since)).order("done_at", ascending: false).limit(200).execute().value
                }
                let names = Dictionary(loadedBuddies.map { ($0.memberId, $0.displayName) }, uniquingKeysWith: { a, _ in a })
                loadedPosts = rows.map { BuddyPost(workout: $0, name: names[$0.memberId] ?? "Buddy") }
            }
            guard loadToken == token else { return }
            groups = loadedGroups; buddies = loadedBuddies; posts = loadedPosts
        } catch {
            guard loadToken == token else { return }
            errorMessage = "Couldn't load your buddies. \(error.localizedDescription)"
        }
    }

    /// Fetch a chosen day's shared workouts independently of the recent-week summary window.
    func loadActivity(day: Date, myUserId: UUID?) async {
        let token = UUID(); dayToken = token
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let roster = buddies
        guard myUserId != nil, !roster.isEmpty else { dayPosts = []; activityDay = start; return }
        isLoadingDay = true
        if activityDay != start { dayPosts = []; activityDay = start }
        defer { if dayToken == token { isLoadingDay = false } }
        do {
            let ids = Array(Set(roster.map(\.memberId)))
            let rows: [Workout] = try await Backend.withRetry {
                try await client.from("workouts").select().in("member_id", values: ids)
                    .gte("done_at", value: ISO8601DateFormatter().string(from: start))
                    .lt("done_at", value: ISO8601DateFormatter().string(from: end))
                    .order("done_at", ascending: false).execute().value
            }
            guard dayToken == token else { return }
            let names = Dictionary(roster.map { ($0.memberId, $0.displayName) }, uniquingKeysWith: { a, _ in a })
            dayPosts = rows.map { BuddyPost(workout: $0, name: names[$0.memberId] ?? "Buddy") }
        } catch {
            guard dayToken == token else { return }
            errorMessage = "Couldn't load activity for this day. \(error.localizedDescription)"
        }
    }

    func analysisWorkouts(group: BuddyGroup, memberID: UUID, start: Date, end: Date) async throws -> [Workout] {
        guard buddies(in: group).contains(where: { $0.memberId == memberID }) else { return [] }
        return try await client.from("workouts").select().eq("member_id", value: memberID)
            .gte("done_at", value: ISO8601DateFormatter().string(from: start))
            .lt("done_at", value: ISO8601DateFormatter().string(from: end))
            .order("done_at").execute().value
    }

    struct GroupWorkoutRequest: Encodable {
        let p_batch: UUID
        let p_group: UUID
        let p_members: [UUID]
        let p_done_at: Date
        let p_kind: String
        let p_minutes: Int
        let p_intensity: String
        let p_note: String?
        let p_exercises: [StrengthExercise]?
        func encode(to encoder: Encoder) throws {
            enum Keys: String, CodingKey { case p_batch, p_group, p_members, p_done_at, p_kind, p_minutes, p_intensity, p_note, p_exercises }
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(p_batch, forKey: .p_batch); try c.encode(p_group, forKey: .p_group)
            try c.encode(p_members, forKey: .p_members)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try c.encode(formatter.string(from: p_done_at), forKey: .p_done_at)
            try c.encode(p_kind, forKey: .p_kind); try c.encode(p_minutes, forKey: .p_minutes)
            try c.encode(p_intensity, forKey: .p_intensity)
            try c.encode(p_note, forKey: .p_note); try c.encode(p_exercises, forKey: .p_exercises)
        }
    }

    func logGroupWorkout(_ request: GroupWorkoutRequest) async throws -> [Workout] {
        // A transaction inserts every selected participant or none. The batch ID makes retries safe.
        try await client.rpc("log_buddy_group_workout", params: request).execute().value
    }

    @discardableResult
    func create(name: String, member: Member, myUserId: UUID?) async -> Bool { await run("create_buddy_group", ["p_name": name, "p_member": member.id.uuidString], myUserId) }

    @discardableResult
    func join(code: String, member: Member, myUserId: UUID?) async -> Bool {
        await run("join_buddy_group", ["p_code": code.trimmingCharacters(in: .whitespaces).uppercased(), "p_member": member.id.uuidString], myUserId)
    }

    private func run(_ rpc: String, _ params: [String: String], _ myUserId: UUID?) async -> Bool {
        errorMessage = nil
        do {
            _ = try await Backend.withRetry { try await client.rpc(rpc, params: params).execute() }
            await load(myUserId: myUserId)
            return true
        } catch {
            errorMessage = Self.friendly(error)
            return false
        }
    }

    func leave(_ group: BuddyGroup, myUserId: UUID?) async {
        guard let myUserId else { return }
        do {
            try await Backend.withRetry { try await client.from("buddy_members").delete().eq("group_id", value: group.id).eq("user_id", value: myUserId).execute() }
            await load(myUserId: myUserId)
        } catch { errorMessage = "Couldn't leave the group. \(error.localizedDescription)" }
    }

    /// The database gives readable reasons (adult only, group full, wrong code); show them as they are.
    nonisolated static func friendly(_ error: Error) -> String {
        let text = error.localizedDescription
        for known in ["link yourself first", "gym buddies are for adults", "already in 5", "no group with that code", "group is full"] where text.contains(known) {
            return text
        }
        return "That didn't work. \(text)"
    }
}
