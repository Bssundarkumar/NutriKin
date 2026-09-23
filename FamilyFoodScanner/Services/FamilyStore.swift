import Foundation
import Observation
import Supabase

/// The family's shared data, backed by Supabase (see `backend/schema.sql`).
///
/// Trust model: a "household" is identified by a UUID. Anyone who has that
/// UUID (the invite code, shown in Family > Invite code) can read and write
/// its members — the same model as a shared link, not per-person login.
/// Good enough for a family app; move to Supabase Auth if you want real
/// per-person accounts later.
@MainActor
@Observable
final class FamilyStore {
    private(set) var members: [Member] = []
    private(set) var householdId: UUID?
    private(set) var householdName: String = ""
    var isLoading = false
    var errorMessage: String?

    private var client: SupabaseClient { Backend.client }
    private let householdDefaultsKey = "nutrikin.householdId"
    private let householdNameDefaultsKey = "nutrikin.householdName"

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: householdDefaultsKey), let id = UUID(uuidString: saved) {
            householdId = id
            householdName = defaults.string(forKey: householdNameDefaultsKey) ?? ""
        }
    }

    var hasHousehold: Bool { householdId != nil }

    @discardableResult
    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        try await Backend.withRetry(operation)
    }

    // MARK: - Household lifecycle

    func createHousehold(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            struct NewHousehold: Encodable { var name: String }
            struct HouseholdRow: Decodable { var id: UUID; var name: String }

            let row: HouseholdRow = try await withRetry {
                try await client.from("households")
                    .insert(NewHousehold(name: trimmed))
                    .select()
                    .single()
                    .execute()
                    .value
            }
            setHousehold(id: row.id, name: row.name)
            await refresh()
        } catch {
            errorMessage = "Couldn't create the family. \(error.localizedDescription)"
        }
    }

    func joinHousehold(code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = UUID(uuidString: trimmed) else {
            errorMessage = "That code doesn't look right. Copy the invite code exactly from another member's phone."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            struct HouseholdRow: Decodable { var id: UUID; var name: String }
            let row: HouseholdRow = try await withRetry {
                try await client.from("households")
                    .select()
                    .eq("id", value: id)
                    .single()
                    .execute()
                    .value
            }
            setHousehold(id: row.id, name: row.name)
            await refresh()
        } catch {
            errorMessage = "Couldn't find a family with that code."
        }
    }

    func leaveHousehold() {
        householdId = nil
        householdName = ""
        members = []
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: householdDefaultsKey)
        defaults.removeObject(forKey: householdNameDefaultsKey)
    }

    private func setHousehold(id: UUID, name: String) {
        householdId = id
        householdName = name
        let defaults = UserDefaults.standard
        defaults.set(id.uuidString, forKey: householdDefaultsKey)
        defaults.set(name, forKey: householdNameDefaultsKey)
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
