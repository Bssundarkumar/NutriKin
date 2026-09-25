import Foundation
import Observation
import Supabase

/// A person's height and weight history (see `backend/migration_015_body_measurements.sql`).
@MainActor
@Observable
final class GrowthStore {
    private(set) var items: [BodyMeasurement] = []
    var isLoading = false
    var errorMessage: String?
    private var client: SupabaseClient { Backend.client }

    func load(for member: Member) async {
        if Demo.isOn { items = Demo.measurements(for: member); return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await Backend.withRetry {
                try await client.from("body_measurements").select().eq("member_id", value: member.id)
                    .order("measured_on").execute().value
            }
        } catch {
            errorMessage = "Couldn't load the history. \(error.localizedDescription)"
        }
    }

    /// One reading a day: adding on a day that already has one replaces it.
    @discardableResult
    func add(member: Member, householdId: UUID?, on date: Date, heightCm: Double?, weightKg: Double?) async -> BodyMeasurement? {
        guard GrowthMath.isValid(heightCm: heightCm, weightKg: weightKg) else {
            errorMessage = "Check the numbers: height is in cm and weight in kg."
            return nil
        }
        errorMessage = nil
        let day = BodyMeasurement.day(date)
        if Demo.isOn {
            let row = BodyMeasurement(memberId: member.id, measuredOn: day, heightCm: heightCm, weightKg: weightKg)
            items.removeAll { $0.measuredOn == day }; items.append(row); return row
        }
        guard let householdId else { return nil }
        struct New: Encodable { var householdId: UUID, memberId: UUID, measuredOn: String, heightCm: Double?, weightKg: Double? }
        do {
            let row: BodyMeasurement = try await Backend.withRetry {
                try await client.from("body_measurements")
                    .upsert(New(householdId: householdId, memberId: member.id, measuredOn: day, heightCm: heightCm, weightKg: weightKg),
                            onConflict: "member_id,measured_on")
                    .select().single().execute().value
            }
            items.removeAll { $0.measuredOn == day }; items.append(row)
            return row
        } catch {
            errorMessage = "Couldn't save that. \(error.localizedDescription)"
            return nil
        }
    }

    func delete(_ m: BodyMeasurement) async {
        items.removeAll { $0.id == m.id }
        if Demo.isOn { return }
        do { try await Backend.withRetry { try await client.from("body_measurements").delete().eq("id", value: m.id).execute() } }
        catch { items.append(m); errorMessage = "Couldn't remove that. \(error.localizedDescription)" }
    }
}
