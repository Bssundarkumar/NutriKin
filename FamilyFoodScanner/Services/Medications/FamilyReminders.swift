import Foundation
import UIKit
import UserNotifications
import Supabase
import Observation

@MainActor
@Observable
final class FamilyReminders {
    static let shared = FamilyReminders()
    private(set) var enabled = false
    private(set) var message: String?
    private var userID: UUID?
    private var token: String?
    private var preferenceKey: String { "familyReminders-\(userID?.uuidString ?? "signedOut")" }

    func configure(userID: UUID?) async {
        guard self.userID != userID else { return }
        if let token, self.userID != nil {
            _ = try? await Backend.client.from("push_devices").delete().eq("token", value: token).execute()
        }
        self.userID = userID
        enabled = userID != nil && UserDefaults.standard.bool(forKey: preferenceKey)
        await register()
    }

    func setEnabled(_ value: Bool) async {
        guard userID != nil else { message = "Sign in to receive family reminders."; return }
        if value {
            guard await MedicationReminders.requestAuthorization() else {
                enabled = false; message = "Allow notifications in iPhone Settings to receive family reminders."; return
            }
        }
        enabled = value
        UserDefaults.standard.set(value, forKey: preferenceKey)
        await register()
    }

    private func register() async {
        guard !Demo.isOn else { return }
        if enabled { UIApplication.shared.registerForRemoteNotifications() }
        await uploadToken()
    }

    func receivedToken(_ data: Data) async {
        token = data.map { String(format: "%02x", $0) }.joined()
        await uploadToken()
    }

    private struct Registration: Encodable { var p_token: String; var p_environment: String; var p_enabled: Bool }
    private func uploadToken() async {
        guard let token, let userID, !Demo.isOn else { return }
        do {
            let session = try await Backend.client.auth.session
            guard session.user.id == userID else { return }
            #if DEBUG
            let environment = "sandbox"
            #else
            let environment = "production"
            #endif
            try await Backend.client.rpc("register_push_device", params: Registration(p_token: token, p_environment: environment, p_enabled: enabled)).execute()
            message = nil
        } catch { message = "Couldn't register this phone for family reminders. Please try again." }
    }

    func registrationFailed() { message = "Push notifications couldn't connect. Please try again on your iPhone." }

    /// Disable while the outgoing account's session is still available.
    func disconnect() async {
        enabled = false
        await uploadToken()
        userID = nil
        UIApplication.shared.unregisterForRemoteNotifications()
    }
}
