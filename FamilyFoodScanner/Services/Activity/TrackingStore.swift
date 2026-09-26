import Foundation
import Observation
import Supabase

/// Food eaten and workouts done, for one day at a time, shared by the family through Supabase
/// (see `backend/migration_007_tracking_workouts_groceries.sql`).
@MainActor
@Observable
final class TrackingStore {
    private(set) var entries: [FoodEntry] = []
    internal(set) var workouts: [Workout] = []
    /// Workouts from the last four weeks: feeds the weekly goal and "copy from a previous workout".
    internal(set) var recentWorkouts: [Workout] = []
    internal(set) var templates: [WorkoutTemplate] = []
    internal(set) var schedules: [ActivitySchedule] = []
    /// The day being shown (start of that day, local time).
    private(set) var day = Calendar.current.startOfDay(for: Date())
    var isLoading = false
    var errorMessage: String?

    var householdId: UUID?
    var client: SupabaseClient { Backend.client }

    var isToday: Bool { Calendar.current.isDateInToday(day) }

    func entries(for member: Member) -> [FoodEntry] { entries.filter { $0.memberId == member.id }.sorted { $0.eatenAt < $1.eatenAt } }
    func workouts(for member: Member) -> [Workout] { workouts.filter { $0.memberId == member.id }.sorted { $0.doneAt < $1.doneAt } }

    func budget(for member: Member, healthActiveKcal: Double? = nil) -> DayBudget {
        DayBudget(member: member, entries: entries(for: member), workouts: workouts(for: member), healthActiveKcal: healthActiveKcal)
    }

    // MARK: Loading

    func load(householdId: UUID?, day newDay: Date? = nil) async {
        if let newDay { day = Calendar.current.startOfDay(for: newDay) }
        if Demo.isOn { entries = Demo.foodEntries; workouts = Demo.workouts; recentWorkouts = Demo.workouts; return }
        self.householdId = householdId
        guard let householdId else { entries = []; workouts = []; schedules = []; templates = []; return }
        let start = day
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let food: [FoodEntry] = Backend.withRetry {
                try await client.from("food_log").select()
                    .eq("household_id", value: householdId)
                    .gte("eaten_at", value: Self.iso(start)).lt("eaten_at", value: Self.iso(end))
                    .order("eaten_at").execute().value
            }
            async let training: [Workout] = Backend.withRetry {
                try await client.from("workouts").select()
                    .eq("household_id", value: householdId)
                    .gte("done_at", value: Self.iso(start)).lt("done_at", value: Self.iso(end))
                    .order("done_at").execute().value
            }
            // The week, templates and schedule don't depend on the day being shown, so they load alongside the day
            // (in parallel) and only on a first load or a pull to refresh, not every time the day changes.
            let reloadExtras = newDay == nil
            async let week: Void = reloadExtras ? loadWeek(householdId) : ()
            async let tmpl: Void = reloadExtras ? loadTemplates(householdId) : ()
            async let sched: Void = reloadExtras ? loadSchedules(householdId) : ()
            let (f, w) = try await (food, training)
            _ = await (week, tmpl, sched)
            guard day == start else { return }              // the person moved to another day meanwhile
            entries = f; workouts = w
        } catch {
            errorMessage = "Couldn't load this day. \(error.localizedDescription)"
        }
    }

    func moveDay(by days: Int) async {
        guard let target = Calendar.current.date(byAdding: .day, value: days, to: day), target <= Date() else { return }
        await load(householdId: householdId, day: target)
    }

    func goToToday() async { await load(householdId: householdId, day: Date()) }

    /// When something is logged: now if viewing today, otherwise midday of the day being viewed.
    var timestampForNewItem: Date {
        isToday ? Date() : (Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day)
    }

    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    // MARK: Food

    struct NewFood: Encodable {
        var householdId: UUID, memberId: UUID, eatenAt: Date, label: String, barcode: String?, source: String
        var calories: Double, sugarG: Double, carbsG: Double, sodiumMg: Double, satFatG: Double, proteinG: Double
        var fiberG: Double, fatG: Double
    }

    @discardableResult
    func add(_ entry: FoodEntry) async -> Bool {
        guard let householdId = householdId ?? entry.householdId else { return false }
        errorMessage = nil
        if Demo.isOn { entries.append(entry); return true }
        let payload = NewFood(householdId: householdId, memberId: entry.memberId, eatenAt: entry.eatenAt,
                              label: AIGuardrails.sanitize(entry.label, max: 120), barcode: entry.barcode, source: entry.source.rawValue,
                              calories: clamp(entry.calories, 5000), sugarG: clamp(entry.sugarG, 1000), carbsG: clamp(entry.carbsG, 1000),
                              sodiumMg: clamp(entry.sodiumMg, 50000), satFatG: clamp(entry.satFatG, 1000), proteinG: clamp(entry.proteinG, 1000),
                              fiberG: clamp(entry.fiberG, 1000), fatG: clamp(entry.fatG, 1000))
        do {
            let saved: FoodEntry = try await Backend.withRetry {
                try await client.from("food_log").insert(payload).select().single().execute().value
            }
            if Calendar.current.isDate(saved.eatenAt, inSameDayAs: day) { entries.append(saved) }
            return true
        } catch {
            errorMessage = "Couldn't save that. \(error.localizedDescription)"
            return false
        }
    }

    func delete(_ entry: FoodEntry) async {
        errorMessage = nil
        entries.removeAll { $0.id == entry.id }
        if Demo.isOn { return }
        do {
            try await Backend.withRetry { try await client.from("food_log").delete().eq("id", value: entry.id).execute() }
        } catch {
            entries.append(entry)
            errorMessage = "Couldn't remove that. \(error.localizedDescription)"
        }
    }

    func setHousehold(_ id: UUID?) { householdId = id }

    func reset() { entries = []; workouts = []; recentWorkouts = []; templates = []; schedules = []; householdId = nil; errorMessage = nil; day = Calendar.current.startOfDay(for: Date()) }

    func clamp(_ v: Double, _ hi: Double) -> Double { min(max(v, 0), hi) }
}
