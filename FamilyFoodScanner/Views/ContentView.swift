import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(FamilyStore.self) private var family
    @Environment(HistoryStore.self) private var history
    @Environment(AIConnection.self) private var ai
    @Environment(TrackingStore.self) private var tracking
    @Environment(GroceryStore.self) private var groceries
    @State private var tab: Tab = Tab(rawValue: Demo.startTab) ?? .today

    private enum Tab: String, Hashable { case today, scan, groceries, history, family }

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                ProgressView()
            case .signedOut:
                SignInView()
            case .signedIn:
                switch family.phase {
                case .idle, .loading:
                    ProgressView()
                case .failed(let message):
                    retryView(message)
                case .loaded:
                    if family.hasHousehold {
                        TabView(selection: $tab) {
                            TodayView(onScan: { tab = .scan })
                                .tabItem { Label("Today", systemImage: "chart.pie.fill") }
                                .tag(Tab.today)
                            ScanView(isActive: tab == .scan)
                                .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
                                .tag(Tab.scan)
                            GroceriesView()
                                .tabItem { Label("Groceries", systemImage: "cart.fill") }
                                .tag(Tab.groceries)
                            HistoryView()
                                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                                .tag(Tab.history)
                            FamilyView()
                                .tabItem { Label("Family", systemImage: "person.3") }
                                .tag(Tab.family)
                        }
                        .sensoryFeedback(.selection, trigger: tab)
                    } else {
                        HouseholdSetupView()
                    }
                }
            }
        }
        .tint(Theme.brand)
        .animation(.smooth(duration: 0.3), value: auth.state)
        .animation(.smooth(duration: 0.3), value: family.phase)
        .task(id: family.householdId) { tracking.setHousehold(family.householdId); groceries.setHousehold(family.householdId) }
        // Whatever the route (sign out, deleted account, revoked session), the linked AI key goes too.
        .onChange(of: auth.state) { old, new in
            if case .signedIn = old, case .signedOut = new { ai.disconnect(); history.wipeLocal(); tracking.reset(); groceries.reset() }
        }
        // Runs on launch and again whenever the signed-in account changes.
        .task(id: auth.state) {
            if case .signedIn = auth.state {
                await family.loadHousehold()
            } else {
                family.reset()
                await history.load(householdId: nil)
            }
        }
    }

    private func retryView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Couldn't load your family")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await family.loadHousehold() } }
                .buttonStyle(.borderedProminent)
            Button("Sign out") { Task { await auth.signOut() } }
                .font(.footnote)
        }
        .padding(32)
    }
}
