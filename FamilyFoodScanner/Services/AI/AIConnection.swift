import Foundation
import Observation

/// Which AI the person has set up: Apple's on-device model (automatic where supported) and/or their own
/// Claude or OpenAI key. Keys live only in this iPhone's Keychain; disconnecting or signing out removes them.
@MainActor
@Observable
final class AIConnection {
    private static let preferenceKey = "aiProviderPreference"

    /// Keys are read from the Keychain once and kept in memory: a Keychain read is an inter-process call
    /// that can take tens of milliseconds on a phone, and views ask for the client many times per redraw.
    @ObservationIgnored private var keys: [AIProvider: String] = [:]
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
        var loaded: [AIProvider: String] = [:]
        if !Demo.isOn {
            for vendor in AIProvider.keyVendors { if let key = KeychainStore.get(Self.account(for: vendor)) { loaded[vendor] = key } }
        }
        keys = loaded
        linked = Demo.isOn ? [.claude] : Set(loaded.keys)
        appleStatus = Demo.isOn ? .available : AppleAI.status
        preference = AIProvider(rawValue: UserDefaults.standard.string(forKey: Self.preferenceKey) ?? "") ?? .apple
    }

    /// True when the person has linked at least one key (needed for photo features).
    var isConnected: Bool { !linked.isEmpty }
    func isLinked(_ provider: AIProvider) -> Bool { linked.contains(provider) }

    /// Re-checks Apple's model (it can finish downloading, or Apple Intelligence can be switched on).
    /// The check is a system call, so it's skipped if the model was found available a moment ago.
    func refreshApple() {
        if Demo.isOn { appleStatus = .available; return }
        if appleStatus.isAvailable, Date().timeIntervalSince(lastAppleCheck) < 30 { return }
        lastAppleCheck = Date()
        appleStatus = AppleAI.status
    }
    @ObservationIgnored private var lastAppleCheck = Date()

    /// Photo features can run with a key (the AI sees the photo) or, more roughly, with Apple's on-device AI.
    var canUseAIForPhotos: Bool { keyClient != nil || appleStatus.isAvailable }

    /// Who answers chat questions and meal plans right now, or nil if nothing is set up.
    var textProvider: AIProvider? {
        AIProvider.choose(preference: preference, appleAvailable: appleStatus.isAvailable, linked: linked)
    }

    /// The key-based provider used for photos, and as a fallback when Apple's model fails.
    var keyProvider: AIProvider? { AIProvider.chooseKey(preference: preference, linked: linked) }
    var keyClient: LLM? { keyProvider.flatMap(client(for:)) }

    func client(for provider: AIProvider) -> LLM? {
        guard provider.usesKey, let key = keys[provider] else { return nil }
        if provider == .claude { return .claude(key: key) }
        let model = UserDefaults.standard.string(forKey: Self.modelKey(provider)) ?? OpenAIClient.fallbackModel(for: provider)
        return .compatible(provider: provider, key: key, model: model)
    }

    func connect(key raw: String, provider: AIProvider) async -> Bool {
        let key = Self.cleaned(raw)
        guard provider.usesKey, Self.looksLikeKey(key, for: provider) else {
            errorMessage = "That doesn't look like a \(provider.shortName) key. \(Self.keyHint(provider))"
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
                let ids = (try? await OpenAIClient.availableModels(provider: provider, apiKey: key)) ?? []
                client = .compatible(provider: provider, key: key, model: OpenAIClient.pickModel(for: provider, from: ids))
            }
            try await client.verify()
            guard KeychainStore.set(key, for: Self.account(for: provider)) else {
                errorMessage = "Couldn't store the key securely on this iPhone."
                return false
            }
            if case .compatible(_, _, let model) = client { UserDefaults.standard.set(model, forKey: Self.modelKey(provider)) }
            keys[provider] = key
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
        keys[provider] = nil
        linked.remove(provider)
        errorMessage = nil
    }

    /// Removes every stored key (sign out, deleted account).
    func disconnect() { AIProvider.allCases.forEach(disconnect) }

    nonisolated static func account(for provider: AIProvider) -> String {
        switch provider {
        case .openai: "openai-api-key"
        case .grok: "xai-api-key"
        case .gemini: "gemini-api-key"
        default: "anthropic-api-key"
        }
    }

    nonisolated static func modelKey(_ provider: AIProvider) -> String { "aiModel-\(provider.rawValue)" }

    nonisolated static func keyHint(_ provider: AIProvider) -> String {
        switch provider {
        case .claude: "It starts with \"sk-ant-\"."
        case .openai: "It starts with \"sk-\"."
        case .grok: "It starts with \"xai-\"."
        case .gemini: "It starts with \"AIza\"."
        case .apple: ""
        }
    }

    nonisolated static func cleaned(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func looksLikeKey(_ key: String, for provider: AIProvider) -> Bool {
        guard key.count >= 20, !key.contains(where: \.isWhitespace) else { return false }
        switch provider {
        case .claude: return key.hasPrefix("sk-ant-")
        case .openai: return key.hasPrefix("sk-") && !key.hasPrefix("sk-ant-")
        case .grok: return key.hasPrefix("xai-")
        case .gemini: return key.hasPrefix("AIza")
        case .apple: return false
        }
    }
}
