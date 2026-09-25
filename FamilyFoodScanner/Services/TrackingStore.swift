import Foundation
import Observation
import Supabase

/// Food eaten and workouts done, for one day at a time, shared by the family through Supabase
/// (see `backend/migration_007_tracking_workouts_groceries.sql`).
@MainActor
@Observable
final class TrackingStore {
    private(set) var entries: [FoodEntry] = []
    private(set) var workouts: [Workout] = []
    /// Workouts since Monday, for the weekly workout goal (whatever day is being viewed).
    private(set) var weekWorkouts: [Workout] = []
    /// The day being shown (start of that day, local time).
    private(set) var day = Calendar.current.startOfDay(for: Date())
    var isLoading = false
    var errorMessage: String?

    private var householdId: UUID?
    private var client: SupabaseClient { Backend.client }

    var isToday: Bool { Calendar.current.isDateInToday(day) }

    func entries(for member: Member) -> [FoodEntry] { entries.filter { $0.memberId == member.id }.sorted { $0.eatenAt < $1.eatenAt } }
    func workouts(for member: Member) -> [Workout] { workouts.filter { $0.memberId == member.id }.sorted { $0.doneAt < $1.doneAt } }

    func budget(for member: Member, healthActiveKcal: Double? = nil) -> DayBudget {
        DayBudget(member: member, entries: entries(for: member), workouts: workouts(for: member), healthActiveKcal: healthActiveKcal)
    }

    // MARK: Loading

    func load(householdId: UUID?, day newDay: Date? = nil) async {
        if let newDay { day = Calendar.current.startOfDay(for: newDay) }
        if Demo.isOn { entries = Demo.foodEntries; workouts = Demo.workouts; weekWorkouts = Demo.workouts; return }
        self.householdId = householdId
        guard let householdId else { entries = []; workouts = []; return }
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
            let (f, w) = try await (food, training)
            guard day == start else { return }              // the person moved to another day meanwhile
            entries = f; workouts = w
            await loadWeek(householdId)
        } catch {
            errorMessage = "Couldn't load this day. \(error.localizedDescription)"
        }
    }

    private func loadWeek(_ householdId: UUID) async {
        let start = ActivityGoals.weekStart()
        do {
            weekWorkouts = try await Backend.withRetry {
                try await client.from("workouts").select()
                    .eq("household_id", value: householdId)
                    .gte("done_at", value: Self.iso(start)).execute().value
            }
        } catch { /* the goal bar just shows what it has */ }
    }

    func weeklyMinutes(for member: Member) -> Int {
        ActivityGoals.weeklyMinutes(weekWorkouts.filter { $0.memberId == member.id }, since: ActivityGoals.weekStart())
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

    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    // MARK: Food

    private struct NewFood: Encodable {
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

    // MARK: Workouts

    private struct NewWorkout: Encodable {
        var householdId: UUID, memberId: UUID, doneAt: Date, kind: String, minutes: Int
        var intensity: String, caloriesBurned: Int, note: String?
        /// Only sent for imported workouts, so typing one in never depends on the Health columns existing.
        var source: String?, externalId: String?
        /// Only sent for strength workouts, for the same reason.
        var exercises: [StrengthExercise]?
    }

    @discardableResult
    func add(_ workout: Workout) async -> Bool {
        guard let householdId = householdId ?? workout.householdId else { return false }
        errorMessage = nil
        if Demo.isOn { workouts.append(workout); return true }
        let note = workout.note.map { AIGuardrails.sanitize($0, max: 200) }
        let payload = NewWorkout(householdId: householdId, memberId: workout.memberId, doneAt: workout.doneAt, kind: workout.kind,
                                 minutes: min(max(workout.minutes, 1), 600), intensity: workout.intensity.rawValue,
                                 caloriesBurned: min(max(workout.caloriesBurned, 0), 5000), note: (note?.isEmpty == false) ? note : nil,
                                 source: workout.externalId == nil ? nil : workout.source, externalId: workout.externalId,
                                 exercises: workout.exercises.map(StrengthMath.cleaned).flatMap { $0.isEmpty ? nil : $0 })
        do {
            let saved: Workout = try await Backend.withRetry {
                try await client.from("workouts").insert(payload).select().single().execute().value
            }
            if Calendar.current.isDate(saved.doneAt, inSameDayAs: day) { workouts.append(saved) }
            if saved.doneAt >= ActivityGoals.weekStart() { weekWorkouts.append(saved) }
            return true
        } catch {
            errorMessage = "Couldn't save that workout. \(error.localizedDescription)"
            return false
        }
    }

    /// Saves changes to a logged workout (kind, time spent, effort, calories, note and strength exercises).
    @discardableResult
    func update(_ workout: Workout) async -> Bool {
        errorMessage = nil
        let cleaned = workout.exercises.map(StrengthMath.cleaned)
        var fixed = workout
        fixed.minutes = min(max(workout.minutes, 1), 600)
        fixed.caloriesBurned = min(max(workout.caloriesBurned, 0), 5000)
        fixed.note = workout.note.map { AIGuardrails.sanitize($0, max: 200) }.flatMap { $0.isEmpty ? nil : $0 }
        fixed.exercises = (cleaned?.isEmpty == false) ? cleaned : nil
        func apply(_ list: inout [Workout]) { if let i = list.firstIndex(where: { $0.id == fixed.id }) { list[i] = fixed } }
        let before = (workouts, weekWorkouts)
        apply(&workouts); apply(&weekWorkouts)
        if Demo.isOn { return true }
        struct Patch: Encodable {
            var minutes: Int, intensity: String, caloriesBurned: Int, note: String?
            var exercises: [StrengthExercise]?
            func encode(to encoder: Encoder) throws {
                enum K: String, CodingKey { case minutes, intensity, caloriesBurned, note, exercises }
                var c = encoder.container(keyedBy: K.self)
                try c.encode(minutes, forKey: .minutes); try c.encode(intensity, forKey: .intensity)
                try c.encode(caloriesBurned, forKey: .caloriesBurned)
                try c.encode(note, forKey: .note); try c.encode(exercises, forKey: .exercises)
            }
        }
        do {
            try await Backend.withRetry {
                try await client.from("workouts")
                    .update(Patch(minutes: fixed.minutes, intensity: fixed.intensity.rawValue, caloriesBurned: fixed.caloriesBurned,
                                  note: fixed.note, exercises: fixed.exercises))
                    .eq("id", value: fixed.id).execute()
            }
            return true
        } catch {
            (workouts, weekWorkouts) = before
            errorMessage = "Couldn't save that change. \(error.localizedDescription)"
            return false
        }
    }

    func delete(_ workout: Workout) async {
        errorMessage = nil
        workouts.removeAll { $0.id == workout.id }
        let weekBefore = weekWorkouts
        weekWorkouts.removeAll { $0.id == workout.id }
        if Demo.isOn { return }
        do {
            try await Backend.withRetry { try await client.from("workouts").delete().eq("id", value: workout.id).execute() }
        } catch {
            workouts.append(workout); weekWorkouts = weekBefore
            errorMessage = "Couldn't remove that workout. \(error.localizedDescription)"
        }
    }

    func setHousehold(_ id: UUID?) { householdId = id }

    func reset() { entries = []; workouts = []; householdId = nil; errorMessage = nil; day = Calendar.current.startOfDay(for: Date()) }

    private func clamp(_ v: Double, _ hi: Double) -> Double { min(max(v, 0), hi) }
}
