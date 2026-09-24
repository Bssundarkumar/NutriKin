import SwiftUI

@main
struct FamilyFoodScannerApp: App {
    @State private var auth = AuthStore()
    @State private var family = FamilyStore()
    @State private var history = HistoryStore()
    @State private var health = HealthKitManager()
    @State private var ai = AIConnection()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(auth)
                .environment(family)
                .environment(history)
                .environment(health)
                .environment(ai)
                .onOpenURL { url in
                    // Only invite links matter here; the Google sign-in
                    // callback is handled by the browser sheet itself.
                    if let code = InviteLink.code(from: url) { family.pendingInviteCode = code }
                }
        }
    }
}
