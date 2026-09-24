import Foundation
import Observation

/// Which AI the person has set up: Apple's on-device model (automatic where supported) and/or their own
/// Claude or OpenAI key. Keys live only in this iPhone's Keychain; disconnecting or signing out removes them.
@MainActor
@Observable
final class AIConnection {
    private static let preferenceKey = "aiProviderPreference"
    private static let openAIModelKey = "openAIModel"

    /// Key-based providers that have a key stored.
    private(set) var linked: Set<AIProvider>
    private(set) var appleStatus: AppleAI.Status
    var isWorking = false
    var errorMessage: String?

    /// What the person prefers when several are possible. Apple's on-device AI is the default.
    var preference: AIProvider {
        didSet { UserDefaults.standard.set(preference.rawValue, forKey: Self.preferenceKey) }
    }

    init() {
        linked = Demo.isOn ? [.claude] : Set([AIProvider.claude, .openai].filter { KeychainStore.get(Self.account(for: $0)) != nil })
        appleStatus = Demo.isOn ? .available : AppleAI.status
        preference = AIProvider(rawValue: UserDefaults.standard.string(forKey: Self.preferenceKey) ?? "") ?? .apple
    }

    /// True when the person has linked at least one key (needed for photo features).
    var isConnected: Bool { !linked.isEmpty }
    func isLinked(_ provider: AIProvider) -> Bool { linked.contains(provider) }

    /// Re-checks Apple's model (it can finish downloading, or Apple Intelligence can be switched on).
    func refreshApple() { appleStatus = Demo.isOn ? .available : AppleAI.status }

    /// Who answers chat questions and meal plans right now, or nil if nothing is set up.
    var textProvider: AIProvider? {
        AIProvider.choose(preference: preference, appleAvailable: appleStatus.isAvailable, linked: linked)
    }

    /// The key-based provider used for photos, and as a fallback when Apple's model fails.
    var keyProvider: AIProvider? { AIProvider.chooseKey(preference: preference, linked: linked) }
    var keyClient: LLM? { keyProvider.flatMap(client(for:)) }

    func client(for provider: AIProvider) -> LLM? {
        guard provider.usesKey, let key = KeychainStore.get(Self.account(for: provider)) else { return nil }
        if provider == .claude { return .claude(key: key) }
        return .openai(key: key, model: UserDefaults.standard.string(forKey: Self.openAIModelKey) ?? OpenAIClient.fallbackModel)
    }

    func connect(key raw: String, provider: AIProvider) async -> Bool {
        let key = Self.cleaned(raw)
        guard provider.usesKey, Self.looksLikeKey(key, for: provider) else {
            errorMessage = provider == .claude
                ? "That doesn't look like an Anthropic key. It starts with \"sk-ant-\"."
                : "That doesn't look like an OpenAI key. It starts with \"sk-\"."
            return false
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let client: LLM
            if provider == .claude {
                client = .claude(key: key)
            } else {
                // Ask the key which models it can use and take the best; fall back to a common one.
                let ids = (try? await OpenAIClient.availableModels(apiKey: key)) ?? []
                client = .openai(key: key, model: OpenAIClient.pickModel(from: ids))
            }
            try await client.verify()
            guard KeychainStore.set(key, for: Self.account(for: provider)) else {
                errorMessage = "Couldn't store the key securely on this iPhone."
                return false
            }
            if case .openai(_, let model) = client { UserDefaults.standard.set(model, forKey: Self.openAIModelKey) }
            linked.insert(provider)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func disconnect(_ provider: AIProvider) {
        guard provider.usesKey else { return }
        KeychainStore.remove(Self.account(for: provider))
        linked.remove(provider)
        errorMessage = nil
    }

    /// Removes every stored key (sign out, deleted account).
    func disconnect() { AIProvider.allCases.forEach(disconnect) }

    nonisolated static func account(for provider: AIProvider) -> String {
        provider == .openai ? "openai-api-key" : "anthropic-api-key"
    }

    nonisolated static func cleaned(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func looksLikeKey(_ key: String, for provider: AIProvider) -> Bool {
        guard key.count >= 20, !key.contains(where: \.isWhitespace) else { return false }
        switch provider {
        case .claude: return key.hasPrefix("sk-ant-")
        case .openai: return key.hasPrefix("sk-") && !key.hasPrefix("sk-ant-")
        case .apple: return false
        }
    }
}
