import Foundation
import Observation

/// Whether the person has linked their own AI account. The key lives only in
/// this iPhone's Keychain; disconnecting (or signing out) removes it.
@MainActor
@Observable
final class AIConnection {
    static let account = "anthropic-api-key"

    private(set) var isConnected: Bool
    var isWorking = false
    var errorMessage: String?

    init() { isConnected = KeychainStore.get(Self.account) != nil }

    var apiKey: String? { KeychainStore.get(Self.account) }

    func connect(key raw: String) async -> Bool {
        let key = Self.cleaned(raw)
        guard Self.looksLikeKey(key) else {
            errorMessage = "That doesn't look like an Anthropic key. It starts with \"sk-ant-\"."
            return false
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await AnthropicClient(apiKey: key).verify()
            guard KeychainStore.set(key, for: Self.account) else {
                errorMessage = "Couldn't store the key securely on this iPhone."
                return false
            }
            isConnected = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func disconnect() {
        KeychainStore.remove(Self.account)
        isConnected = false
        errorMessage = nil
    }

    nonisolated static func cleaned(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func looksLikeKey(_ key: String) -> Bool {
        key.hasPrefix("sk-ant-") && key.count >= 20 && !key.contains(where: \.isWhitespace)
    }
}
