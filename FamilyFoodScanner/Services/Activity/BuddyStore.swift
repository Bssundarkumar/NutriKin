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
    var isLoading = false
    var errorMessage: String?
    private var client: SupabaseClient { Backend.client }

    func buddies(in group: BuddyGroup) -> [Buddy] { buddies.filter { $0.groupId == group.id } }

    func load(myUserId: UUID?) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            groups = try await Backend.withRetry { try await client.from("buddy_groups").select().order("created_at").execute().value }
            buddies = try await Backend.withRetry { try await client.from("buddy_members").select().order("joined_at").execute().value }
            let others = Set(buddies.filter { $0.userId != myUserId }.map(\.memberId))
            guard !others.isEmpty else { posts = []; return }
            let since = Calendar.current.date(byAdding: .day, value: -21, to: Date()) ?? Date()
            let rows: [Workout] = try await Backend.withRetry {
                try await client.from("workouts").select().in("member_id", values: Array(others))
                    .gte("done_at", value: ISO8601DateFormatter().string(from: since)).order("done_at", ascending: false).limit(200).execute().value
            }
            let names = Dictionary(buddies.map { ($0.memberId, $0.displayName) }, uniquingKeysWith: { a, _ in a })
            posts = rows.map { BuddyPost(workout: $0, name: names[$0.memberId] ?? "Buddy") }
        } catch {
            errorMessage = "Couldn't load your buddies. \(error.localizedDescription)"
        }
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
