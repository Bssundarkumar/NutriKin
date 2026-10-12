import SwiftUI

/// Logging a workout, right on the Activity screen instead of behind another sheet. Tap "Add" to expand it in
/// place; save collapses it back with a short cheer. Strength still opens its own screen, because it genuinely
/// needs more room (exercises, sets, reps and weight).
struct InlineWorkoutLogger: View {
    let member: Member
    var onClose: () -> Void = {}
    @Environment(TrackingStore.self) private var tracking
    @Environment(FamilyStore.self) private var family
    @Environment(AIConnection.self) private var ai

    @State private var kind: WorkoutKind
    @State private var minutes = 30
    @State private var intensity: WorkoutIntensity = .moderate
    @State private var override: Int?
    @State private var note = ""
    @State private var showStrength = false
    @State private var isSaving = false
    @State private var message: String?
    @State private var saved: Workout?
    @State private var cheer = ""
    @State private var cheerIsAI = false
    @State private var idea: String?
    @State private var ideaLoading = false

    init(member: Member, onClose: @escaping () -> Void = {}) {
        self.member = member; self.onClose = onClose
        _kind = State(initialValue: TodayLayout.isChild(member) ? .play : .walking)
    }

    private var estimate: Int { WorkoutEstimator.calories(kind: kind, intensity: intensity, minutes: minutes, weightKg: member.weightKg) }
    private var burned: Int { override ?? estimate }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let saved { cheerCard(saved) } else { form }
        }
        .card()
        .onAppear { if Demo.strengthSample != nil { kind = .strength; showStrength = true } }
        .fullScreenCover(isPresented: $showStrength) {
            StrengthSessionView(member: member, editing: nil) { w in showStrength = false; showCheer(for: w) }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(TodayLayout.isChild(member) ? "Log play" : "Log a workout").readableFont(19, weight: .semibold, relativeTo: .headline)
                Spacer()
                Button("Cancel", action: onClose).readableFont(17, weight: .regular, relativeTo: .subheadline).foregroundStyle(.secondary)
            }

            if ai.textProvider != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let idea { Text(idea).readableFont(17, weight: .regular, relativeTo: .subheadline) }
                    Button {
                        ideaLoading = true
                        Task {
                            idea = await AIQuick.text(rules: DayCoach.workoutIdeaRules,
                                                      user: DayCoach.workoutPrompt(member: member, weekMinutes: tracking.weeklyMinutes(for: member), steps: nil),
                                                      members: family.members, ai: ai, forMember: member)
                                ?? "Couldn't get an idea right now. A walk you enjoy is always a good start."
                            ideaLoading = false
                        }
                    } label: {
                        Label(ideaLoading ? "Thinking\u{2026}" : (idea == nil ? "Not sure what to do? Get an idea" : "Another idea"), systemImage: "sparkles")
                            .readableFont(16, weight: .semibold, relativeTo: .footnote)
                    }
                    .disabled(ideaLoading)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 10) {
                ForEach(WorkoutKind.choices(for: member)) { k in
                    Button { kind = k; override = nil; if k == .strength { showStrength = true } } label: {
                        VStack(spacing: 5) {
                            Image(systemName: k.symbol).readableFont(22, weight: .regular, relativeTo: .title3).frame(minHeight: 24)
                            Text(k.title).readableFont(15, weight: .regular, relativeTo: .caption2).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(kind == k ? Color.orange.opacity(0.22) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(kind == k ? Color.orange : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(kind == k ? .isSelected : [])
                }
            }

            if kind == .strength {
                Button { showStrength = true } label: { Label("Open the strength log", systemImage: "dumbbell.fill") }
                Text("Choose exercises by muscle group, use a template or copy a past session, and enter sets, reps and weight.")
                    .readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Stepper("\(minutes) minutes", value: $minutes, in: 5...300, step: 5).onChange(of: minutes) { _, _ in override = nil }
                    HStack { ForEach([15, 30, 45, 60], id: \.self) { m in
                        Button("\(m)") { minutes = m; override = nil }.buttonStyle(.bordered).buttonBorderShape(.capsule).tint(minutes == m ? .orange : .gray)
                    } }
                    Picker("Effort", selection: $intensity) { ForEach(WorkoutIntensity.allCases) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented).onChange(of: intensity) { _, _ in override = nil }
                }
                if !TodayLayout.isChild(member) {
                    VStack(alignment: .leading, spacing: 6) {
                        Stepper("\(burned) kcal burned", value: Binding(get: { burned }, set: { override = $0 }), in: 0...3000, step: 10)
                        Text(member.weightKg == nil
                             ? "An estimate for a 70 kg adult. Add \(member.name)'s weight in the Family tab for a better one."
                             : "An estimate for \(Int(member.weightKg ?? 0)) kg. Change it if your watch says otherwise.")
                            .readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary)
                    }
                }
                TextField("Note (optional), e.g. Morning walk in the park", text: $note)
                    .textFieldStyle(.roundedBorder)
                if let message { Text(message).readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.red) }
                Button(isSaving ? "Saving\u{2026}" : "Log") { save() }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                    .disabled(isSaving)
            }
        }
    }

    private func save() {
        isSaving = true
        let workout = Workout(householdId: family.householdId, memberId: member.id, doneAt: tracking.timestampForNewItem,
                              kind: kind.rawValue, minutes: minutes, intensity: intensity, caloriesBurned: burned,
                              note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note, exercises: nil)
        Task {
            if await tracking.add(workout) { UINotificationFeedbackGenerator().notificationOccurred(.success); showCheer(for: workout) }
            else { message = tracking.errorMessage; isSaving = false }
        }
    }

    private func showCheer(for workout: Workout) {
        cheer = WorkoutCoach.fallback(workout: workout, member: member)
        withAnimation(.spring(duration: 0.4)) { saved = workout }
        let minutesToday = tracking.workouts(for: member).reduce(0) { $0 + $1.minutes }
        Task {
            if let text = await WorkoutCoach.aiCheer(workout: workout, member: member, minutesToday: minutesToday, weekMinutes: tracking.weeklyMinutes(for: member), ai: ai, family: family.members) {
                withAnimation(.smooth) { cheer = text; cheerIsAI = true }
            }
        }
    }

    private func cheerCard(_ workout: Workout) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "party.popper.fill").font(.system(size: 32)).foregroundStyle(.orange).popIn()
            Text("Workout saved").readableFont(19, weight: .semibold, relativeTo: .headline)
            Text(cheer).readableFont(17, weight: .regular, relativeTo: .subheadline).multilineTextAlignment(.center).contentTransition(.opacity)
            if cheerIsAI { Label("Written by AI", systemImage: "sparkles").readableFont(15, weight: .regular, relativeTo: .caption2).foregroundStyle(.secondary) }
            Button("Done", action: onClose).buttonStyle(.borderedProminent).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }
}
