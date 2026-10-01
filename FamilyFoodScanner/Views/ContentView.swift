import SwiftUI

struct ContentView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(FamilyStore.self) private var family
    @Environment(HistoryStore.self) private var history
    @Environment(AIConnection.self) private var ai
    @Environment(TrackingStore.self) private var tracking
    @Environment(GroceryStore.self) private var groceries
    @Environment(MedicationStore.self) private var medications
    @Environment(HealthKitManager.self) private var health
    @Environment(DailyCheckInStore.self) private var checkIns
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("healthMemberID") private var healthMemberID = ""
    @State private var refreshingHealth = false
    @State private var healthRefreshPending = false
    @State private var tab: Tab = Tab(rawValue: Demo.startTab) ?? .today
    @AppStorage("hasSeenWelcomeCarousel") private var hasSeenWelcomeCarousel = false

    private enum Tab: String, Hashable { case today, scan, groceries, family }

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                ProgressView()
            case .signedOut:
                if hasSeenWelcomeCarousel {
                    SignInView()
                } else {
                    WelcomeCarouselView { hasSeenWelcomeCarousel = true }
                }
            case .signedIn:
                switch family.phase {
                case .idle, .loading:
                    ProgressView("Loading your family…")
                case .failed(let message):
                    retryView(message)
                case .loaded:
                    if family.hasHousehold {
                        TabView(selection: $tab) {
                            TodayView()
                                .tabItem { Label("Today", systemImage: "house.fill") }
                                .tag(Tab.today)
                            ScanView(isActive: tab == .scan)
                                .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
                                .tag(Tab.scan)
                            GroceriesView()
                                .tabItem { Label("Groceries", systemImage: "cart.fill") }
                                .tag(Tab.groceries)
                            FamilyView()
                                .tabItem { Label("Family", systemImage: "person.3") }
                                .tag(Tab.family)
                        }
                        .sensoryFeedback(.selection, trigger: tab)
                        .fullScreenCover(isPresented: Binding(
                            get: { family.promptToAddMembers },
                            set: { family.promptToAddMembers = $0 }
                        )) {
                            GoalOnboardingView()
                        }
                    } else {
                        HouseholdSetupView()
                    }
                }
            }
        }
        .readableFont(18)
        .environment(\.defaultMinListRowHeight, 52)
        .tint(Theme.brand)
        .animation(.smooth(duration: 0.3), value: auth.state)
        .animation(.smooth(duration: 0.3), value: family.phase)
        .task(id: family.householdId) { tracking.setHousehold(family.householdId); groceries.setHousehold(family.householdId); medications.setHousehold(family.householdId) }
        .task(id: "\(family.myUserId?.uuidString ?? "")-\(healthMemberID)") {
            tracking.healthSync = health; checkIns.healthSync = health; family.healthSync = health
            let owner = family.members.first { $0.id.uuidString == healthMemberID && $0.userId == family.myUserId && family.myUserId != nil }
            health.onHealthChange = { await refreshHealth() }
            await health.configure(userID: family.myUserId, memberID: owner?.id)
            await refreshHealth()
        }
        .task(id: family.myUserId) { await FamilyReminders.shared.configure(userID: family.myUserId) }
        .task(id: tracking.day) { await refreshHealth() }
        .onChange(of: tracking.isLoading) { _, loading in
            if !loading { Task { await refreshHealth() } }
        }
        .onChange(of: family.members) { _, _ in
            Task {
                let owner = family.members.first { $0.id.uuidString == healthMemberID && $0.userId == family.myUserId && family.myUserId != nil }
                await health.configure(userID: family.myUserId, memberID: owner?.id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nutrikinFamilyReminder)) { notification in
            guard let memberID = notification.object as? String, family.members.contains(where: { $0.id.uuidString == memberID }) else { return }
            UserDefaults.standard.set(memberID, forKey: "todayMemberID")
            tab = .today
            Task { await tracking.goToToday(); await medications.load(householdId: family.householdId, day: .now) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshHealth() } }
        }
        // Whatever the route (sign out, deleted account, revoked session), the linked AI key goes too.
        .onChange(of: auth.state) { old, new in
            if case .signedIn = old, case .signedOut = new { ai.disconnect(); history.wipeLocal(); tracking.reset(); Task { await ActivityReminders.removeAll() }; groceries.reset(); medications.reset() }
        }
        // Runs on launch and again whenever the signed-in account changes.
        .task(id: auth.state) {
            if case .signedIn = auth.state {
                await family.loadHousehold()
                await FamilyReminders.shared.configure(userID: family.myUserId)
            } else {
                family.reset()
                await history.load(householdId: nil)
            }
        }
    }

    private func refreshHealth() async {
        guard case .signedIn = auth.state else { return }
        if refreshingHealth { healthRefreshPending = true; return }
        guard !Demo.isOn, !tracking.isLoading, let member = family.members.first(where: {
            $0.id == health.linkedMemberID && $0.userId == family.myUserId && family.myUserId != nil
        }) else { return }
        refreshingHealth = true
        defer {
            refreshingHealth = false
            if healthRefreshPending {
                healthRefreshPending = false
                Task { await refreshHealth() }
            }
        }
        let day = tracking.day
        await health.checkAccessStatus()
        guard health.hasRequestedAccess else { return }
        await health.flush()
        await health.refresh()
        await health.loadActivity(day: day)
        guard tracking.day == day, health.linkedMemberID == member.id else { return }
        let waitingMeasurement = health.pendingWrites.values.contains { write in
            write.quantities.contains { $0.type == "HKQuantityTypeIdentifierBodyMass" || $0.type == "HKQuantityTypeIdentifierHeight" }
        }
        if !waitingMeasurement {
            var updated = member
            if let weight = health.snapshot.weightKg, (1...500).contains(weight) { updated.weightKg = weight }
            if let height = health.snapshot.heightCm, (20...260).contains(height) { updated.heightCm = height }
            if updated != member { await family.updateMember(updated, syncToHealth: false) }
        }
        guard health.linkedMemberID == member.id, family.myUserId == member.userId, tracking.day == day else { return }
        // The backend enforces an external-id uniqueness constraint; skip this app's exports.
        let existing = tracking.workouts(for: member) + tracking.recentWorkouts(for: member)
        for workout in HealthImport.newWorkouts(from: health.activity.workouts, existing: existing) {
            guard health.linkedMemberID == member.id, family.myUserId == member.userId, tracking.day == day else { break }
            _ = await tracking.add(HealthImport.workout(from: workout, memberId: member.id, householdId: family.householdId, weightKg: member.weightKg))
        }
    }

    private func retryView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .readableFont(36, weight: .regular, relativeTo: .largeTitle)
                .foregroundStyle(.secondary)
            Text("Couldn't load your family")
                .readableFont(19, weight: .semibold, relativeTo: .headline)
            Text(message)
                .readableFont(16, weight: .regular, relativeTo: .footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await family.loadHousehold() } }
                .buttonStyle(.borderedProminent)
            Button("Sign out") { Task { await auth.signOut() } }
                .readableFont(16, weight: .regular, relativeTo: .footnote)
        }
        .padding(32)
    }
}
