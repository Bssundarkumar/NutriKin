import SwiftUI

@main
struct FamilyFoodScannerApp: App {
    @State private var family = FamilyStore()
    @State private var health = HealthKitManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(family)
                .environment(health)
        }
    }
}
