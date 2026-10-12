import SwiftUI

/// One shared session, saved atomically for the selected participants in a single group.
struct BuddyGroupWorkoutSheet: View {
    let member: Member
    let group: BuddyGroup
    let participantIDs: [UUID]
    let day: Date
    @Environment(BuddyStore.self) private var buddies
    @Environment(TrackingStore.self) private var tracking
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @State private var kind: WorkoutKind
    @State private var exercises: [StrengthExercise]
    @State private var minutes = 30
    @State private var intensity: WorkoutIntensity = .moderate
    @State private var note = ""
    @State private var saving = false
    @State private var error: String?
    @State private var pendingRequest: BuddyStore.GroupWorkoutRequest?

    init(member: Member, group: BuddyGroup, participantIDs: [UUID], day: Date, initialKind: WorkoutKind, prefill: [StrengthExercise]? = nil) {
        self.member = member; self.group = group; self.participantIDs = participantIDs; self.day = day
        _kind = State(initialValue: initialKind)
        _exercises = State(initialValue: prefill ?? [])
    }
    private var clean: [StrengthExercise] { StrengthMath.cleaned(exercises) }
    private var canSave: Bool { !participantIDs.isEmpty && (kind != .strength || !clean.isEmpty) }
    private var names: [String] {
        buddies.buddies(in: group).filter { participantIDs.contains($0.memberId) }.map(\.displayName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.name).readableFont(21, weight: .bold)
                        Text(day.formatted(date: .complete, time: .omitted)).readableFont(15).foregroundStyle(.secondary)
                        Text("Adding for: \(names.joined(separator: ", "))").readableFont(16, weight: .medium)
                        Text("Each selected person gets the same exercises, sets and effort. Calories are estimated separately for each person.")
                            .readableFont(13).foregroundStyle(.secondary)
                    }.card()
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Workout type", selection: $kind) {
                            ForEach(WorkoutKind.allCases.filter { [.walking, .running, .cycling, .swimming, .yoga, .strength, .hiit, .dance, .sports, .housework, .other].contains($0) }) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        Stepper("Duration: \(minutes) min", value: $minutes, in: 1...600, step: 1)
                        Picker("Effort", selection: $intensity) {
                            ForEach(WorkoutIntensity.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                        TextField("Note (optional)", text: $note, axis: .vertical)
                    }.card().disabled(pendingRequest != nil || saving)
                    if kind == .strength {
                        StrengthEditor(member: member, exercises: $exercises)
                            .disabled(pendingRequest != nil || saving)
                    }
                    if let error { Text(error).readableFont(15).foregroundStyle(.red) }
                    if pendingRequest != nil && !saving {
                        Text("Retry sends the same session so it won't create duplicate workouts. Close this form to start a different session.")
                            .readableFont(13).foregroundStyle(.secondary)
                    }
                }.padding(16)
            }
            .background(AppBackground())
            .navigationTitle("Group workout").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : pendingRequest == nil ? "Save for all" : "Retry save") { Task { await save() } }
                        .disabled(saving || (!canSave && pendingRequest == nil))
                }
            }
            .interactiveDismissDisabled(saving)
            .onChange(of: exercises) { _, _ in
                if pendingRequest == nil { minutes = min(StrengthMath.estimatedMinutes(sets: StrengthMath.totalSets(clean)), 600) }
            }
        }.tint(Theme.brand)
    }

    private func save() async {
        guard !saving, canSave || pendingRequest != nil else { return }
        saving = true; error = nil
        defer { saving = false }
        let request: BuddyStore.GroupWorkoutRequest
        if let existing = pendingRequest { request = existing }
        else {
            let cal = Calendar.current
            let time = cal.dateComponents([.hour, .minute, .second], from: Date())
            let date = cal.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? day
            request = BuddyStore.GroupWorkoutRequest(p_batch: UUID(), p_group: group.id, p_members: participantIDs,
                                                    p_done_at: min(date, Date()), p_kind: kind.rawValue, p_minutes: minutes,
                                                    p_intensity: intensity.rawValue,
                                                    p_note: note.isEmpty ? nil : AIGuardrails.sanitize(note, max: 200),
                                                    p_exercises: kind == .strength ? clean : nil)
            pendingRequest = request
        }
        do {
            let saved = try await buddies.logGroupWorkout(request)
            // Cache only the signed-in family's records; HealthSync accepts only its linked phone owner.
            tracking.receiveGroupWorkouts(saved)
            await buddies.loadActivity(day: day, myUserId: family.myUserId)
            await buddies.load(myUserId: family.myUserId)
            dismiss()
        } catch {
            self.error = "Couldn't save this group workout. \(error.localizedDescription)"
        }
    }
}
