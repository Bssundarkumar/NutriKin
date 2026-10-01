import SwiftUI

/// "Get a tip for today": one warm, practical food idea from the person's AI, only when they ask and only when AI is set up.
/// Shown as a slim pill; tapping fetches a tip and expands to show it right there, collapsing again on a second tap.
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
    @State private var expanded = false
    @State private var snacks: String?
    @State private var carerNote: String?
    @Environment(MedicationStore.self) private var medications

    var body: some View {
        if ai.textProvider != nil, tracking.isToday, budget.eaten.calories > 0 || TodayLayout.isChild(member) || TodayLayout.isOlderAdult(member) {
            VStack(alignment: .leading, spacing: 10) {
                Button { tap() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(Theme.brand)
                        Text(loading ? "Thinking\u{2026}" : (tip == nil ? "Get a tip for today" : "Today's tip"))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(loading)

                if expanded {
                    VStack(alignment: .leading, spacing: 10) {
                        if let tip {
                            Text(tip).font(.subheadline)
                            Text("Written by AI. General food ideas, not medical advice.").font(.caption2).foregroundStyle(.secondary)
                        }
                        if TodayLayout.isChild(member) {
                            if let snacks { Text(snacks).font(.subheadline) }
                            Button { fetchSnacks() } label: { Label(snacks == nil ? "Snack and lunchbox ideas" : "Another idea", systemImage: "sparkles").font(.footnote.weight(.semibold)) }
                                .disabled(loading)
                        }
                        if TodayLayout.isOlderAdult(member) {
                            if let carerNote { Text(carerNote).font(.subheadline) }
                            Button { fetchCarerNote() } label: { Label(carerNote == nil ? "Weekly note for the family" : "Another note", systemImage: "sparkles").font(.footnote.weight(.semibold)) }
                                .disabled(loading)
                        }
                        if tip != nil {
                            Button("Another tip") { fetch() }.font(.footnote.weight(.semibold)).disabled(loading)
                        }
                    }
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .onChange(of: member.id) { _, _ in tip = nil; expanded = false }
        }
    }

    private func tap() {
        withAnimation(.snappy) { expanded.toggle() }
        if expanded && tip == nil { fetch() }
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
