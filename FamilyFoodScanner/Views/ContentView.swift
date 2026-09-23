import SwiftUI

struct ContentView: View {
    @Environment(FamilyStore.self) private var family

    var body: some View {
        Group {
            if family.hasHousehold {
                TabView {
                    ScanView()
                        .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
                    FamilyView()
                        .tabItem { Label("Family", systemImage: "person.3") }
                }
            } else {
                HouseholdSetupView()
            }
        }
        .tint(Color(red: 0.12, green: 0.35, blue: 0.24))
    }
}
