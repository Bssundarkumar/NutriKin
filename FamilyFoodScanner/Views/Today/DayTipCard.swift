import SwiftUI

/// "Get a tip for today": one warm, practical food idea from the person's AI, only when they ask and only when AI is set up.
struct DayTipCard: View {
    let member: Member
    let budget: DayBudget
    let steps: Int?
    let weekMinutes: Int
    @Environment(AIConnection.self) private var ai
    @Environment(FamilyStore.self) private var family
    @Environment(TrackingStore.self) private var tracking
    @State private var tip: String?
    @State private var loading = false
    @State private var snacks: String?
    @State private var carerNote: String?
    @Environment(MedicationStore.self) private var medications

    var body: some View {
        if ai.textProvider != nil, tracking.isToday, budget.eaten.calories > 0 || TodayLayout.isChild(member) || TodayLayout.isOlderAdult(member) {
            VStack(alignment: .leading, spacing: 8) {
                if let tip {
                    Label("A tip for \(member.name)", systemImage: "sparkles").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.brand)
                    Text(tip).font(.subheadline)
                    Text("Written by AI. General food ideas, not medical advice.").font(.caption2).foregroundStyle(.secondary)
                }
                if TodayLayout.isChild(member) {
                    if let snacks {
                        Label("Snack ideas", systemImage: "carrot").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.brand)
                        Text(snacks).font(.subheadline)
                    }
                    Button { fetchSnacks() } label: { Label(snacks == nil ? "Snack and lunchbox ideas" : "More ideas", systemImage: "sparkles").font(.subheadline.weight(.semibold)) }
                        .disabled(loading)
                }
                if TodayLayout.isOlderAdult(member) {
                    if let carerNote {
                        Label("A note for the family", systemImage: "heart.text.square").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.brand)
                        Text(carerNote).font(.subheadline)
                    }
                    Button { fetchCarerNote() } label: { Label(carerNote == nil ? "Weekly note for the family" : "Another note", systemImage: "sparkles").font(.subheadline.weight(.semibold)) }
                        .disabled(loading)
                }
                Button { fetch() } label: {
                    Label(loading ? "Thinking\u{2026}" : (tip == nil ? "Get a tip for today" : "Another tip"), systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(loading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .onChange(of: member.id) { _, _ in tip = nil }
        }
    }

    private func fetchCarerNote() {
        loading = true
        let days = KidActivity.week(tracking.recentWorkouts(for: member))
        let doses = MedicationSchedule.summary(medications.doses(for: member))
        Task {
            carerNote = await AIQuick.text(rules: DayCoach.carerWeekRules,
                                           user: DayCoach.carerWeekPrompt(member: member, days: days, doses: doses, eatenToday: budget.eaten.calories > 0),
                                           members: family.members, ai: ai, forMember: member)
                ?? "Couldn't get a note right now. Try again in a moment."
            loading = false
        }
    }

    private func fetchSnacks() {
        loading = true
        Task {
            snacks = await AIQuick.text(rules: DayCoach.kidSnackRules, user: DayCoach.dayPrompt(member: member, budget: budget, steps: steps, weekMinutes: weekMinutes),
                                        members: family.members, ai: ai, forMember: member)
                ?? "Couldn't get ideas right now. Try again in a moment."
            loading = false
        }
    }

    private func fetch() {
        loading = true
        Task {
            tip = await AIQuick.text(rules: DayCoach.tipRules, user: DayCoach.dayPrompt(member: member, budget: budget, steps: steps, weekMinutes: weekMinutes),
                                     members: family.members, ai: ai, forMember: member)
                ?? "Couldn't get a tip right now. Try again in a moment."
            loading = false
        }
    }
}
