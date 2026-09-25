import Foundation
import Supabase

/// The weekly activity schedule (see `backend/migration_016_activity_schedules.sql`).
extension TrackingStore {
    func loadSchedules(_ householdId: UUID) async {
        do {
            schedules = try await Backend.withRetry {
                try await client.from("activity_schedules").select().eq("household_id", value: householdId).order("created_at").execute().value
            }
        } catch { /* older database without schedules: the list stays empty */ }
    }

    func schedules(for member: Member) -> [ActivitySchedule] { schedules.filter { $0.memberId == member.id } }

    @discardableResult
    func save(_ schedule: ActivitySchedule) async -> Bool {
        guard let householdId = householdId ?? schedule.householdId else { return false }
        var s = schedule
        s.householdId = householdId
        s.minutes = min(max(s.minutes, 5), 600)
        s.daysOfWeek = Array(Set(s.daysOfWeek.filter { (1...7).contains($0) })).sorted()
        s.label = s.label.map { AIGuardrails.sanitize($0, max: 60) }.flatMap { $0.isEmpty ? nil : $0 }
        guard !s.daysOfWeek.isEmpty else { errorMessage = "Pick at least one day."; return false }
        errorMessage = nil
        if Demo.isOn { if let i = schedules.firstIndex(where: { $0.id == s.id }) { schedules[i] = s } else { schedules.append(s) }; return true }
        struct Row: Encodable {
            var id: UUID, householdId: UUID, memberId: UUID, kind: String, label: String?, minutes: Int, time: String
            var daysOfWeek: [Int], remind: Bool, active: Bool
            func encode(to encoder: Encoder) throws {
                enum K: String, CodingKey { case id, householdId, memberId, kind, label, minutes, time, daysOfWeek, remind, active }
                var c = encoder.container(keyedBy: K.self)
                try c.encode(id, forKey: .id); try c.encode(householdId, forKey: .householdId); try c.encode(memberId, forKey: .memberId)
                try c.encode(kind, forKey: .kind); try c.encode(label, forKey: .label); try c.encode(minutes, forKey: .minutes)
                try c.encode(time, forKey: .time); try c.encode(daysOfWeek, forKey: .daysOfWeek)
                try c.encode(remind, forKey: .remind); try c.encode(active, forKey: .active)
            }
        }
        do {
            let saved: ActivitySchedule = try await Backend.withRetry {
                try await client.from("activity_schedules")
                    .upsert(Row(id: s.id, householdId: householdId, memberId: s.memberId, kind: s.kind, label: s.label, minutes: s.minutes,
                                time: s.time, daysOfWeek: s.daysOfWeek, remind: s.remind, active: s.active))
                    .select().single().execute().value
            }
            if let i = schedules.firstIndex(where: { $0.id == saved.id }) { schedules[i] = saved } else { schedules.append(saved) }
            return true
        } catch {
            errorMessage = "Couldn't save that schedule. \(error.localizedDescription)"
            return false
        }
    }

    func delete(_ schedule: ActivitySchedule) async {
        schedules.removeAll { $0.id == schedule.id }
        if Demo.isOn { return }
        do { try await Backend.withRetry { try await client.from("activity_schedules").delete().eq("id", value: schedule.id).execute() } }
        catch { schedules.append(schedule); errorMessage = "Couldn't remove that. \(error.localizedDescription)" }
    }
}
