import SwiftUI

/// For children: today's active play against an hour, a week of stars, a one-tap "log play", and a parent summary on request.
struct KidActivityCard: View {
    let member: Member
    let healthMinutes: Int?
    @Environment(TrackingStore.self) private var tracking
    @Environment(FamilyStore.self) private var family
    @Environment(AIConnection.self) private var ai
    @State private var summary: String?
    @State private var loading = false

    private var week: [KidActivity.Day] { KidActivity.week(tracking.recentWorkouts(for: member)) }
    private var todayMinutes: Int {
        max(KidActivity.minutes(tracking.recentWorkouts(for: member), on: Date()), tracking.isToday ? (healthMinutes ?? 0) : 0)
    }
    private var canEdit: Bool { family.canManage(member) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.orange.opacity(0.18), lineWidth: 10)
                    Circle().trim(from: 0, to: min(Double(todayMinutes) / Double(KidActivity.dailyGoalMinutes), 1))
                        .stroke(todayMinutes >= KidActivity.dailyGoalMinutes ? Color.green : Color.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90)).animation(.smooth, value: todayMinutes)
                    VStack(spacing: 0) {
                        Text("\(todayMinutes)").font(.title3.bold().monospacedDigit())
                        Text("of \(KidActivity.dailyGoalMinutes) min").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 92, height: 92)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(todayMinutes) of \(KidActivity.dailyGoalMinutes) minutes of active play today")
                VStack(alignment: .leading, spacing: 6) {
                    Text(KidActivity.message(name: member.name, todayMinutes: todayMinutes)).font(.subheadline.weight(.semibold))
                    if canEdit && tracking.isToday {
                        Button { Task { await logPlay(30) } } label: { Label("Log 30 min of play", systemImage: "plus.circle.fill").font(.footnote.weight(.semibold)) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("This week").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(KidActivity.stars(week)) star\(KidActivity.stars(week) == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach(week) { d in
                        VStack(spacing: 3) {
                            Image(systemName: d.earnedStar ? "star.fill" : "star")
                                .foregroundStyle(d.earnedStar ? Color.yellow : Color.secondary.opacity(0.4))
                            Text(d.date.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(d.date.formatted(.dateTime.weekday(.wide))): \(d.earnedStar ? "star earned" : "\(d.minutes) minutes")")
                    }
                }
            }
            if ai.textProvider != nil {
                if let summary {
                    Text(summary).font(.subheadline)
                    Text("Written by AI. General encouragement, not medical advice.").font(.caption2).foregroundStyle(.secondary)
                }
                Button { fetchSummary() } label: {
                    Label(loading ? "Thinking\u{2026}" : (summary == nil ? "Weekly summary for parents" : "Another summary"), systemImage: "sparkles")
                        .font(.footnote.weight(.semibold))
                }.disabled(loading)
            }
        }
    }

    private func logPlay(_ minutes: Int) async {
        let w = Workout(householdId: family.householdId, memberId: member.id, doneAt: Date(), kind: WorkoutKind.play.rawValue, minutes: minutes,
                        intensity: .moderate, caloriesBurned: WorkoutEstimator.calories(kind: .play, intensity: .moderate, minutes: minutes, weightKg: member.weightKg))
        if await tracking.add(w) { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    private func fetchSummary() {
        loading = true
        let days = week
        Task {
            summary = await AIQuick.text(rules: DayCoach.kidWeekRules, user: DayCoach.kidWeekPrompt(member: member, days: days, workouts: tracking.recentWorkouts(for: member)),
                                         members: family.members, ai: ai)
                ?? "Couldn't get a summary right now. Try again in a moment."
            loading = false
        }
    }
}
