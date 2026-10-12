import SwiftUI

/// A short, dismissible checklist introducing the parts of the app the 3-slide welcome carousel and the
/// profile-setup form never mention — medications, Gym Buddies, AI-linked scanning, Apple Health. Each
/// item is a real signal (family size, whether a key is linked, whether Health is connected) or a
/// one-time flag set at the place that action happens (see `GettingStarted`), not a fake progress bar.
/// Hides itself once every item is done, or the person dismisses it — it's a nudge, not a gate.
struct GettingStartedCard: View {
    let member: Member
    @Environment(FamilyStore.self) private var family
    @Environment(AIConnection.self) private var ai
    @Environment(HealthKitManager.self) private var health
    @AppStorage("healthMemberID") private var healthMemberID = ""
    @AppStorage("dismissedGettingStarted") private var dismissed = false
    @State private var expanded = true
    @State private var showAddMember = false
    @State private var showScan = false
    @State private var showConnectAI = false
    @State private var showBuddies = false
    @State private var connectingHealth = false

    private struct Item: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let done: Bool
        let action: () -> Void
    }

    private var hasLoggedFood: Bool { UserDefaults.standard.bool(forKey: GettingStarted.hasLoggedFoodKey) }
    private var hasOpenedBuddies: Bool { UserDefaults.standard.bool(forKey: GettingStarted.hasOpenedBuddiesKey) }

    private var items: [Item] {
        [
            Item(id: "family", title: "Add your family", symbol: "person.3.fill", done: family.members.count > 1) { showAddMember = true },
            Item(id: "scan", title: "Try a plate or barcode scan", symbol: "camera.viewfinder", done: hasLoggedFood) { showScan = true },
            Item(id: "ai", title: "Link an AI key for accurate scans", symbol: "key.fill", done: ai.keyClient != nil) { showConnectAI = true },
            Item(id: "health", title: "Connect Apple Health", symbol: "heart.fill", done: health.hasRequestedAccess) { Task { await connectHealth() } },
            Item(id: "buddies", title: "Check out Gym Buddies", symbol: "figure.run", done: hasOpenedBuddies) { showBuddies = true },
        ]
    }

    private var remaining: Int { items.filter { !$0.done }.count }

    var body: some View {
        if !dismissed && remaining > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(Theme.brand)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Get the most out of NutriKin").readableFont(17, weight: .semibold, relativeTo: .subheadline).foregroundStyle(.primary)
                            Text("\(items.count - remaining) of \(items.count) done").readableFont(14, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { dismissed = true } label: { Image(systemName: "xmark").readableFont(13, weight: .semibold).foregroundStyle(.secondary) }
                            .buttonStyle(.plain).frame(width: 32, height: 32).accessibilityLabel("Dismiss")
                        Image(systemName: "chevron.right").readableFont(14, weight: .semibold, relativeTo: .caption).foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item)
                            if index != items.count - 1 { Divider() }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .card(padding: 16, radius: 18)
            .sheet(isPresented: $showAddMember) { MemberEditView(mode: .add) }
            .sheet(isPresented: $showScan) { PlateScanView(logFor: member) { showScan = false } }
            .sheet(isPresented: $showConnectAI) { ConnectAIView() }
            .sheet(isPresented: $showBuddies) { BuddiesView() }
        }
    }

    private func row(_ item: Item) -> some View {
        Button(action: item.action) {
            HStack(spacing: 12) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .readableFont(20, weight: .regular, relativeTo: .body)
                    .foregroundStyle(item.done ? Theme.brand : .secondary)
                Image(systemName: item.symbol).readableFont(14, weight: .medium).foregroundStyle(.secondary).frame(width: 20)
                Text(item.title).readableFont(16, weight: .regular, relativeTo: .subheadline)
                    .foregroundStyle(item.done ? .secondary : .primary)
                    .strikethrough(item.done)
                Spacer(minLength: 4)
                if !item.done { Image(systemName: "chevron.right").readableFont(13, weight: .semibold).foregroundStyle(.tertiary) }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.done || (item.id == "health" && connectingHealth))
    }

    private func connectHealth() async {
        guard let me = family.members.first(where: { $0.userId == family.myUserId && family.myUserId != nil }) else { return }
        connectingHealth = true
        defer { connectingHealth = false }
        healthMemberID = me.id.uuidString
        await health.configure(userID: family.myUserId, memberID: me.id)
        await health.requestAccess()
    }
}
