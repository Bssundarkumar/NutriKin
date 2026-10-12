import SwiftUI

/// The strength panel: everything about one strength session on its own screen. Start from a template or a past
/// session, build it exercise by exercise (by muscle group), edit sets, reps and weight, and save.
struct StrengthSessionView: View {
    let member: Member
    var editing: Workout? = nil
    /// Exercises to start from, for example copied from a buddy's workout.
    var prefill: [StrengthExercise]? = nil
    /// Called after a new session is saved, so the caller can show the cheer.
    var onSaved: ((Workout) -> Void)? = nil
    @Environment(TrackingStore.self) private var tracking
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @AppStorage("strengthUsesPounds") private var pounds = false

    @State private var exercises: [StrengthExercise] = []
    @State private var intensity: WorkoutIntensity = .moderate
    @State private var note = ""
    @State private var prefilled = false
    @State private var isSaving = false
    @State private var message: String?
    @State private var draftStarted = false

    private var draftURL: URL? {
        guard !Demo.isOn, let user = family.myUserId else { return nil }
        return StrengthDraftStore.url(user: user, member: member.id, workout: editing?.id)
    }

    private var clean: [StrengthExercise] { StrengthMath.cleaned(exercises) }
    private var sets: Int { StrengthMath.totalSets(clean) }
    private var minutes: Int { StrengthMath.estimatedMinutes(sets: sets) }
    private var kcal: Int { WorkoutEstimator.calories(kind: .strength, intensity: intensity, minutes: minutes, weightKg: member.weightKg) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    StrengthEditor(member: member, exercises: $exercises)
                    Text("Save set keeps a draft on this iPhone. Save above logs the whole workout. You can edit or delete sets later.")
                        .readableFont(15).foregroundStyle(.secondary)
                    sessionSummary
                    if let message { Text(message).readableFont(16, weight: .regular, relativeTo: .footnote).foregroundStyle(.red) }
                }.padding(.horizontal, 12).padding(.vertical, 8)
            }
            .background(AppBackground())
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "arrow.left").readableFont(20, weight: .medium, design: .default)
                            .foregroundStyle(StrengthStyle.green).frame(width: 44, height: 44)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    }.accessibilityLabel("Cancel strength workout")
                    Spacer()
                    Text(editing == nil ? "Strength" : "Edit strength").readableFont(24, weight: .bold, design: .default)
                    Spacer()
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .readableFont(16, weight: .semibold, design: .default).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(StrengthStyle.green.gradient, in: Capsule())
                        .disabled(isSaving || sets == 0).opacity(sets == 0 ? 0.5 : 1)
                }.padding(.horizontal, 12).padding(.vertical, 8)
                    .background {
                        LinearGradient(colors: [.green.opacity(0.10), Color(.systemGroupedBackground)], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .top)
                    }
            }
            .toolbar(.hidden, for: .navigationBar)
            .tint(StrengthStyle.green)
            .onAppear {
                guard !prefilled else { return }
                prefilled = true
                if let url = draftURL, let draft = StrengthDraftStore.load(from: url) {
                    exercises = draft.exercises; intensity = draft.intensity; note = draft.note; draftStarted = true
                }
                else if let e = editing { exercises = e.exercises ?? []; intensity = e.intensity; note = e.note ?? "" }
                else if let prefill { exercises = StrengthMath.forReuse(prefill) }
                else if let sample = Demo.strengthSample { exercises = sample }
            }
            .onChange(of: exercises) { _, _ in keepDraft() }
            .onChange(of: intensity) { _, _ in keepDraft() }
            .onChange(of: note) { _, _ in keepDraft() }
        }
    }

    private func keepDraft() {
        guard prefilled, let url = draftURL else { return }
        if exercises.contains(where: { $0.sets.contains(where: { $0.isSaved == true }) }) { draftStarted = true }
        guard draftStarted else { return }
        do {
            try StrengthDraftStore.save(.init(exercises: exercises, intensity: intensity, note: note), to: url)
        } catch { message = "Couldn’t keep the draft on this iPhone. Save the workout before leaving." }
    }

    private func clearDraft() { if let url = draftURL { StrengthDraftStore.remove(at: url) } }

    private var sessionSummary: some View {
        VStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 10) {
                Text("This session").readableFont(17, weight: .bold, design: .default)
                HStack(spacing: 0) {
                    ForEach(WorkoutIntensity.allCases) { effort in
                        Button { intensity = effort } label: {
                            Text(effort.title).readableFont(15, weight: .medium, design: .default)
                                .foregroundStyle(intensity == effort ? .white : Color.secondary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(intensity == effort ? StrengthStyle.green : .clear, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }.background(Color(.secondarySystemFill), in: Capsule())
            }
            ReadableStack(spacing: 10) {
                estimate("Estimated time", sets == 0 ? "—" : "\(minutes) min", symbol: "clock", tint: StrengthStyle.green)
                if !TodayLayout.isChild(member) {
                    estimate("Estimated calories", sets == 0 ? "—" : "\(kcal) kcal", symbol: "flame.fill", tint: .orange)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "note.text").readableFont(22, weight: .regular, design: .default)
                TextField("Add a note (optional), e.g. Morning strength workout", text: $note)
                    .readableFont(15, weight: .regular, design: .default)
            }.strengthSurface(padding: 10)
        }.strengthSurface(tint: .green)
        .accessibilityHint("Time includes rest between sets. Calories are estimated from weight and effort.")
    }

    private func estimate(_ title: String, _ value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).readableFont(25, weight: .regular, design: .default).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).readableFont(15, weight: .regular, design: .default).foregroundStyle(.secondary)
                Text(value).readableFont(19, weight: .bold, design: .default)
            }
            Spacer(minLength: 0)
        }.strengthSurface(padding: 12)
    }

    private func save() {
        guard sets > 0 else { return }
        isSaving = true
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        if var changed = editing {
            changed.kind = WorkoutKind.strength.rawValue; changed.minutes = minutes; changed.intensity = intensity
            changed.caloriesBurned = kcal; changed.note = trimmed.isEmpty ? nil : trimmed; changed.exercises = clean
            Task {
                if await tracking.update(changed) { clearDraft(); UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss() }
                else { message = tracking.errorMessage; isSaving = false }
            }
            return
        }
        let workout = Workout(householdId: family.householdId, memberId: member.id, doneAt: tracking.timestampForNewItem,
                              kind: WorkoutKind.strength.rawValue, minutes: minutes, intensity: intensity, caloriesBurned: kcal,
                              note: trimmed.isEmpty ? nil : trimmed, exercises: clean)
        Task {
            if await tracking.add(workout) { clearDraft(); UINotificationFeedbackGenerator().notificationOccurred(.success); onSaved?(workout); dismiss() }
            else { message = tracking.errorMessage; isSaving = false }
        }
    }
}

/// Shared surfaces for the strength session and its exercise cards.
enum StrengthStyle {
    static let green = Theme.brand
}

extension View {
    func strengthSurface(padding: CGFloat = 16, tint: Color? = nil) -> some View {
        card(padding: padding, radius: 18, tint: tint)
    }

    func setField() -> some View {
        self.readableFont(15, weight: .regular, design: .default)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 6))
    }
}
