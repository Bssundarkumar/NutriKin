import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(FamilyStore.self) private var family
    @Environment(HistoryStore.self) private var history
    @Environment(AIConnection.self) private var ai
    @State private var tab: Tab = Demo.startTab == "history" ? .history : Demo.startTab == "family" ? .family : .scan

    private enum Tab: Hashable { case scan, history, family }

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
                            ScanView(isActive: tab == .scan)
                                .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
                                .tag(Tab.scan)
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
        // Whatever the route (sign out, deleted account, revoked session), the linked AI key goes too.
        .onChange(of: auth.state) { old, new in
            if case .signedIn = old, case .signedOut = new { ai.disconnect(); history.wipeLocal() }
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
