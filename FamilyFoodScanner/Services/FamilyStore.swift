import Foundation
import Observation
import Supabase

/// The signed-in person's family and its members, backed by Supabase.
///
/// Access is enforced in the database (see `backend/migration_005_auth.sql`):
/// you can only see a family you belong to, and you join one with its invite
/// code. This class never decides who may see what; it just asks.
@MainActor
@Observable
final class FamilyStore {
    /// Where the "which family am I in?" lookup stands.
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var members: [Member] = []
    private(set) var householdId: UUID?
    private(set) var householdName: String = ""
    private(set) var inviteCode: String = ""
    var isLoading = false
    var errorMessage: String?

    private var client: SupabaseClient { Backend.client }

    var hasHousehold: Bool { householdId != nil }

    private struct HouseholdRow: Decodable {
        var id: UUID
        var name: String
        var inviteCode: String
    }

    @discardableResult
    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        try await Backend.withRetry(operation)
    }

    // MARK: - Which family am I in?

    /// Looks up the family this account belongs to (row-level security means
    /// the query only ever returns families you're a member of).
    func loadHousehold() async {
        phase = .loading
        do {
            let rows: [HouseholdRow] = try await withRetry {
                try await client.from("households")
                    .select("id,name,invite_code")
                    .order("created_at")
                    .limit(1)
                    .execute()
                    .value
            }
            if let row = rows.first { adopt(row) } else { clearHousehold() }
            phase = .loaded
            if hasHousehold { await refresh() }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Forgets everything (used on sign-out so the next account starts clean).
    func reset() {
        clearHousehold()
        errorMessage = nil
        phase = .idle
    }

    // MARK: - Create / join / leave

    func createHousehold(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let data = try await withRetry {
                try await client.rpc("create_household", params: ["p_name": trimmed]).execute().data
            }
            adopt(try Backend.decodeRow(data))
            await refresh()
        } catch {
            errorMessage = "Couldn't create the family. \(error.localizedDescription)"
        }
    }

    func joinHousehold(code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count >= 4 else {
            errorMessage = "Enter the invite code exactly as shown on the other person's phone."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let data = try await withRetry {
                try await client.rpc("join_household", params: ["p_code": trimmed]).execute().data
            }
            adopt(try Backend.decodeRow(data))
            await refresh()
        } catch {
            errorMessage = "Couldn't find a family with that code."
        }
    }

    /// Leaves this family (you stay signed in and can join or create another).
    func leaveHousehold() async {
        guard let householdId else { return }
        errorMessage = nil
        do {
            let userId = try await client.auth.session.user.id
            try await withRetry {
                try await client.from("household_users")
                    .delete()
                    .eq("household_id", value: householdId)
                    .eq("user_id", value: userId)
                    .execute()
            }
            clearHousehold()
        } catch {
            errorMessage = "Couldn't leave the family. \(error.localizedDescription)"
        }
    }

    private func adopt(_ row: HouseholdRow) {
        householdId = row.id
        householdName = row.name
        inviteCode = row.inviteCode
    }

    private func clearHousehold() {
        householdId = nil
        householdName = ""
        inviteCode = ""
        members = []
    }

    // MARK: - Members

    func refresh() async {
        guard let householdId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            members = try await withRetry {
                try await client.from("members")
                    .select()
                    .eq("household_id", value: householdId)
                    .order("created_at")
                    .execute()
                    .value
            }
        } catch {
            errorMessage = "Couldn't load your family. \(error.localizedDescription)"
        }
    }

    func addMember(
        name: String,
        conditions: [Condition],
        goals: Goals,
        isManagedByParent: Bool,
        age: Int?,
        heightCm: Double?,
        weightKg: Double?,
        sex: Sex?
    ) async {
        guard let householdId else { return }
        errorMessage = nil
        do {
            struct NewMember: Encodable {
                var householdId: UUID
                var name: String
                var conditions: [Condition]
                var goals: Goals
                var isManagedByParent: Bool
                var age: Int?
                var heightCm: Double?
                var weightKg: Double?
                var sex: Sex?
            }
            let row: Member = try await withRetry {
                try await client.from("members")
                    .insert(NewMember(
                        householdId: householdId,
                        name: name,
                        conditions: conditions,
                        goals: goals,
                        isManagedByParent: isManagedByParent,
                        age: age,
                        heightCm: heightCm,
                        weightKg: weightKg,
                        sex: sex
                    ))
                    .select()
                    .single()
                    .execute()
                    .value
            }
            members.append(row)
        } catch {
            errorMessage = "Couldn't add \(name). \(error.localizedDescription)"
        }
    }

    func updateMember(_ member: Member) async {
        errorMessage = nil
        do {
            struct Patch: Encodable {
                var name: String
                var conditions: [Condition]
                var goals: Goals
                var isManagedByParent: Bool
                var age: Int?
                var heightCm: Double?
                var weightKg: Double?
                var sex: Sex?
            }
            try await withRetry {
                try await client.from("members")
                    .update(Patch(
                        name: member.name,
                        conditions: member.conditions,
                        goals: member.goals,
                        isManagedByParent: member.isManagedByParent,
                        age: member.age,
                        heightCm: member.heightCm,
                        weightKg: member.weightKg,
                        sex: member.sex
                    ))
                    .eq("id", value: member.id)
                    .execute()
            }
            if let index = members.firstIndex(where: { $0.id == member.id }) {
                members[index] = member
            }
        } catch {
            errorMessage = "Couldn't save changes. \(error.localizedDescription)"
        }
    }

    func deleteMember(_ member: Member) async {
        errorMessage = nil
        do {
            try await withRetry {
                try await client.from("members").delete().eq("id", value: member.id).execute()
            }
            members.removeAll { $0.id == member.id }
        } catch {
            errorMessage = "Couldn't remove \(member.name). \(error.localizedDescription)"
        }
    }
}
