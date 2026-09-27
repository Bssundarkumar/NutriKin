import SwiftUI

/// The less-often-used things about one person's body and movement, gathered on a single screen: growth
/// chart and gym buddies. (Their weight & daily intake plan lives on Today itself now, next to the
/// calorie goal it sets, not here.)
struct MoreForMemberView: View {
    let member: Member
    @Environment(\.dismiss) private var dismiss
    @State private var showGrowth = false
    @State private var showBuddies = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showGrowth = true } label: { row("chart.xyaxis.line", "Growth chart", "Height and weight over time") }
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
