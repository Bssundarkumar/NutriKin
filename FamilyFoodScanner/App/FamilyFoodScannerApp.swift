import SwiftUI
import UserNotifications

/// Sets up notification handling as soon as the app launches, so a tap on a reminder is never missed.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        MedicationReminders.registerCategories()
        return true
    }
}

@main
struct FamilyFoodScannerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var auth = AuthStore()
    @State private var family = FamilyStore()
    @State private var history = HistoryStore()
    @State private var health = HealthKitManager()
    @State private var ai = AIConnection()
    @State private var tracking = TrackingStore()
    @State private var groceries = GroceryStore()
    @State private var medications = MedicationStore()
    @State private var customExercises = CustomExerciseStore()
    @State private var checkIns = DailyCheckInStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(auth)
                .environment(family)
                .environment(history)
                .environment(health)
                .environment(ai)
                .environment(tracking)
                .environment(groceries)
                .environment(medications)
                .environment(customExercises)
                .environment(checkIns)
                .onOpenURL { url in
                    // Only invite links matter here; the Google sign-in
                    // callback is handled by the browser sheet itself.
                    if let code = InviteLink.code(from: url) { family.pendingInviteCode = code }
                }
        }
    }
}
