import Foundation
import Supabase

/// Workouts, the recent-weeks window, and strength templates.
extension TrackingStore {
    func loadWeek(_ householdId: UUID) async {
        let start = Self.recentCutoff
        do {
            recentWorkouts = try await Backend.withRetry {
                try await client.from("workouts").select()
                    .eq("household_id", value: householdId)
                    .gte("done_at", value: Self.iso(start)).execute().value
            }
        } catch { /* the goal bar just shows what it has */ }
    }

    func loadTemplates(_ householdId: UUID) async {
        do {
            templates = try await Backend.withRetry {
                try await client.from("workout_templates").select().eq("household_id", value: householdId).order("created_at").execute().value
            }
        } catch { /* older database without templates: the list stays empty */ }
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

    /// Replaces a template's exercises with the current ones (same name, same id).
    @discardableResult
    func updateTemplate(_ t: WorkoutTemplate, exercises: [StrengthExercise]) async -> Bool {
        let clean = StrengthMath.cleaned(exercises)
        guard !clean.isEmpty else { return false }
        errorMessage = nil
        let before = templates
        if let i = templates.firstIndex(where: { $0.id == t.id }) { templates[i].exercises = clean }
        if Demo.isOn { return true }
        struct Patch: Encodable { var exercises: [StrengthExercise] }
        do {
            try await Backend.withRetry { try await client.from("workout_templates").update(Patch(exercises: clean)).eq("id", value: t.id).execute() }
            return true
        } catch {
            templates = before
            errorMessage = "Couldn't update that template. \(error.localizedDescription)"
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

    // MARK: Workouts

    struct NewWorkout: Encodable {
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
}
