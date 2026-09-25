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
    /// Workouts from the last four weeks: feeds the weekly goal and "copy from a previous workout".
    private(set) var recentWorkouts: [Workout] = []
    private(set) var templates: [WorkoutTemplate] = []
    private(set) var schedules: [ActivitySchedule] = []
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
            let (f, w) = try await (food, training)
            guard day == start else { return }              // the person moved to another day meanwhile
            entries = f; workouts = w
            await loadWeek(householdId)
            await loadTemplates(householdId)
            await loadSchedules(householdId)
        } catch {
            errorMessage = "Couldn't load this day. \(error.localizedDescription)"
        }
    }

    private func loadWeek(_ householdId: UUID) async {
        let start = Self.recentCutoff
        do {
            recentWorkouts = try await Backend.withRetry {
                try await client.from("workouts").select()
                    .eq("household_id", value: householdId)
                    .gte("done_at", value: Self.iso(start)).execute().value
            }
        } catch { /* the goal bar just shows what it has */ }
    }

    private func loadTemplates(_ householdId: UUID) async {
        do {
            templates = try await Backend.withRetry {
                try await client.from("workout_templates").select().eq("household_id", value: householdId).order("created_at").execute().value
            }
        } catch { /* older database without templates: the list stays empty */ }
    }

    private func loadSchedules(_ householdId: UUID) async {
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

    func templates(for member: Member) -> [WorkoutTemplate] { templates.filter { $0.memberId == member.id } }

    @discardableResult
    func saveTemplate(name: String, exercises: [StrengthExercise], for member: Member) async -> Bool {
        guard let householdId else { return false }
        let clean = StrengthMath.cleaned(exercises)
        let title = AIGuardrails.sanitize(name, max: 60)
        guard !clean.isEmpty, !title.isEmpty else { return false }
        errorMessage = nil
        if Demo.isOn { templates.append(WorkoutTemplate(householdId: householdId, memberId: member.id, name: title, exercises: clean)); return true }
        struct New: Encodable { var householdId: UUID, memberId: UUID, name: String, exercises: [StrengthExercise] }
        do {
            let row: WorkoutTemplate = try await Backend.withRetry {
                try await client.from("workout_templates").insert(New(householdId: householdId, memberId: member.id, name: title, exercises: clean))
                    .select().single().execute().value
            }
            templates.append(row)
            return true
        } catch {
            errorMessage = "Couldn't save that template. \(error.localizedDescription)"
            return false
        }
    }

    func deleteTemplate(_ t: WorkoutTemplate) async {
        templates.removeAll { $0.id == t.id }
        if Demo.isOn { return }
        do { try await Backend.withRetry { try await client.from("workout_templates").delete().eq("id", value: t.id).execute() } }
        catch { templates.append(t); errorMessage = "Couldn't delete that template. \(error.localizedDescription)" }
    }

    static var recentCutoff: Date { Calendar.current.date(byAdding: .day, value: -28, to: Calendar.current.startOfDay(for: Date())) ?? Date() }

    func recentWorkouts(for member: Member) -> [Workout] { recentWorkouts.filter { $0.memberId == member.id } }

    /// This person's strength workouts from the last four weeks with exercises, newest first.
    func recentStrength(for member: Member) -> [Workout] {
        recentWorkouts.filter { $0.memberId == member.id && $0.exercises?.isEmpty == false }.sorted { $0.doneAt > $1.doneAt }
    }

    func weeklyMinutes(for member: Member) -> Int {
        ActivityGoals.weeklyMinutes(recentWorkouts.filter { $0.memberId == member.id }, since: ActivityGoals.weekStart())
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
            if saved.doneAt >= Self.recentCutoff { recentWorkouts.append(saved) }
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
        let before = (workouts, recentWorkouts)
        apply(&workouts); apply(&recentWorkouts)
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
            (workouts, recentWorkouts) = before
            errorMessage = "Couldn't save that change. \(error.localizedDescription)"
            return false
        }
    }

    func delete(_ workout: Workout) async {
        errorMessage = nil
        workouts.removeAll { $0.id == workout.id }
        let weekBefore = recentWorkouts
        recentWorkouts.removeAll { $0.id == workout.id }
        if Demo.isOn { return }
        do {
            try await Backend.withRetry { try await client.from("workouts").delete().eq("id", value: workout.id).execute() }
        } catch {
            workouts.append(workout); recentWorkouts = weekBefore
            errorMessage = "Couldn't remove that workout. \(error.localizedDescription)"
        }
    }

    func setHousehold(_ id: UUID?) { householdId = id }

    func reset() { entries = []; workouts = []; recentWorkouts = []; templates = []; schedules = []; householdId = nil; errorMessage = nil; day = Calendar.current.startOfDay(for: Date()) }

    private func clamp(_ v: Double, _ hi: Double) -> Double { min(max(v, 0), hi) }
}
