import SwiftUI

/// The less-often-used things for one person, gathered on a single screen instead of three separate ones:
/// growth chart, weight plan and gym buddies. One tap in from Activity, one tap to any of them.
struct MoreForMemberView: View {
    let member: Member
    @Environment(\.dismiss) private var dismiss
    @State private var showGrowth = false
    @State private var showPlan = false
    @State private var showBuddies = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showGrowth = true } label: { row("chart.xyaxis.line", "Growth chart", "Height and weight over time") }
                    if !TodayLayout.isChild(member) {
                        Button { showPlan = true } label: { row("chart.bar.doc.horizontal", "Weight & daily intake plan", "Target weight, a paced calorie goal and BMI") }
                    }
                }
                if !TodayLayout.isChild(member) {
                    Section {
                        Button { showBuddies = true } label: { row("person.2.fill", "Gym buddies", "Train with friends and copy their workouts") }
                    }
                }
            }
            .softList()
            .navigationTitle("More for \(member.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showGrowth) { GrowthView(member: member) }
            .sheet(isPresented: $showPlan) { NutritionPlanView(member: member) }
            .sheet(isPresented: $showBuddies) { BuddiesView() }
        }
    }

    private func row(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 30, height: 30).foregroundStyle(Theme.brand)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
