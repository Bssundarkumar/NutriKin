import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(FamilyStore.self) private var family
    @Environment(HistoryStore.self) private var history

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
                        TabView {
                            ScanView()
                                .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
                            HistoryView()
                                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                            FamilyView()
                                .tabItem { Label("Family", systemImage: "person.3") }
                        }
                    } else {
                        HouseholdSetupView()
                    }
                }
            }
        }
        .tint(Color(red: 0.12, green: 0.35, blue: 0.24))
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
