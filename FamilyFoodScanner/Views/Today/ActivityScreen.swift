import SwiftUI

/// Everything about movement for one person, on its own screen so Today can stay about food:
/// Health steps and workouts, today's scheduled activities, goals, and the workouts logged for the day.
struct ActivityScreen: View {
    let member: Member
    @Environment(FamilyStore.self) private var family
    @Environment(TrackingStore.self) private var tracking
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @AppStorage("healthMemberID") private var healthMemberID = ""
    @State private var showWorkout = Demo.opensLogWorkout
    @State private var editingWorkout: Workout?
    @State private var viewingWorkout: Workout?
    @State private var showSchedule = false
    @State private var showBuddies = false
    @State private var showPlan = Demo.opensPlan

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    let showsHealth = HealthActivityCard.isVisible(for: member, linkedID: healthMemberID, health: health)
                    let list = tracking.workouts(for: member)
                    if TodayLayout.isChild(member) { KidActivityCard(member: member, healthMinutes: showsHealth ? health.activity.exerciseMinutes : nil).card() }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: tracking.isToday ? "Today" : tracking.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)),
                                     actionTitle: "Add") { showWorkout = true }
                        ScheduledTodayList(member: member) { showSchedule = true }
                        HealthActivityCard(member: member)
                        ActivityGoalBars(member: member, showsSteps: showsHealth)
                        if list.isEmpty {
                            EmptyState(symbol: "figure.run", title: TodayLayout.isChild(member) ? "No play logged yet" : "No workout yet",
                                       message: TodayLayout.isChild(member) ? "Log free play, sports, cycling or any activity to earn today's star." : "Log a walk, a run or any activity to add to today's allowance.")
                        } else {
                            VStack(spacing: 0) {
                                ForEach(list) { w in
                                    LogRow(symbol: w.workoutKind.symbol, title: w.workoutKind.title,
                                           subtitle: "\(w.minutes) min \u{00B7} \(w.intensity.title)" + (w.source == "health" ? " \u{00B7} Health" : "") + StrengthSummary.text(w.exercises) + (w.note.map { " \u{00B7} \($0)" } ?? ""),
                                           trailing: TodayLayout.isChild(member) ? "" : "\(w.caloriesBurned) kcal", tint: .orange,
                                           onTap: (w.exercises?.isEmpty == false) ? { viewingWorkout = w } : nil,
                                           onEdit: w.source == "health" ? nil : { editingWorkout = w }) {
                                        Task { await tracking.delete(w) }
                                    }
                                    if w.id != list.last?.id { Divider().padding(.leading, 48) }
                                }
                            }
                        }
                    }
                    .card()
                    if !TodayLayout.isChild(member) {
                        Button { showPlan = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "chart.bar.doc.horizontal").frame(width: 34, height: 34)
                                    .background(Theme.brand.opacity(0.12), in: Circle()).foregroundStyle(Theme.brand)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Weight & daily intake plan").font(.subheadline.weight(.semibold))
                                    Text("Target weight, a paced calorie goal and BMI").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .card()
                        Button { showBuddies = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.2.fill").frame(width: 34, height: 34)
                                    .background(Theme.brand.opacity(0.12), in: Circle()).foregroundStyle(Theme.brand)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Gym buddies").font(.subheadline.weight(.semibold))
                                    Text("Train with friends and copy their workouts").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .card()
                    }
                    if let message = tracking.errorMessage { Text(message).font(.footnote).foregroundStyle(.red) }
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
            .background(AppBackground())
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showBuddies) { BuddiesView() }
            .sheet(isPresented: $showPlan) { NutritionPlanView(member: member) }
            .sheet(isPresented: $showWorkout) { LogWorkoutSheet(member: member) }
            .sheet(isPresented: $showSchedule) { ScheduleView(member: member) }
            .sheet(item: $viewingWorkout) { w in WorkoutDetailView(workout: w) { editingWorkout = w } }
            .sheet(item: $editingWorkout) { w in
                if w.workoutKind == .strength { StrengthSessionView(member: member, editing: w) } else { LogWorkoutSheet(member: member, editing: w) }
            }
        }
    }
}

/// Today's scheduled activities that haven't been logged yet, each with a Went button, and a link to the weekly schedule.
struct ScheduledTodayList: View {
    let member: Member
    var showsScheduleLink = true
    var onSchedule: () -> Void = {}
    @Environment(FamilyStore.self) private var family
    @Environment(TrackingStore.self) private var tracking

    var body: some View {
        let todays = tracking.isToday ? ScheduleMath.items(tracking.schedules, for: member.id, on: Date()) : []
        let pending = todays.filter { !ScheduleMath.isLogged($0, workouts: tracking.workouts(for: member), on: Date()) }
        if !pending.isEmpty || showsScheduleLink {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(pending) { s in
                    HStack(spacing: 10) {
                        Image(systemName: s.workoutKind.symbol).foregroundStyle(.orange)
                        Text("\(s.title) at \(ScheduleMath.timeText(s.time))").font(.subheadline)
                        Spacer()
                        if family.canManage(member) {
                            Button("Went") {
                                Task {
                                    if await tracking.logActivity(for: member, kind: s.kind, minutes: s.minutes, at: Date(), householdId: family.householdId) {
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.small).tint(.orange)
                        }
                    }
                }
                if showsScheduleLink {
                    Button(action: onSchedule) {
                        Label(tracking.schedules(for: member).isEmpty ? "Set up a weekly schedule" : "Weekly schedule", systemImage: "calendar")
                            .font(.footnote.weight(.semibold))
                    }
                }
            }
        }
    }
}

/// Steps and weekly workout goal progress.
struct ActivityGoalBars: View {
    let member: Member
    let showsSteps: Bool
    @Environment(TrackingStore.self) private var tracking
    @Environment(HealthKitManager.self) private var health

    var body: some View {
        let steps = showsSteps ? health.activity.steps : nil
        let week = tracking.weeklyMinutes(for: member)
        if (member.goals.dailySteps != nil && steps != nil) || member.goals.weeklyWorkoutMinutes != nil {
            VStack(spacing: 10) {
                if let goal = member.goals.dailySteps, let steps {
                    bar("Steps", "\(steps.formatted()) of \(goal.formatted())", ActivityGoals.fraction(done: steps, goal: goal) ?? 0, .blue)
                }
                if let goal = member.goals.weeklyWorkoutMinutes {
                    bar("Workouts this week", "\(week) of \(goal) min", ActivityGoals.fraction(done: week, goal: goal) ?? 0, .orange)
                }
            }
        }
    }

    private func bar(_ title: String, _ detail: String, _ fraction: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.subheadline.weight(.semibold)); Spacer(); Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            ProgressView(value: fraction).tint(fraction >= 1 ? .green : tint)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The small Activity card on Today: today at a glance, with a way in to the full screen.
struct ActivitySummaryCard: View {
    let member: Member
    let onOpen: () -> Void
    @Environment(TrackingStore.self) private var tracking
    @Environment(HealthKitManager.self) private var health
    @AppStorage("healthMemberID") private var healthMemberID = ""

    var body: some View {
        let showsHealth = HealthActivityCard.isVisible(for: member, linkedID: healthMemberID, health: health)
        let logged = tracking.workouts(for: member)
        let minutes = max(logged.reduce(0) { $0 + $1.minutes }, showsHealth ? (health.activity.exerciseMinutes ?? 0) : 0)
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Activity", actionTitle: "Open", action: onOpen)
            HStack(spacing: 10) {
                StatTile(title: "Active min", value: "\(minutes)", symbol: "timer", tint: Theme.brand)
                if showsHealth { StatTile(title: "Steps", value: health.activity.steps.map { $0.formatted() } ?? "\u{2013}", symbol: "figure.walk", tint: .blue) }
                StatTile(title: "Workouts", value: "\(logged.count)", symbol: "figure.run", tint: .orange)
            }
            ScheduledTodayList(member: member, showsScheduleLink: false)
            ActivityGoalBars(member: member, showsSteps: showsHealth)
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .id("health")
    }
}
