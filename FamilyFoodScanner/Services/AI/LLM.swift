import Foundation

/// One interface over the key-based AIs, so every feature works with any of them.
/// Content blocks use the Anthropic shape (text and base64 image blocks); the OpenAI-style
/// client (also used for Grok and Gemini, which offer compatible endpoints) translates them.
enum LLM {
    case claude(key: String)
    /// OpenAI, Grok (xAI) or Gemini (Google), all through OpenAI-compatible endpoints.
    case compatible(provider: AIProvider, key: String, model: String)

    var vendorName: String {
        switch self {
        case .claude: "Anthropic"
        case .compatible(let provider, _, _): provider.vendorName
        }
    }

    func send(system: String?, content: [[String: Any]], maxTokens: Int) async throws -> String {
        try await chat(system: system, messages: [["role": "user", "content": content]], maxTokens: maxTokens)
    }

    /// `messages` alternate user/assistant; content is a string or a list of blocks.
    func chat(system: String?, messages: [[String: Any]], maxTokens: Int) async throws -> String {
        switch self {
        case .claude(let key):
            return try await AnthropicClient(apiKey: key).chat(system: system, messages: messages, maxTokens: maxTokens)
        case .compatible(let provider, let key, let model):
            return try await OpenAIClient(provider: provider, apiKey: key, model: model)
                .chat(system: system, messages: messages, maxTokens: maxTokens)
        }
    }

    func verify() async throws {
        switch self {
        case .claude(let key): try await AnthropicClient(apiKey: key).verify()
        case .compatible(let provider, let key, let model):
            try await OpenAIClient(provider: provider, apiKey: key, model: model).verify()
        }
    }
}

/// Talks straight to an OpenAI-style Chat Completions API with the user's own key: OpenAI itself, xAI (Grok)
/// or Google (Gemini's compatibility endpoint).
struct OpenAIClient {
    var provider: AIProvider = .openai
    let apiKey: String
    let model: String

    var baseURL: String { Self.baseURL(for: provider) }

    static func baseURL(for provider: AIProvider) -> String {
        switch provider {
        case .grok: "https://api.x.ai/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
        default: "https://api.openai.com/v1"
        }
    }

    // MARK: Model choice

    /// Best first. The app asks the key which of these it can use, so it keeps working as names change.
    static let preferredModels = ["gpt-5.5", "gpt-5", "gpt-5-mini", "gpt-4.1", "gpt-4o", "gpt-4o-mini"]

    static func fallbackModel(for provider: AIProvider) -> String {
        switch provider {
        case .grok: "grok-4"
        case .gemini: "gemini-2.5-flash"
        default: "gpt-4o"
        }
    }
    static let fallbackModel = "gpt-4o"

    /// Picks the model to use from the ids a key can access. Names change often, so for Grok and Gemini
    /// this takes the newest suitable one by version number rather than a fixed name.
    static func pickModel(for provider: AIProvider, from ids: [String]) -> String {
        switch provider {
        case .grok:
            // Plain flagship ids like "grok-4" or "grok-4.5"; skips -mini, -fast, -vision variants and images.
            return newest(in: ids, pattern: #"^grok-(\d+)(?:\.(\d+))?$"#) ?? fallbackModel(for: .grok)
        case .gemini:
            // "gemini-3.8-flash": fast, cheap and sees images. Skips lite, image, audio, live and preview builds.
            let banned = ["lite", "image", "tts", "audio", "live", "embedding", "thinking", "exp", "preview", "robotics", "computer"]
            let usable = ids.filter { id in !banned.contains { id.contains($0) } }
            return newest(in: usable, pattern: #"^gemini-(\d+)(?:\.(\d+))?-flash$"#) ?? fallbackModel(for: .gemini)
        default:
            let available = Set(ids)
            return preferredModels.first(where: available.contains) ?? fallbackModel(for: provider)
        }
    }

    static func pickModel(from ids: [String]) -> String { pickModel(for: .openai, from: ids) }

    /// The id with the highest "major.minor" captured by `pattern`.
    static func newest(in ids: [String], pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        var best: (id: String, major: Int, minor: Int)?
        for id in ids {
            let range = NSRange(id.startIndex..., in: id)
            guard let m = regex.firstMatch(in: id, range: range), let majorRange = Range(m.range(at: 1), in: id),
                  let major = Int(id[majorRange]) else { continue }
            let minor = Range(m.range(at: 2), in: id).flatMap { Int(id[$0]) } ?? 0
            if best == nil || (major, minor) > (best!.major, best!.minor) { best = (id, major, minor) }
        }
        return best?.id
    }

    // MARK: Requests

    func chat(system: String?, messages: [[String: Any]], maxTokens: Int) async throws -> String {
        var wire: [[String: Any]] = []
        if let system { wire.append(["role": "system", "content": system]) }
        for m in messages {
            wire.append(["role": (m["role"] as? String) ?? "user", "content": Self.convert(m["content"] ?? "")])
        }
        // Newer models spend part of this budget "thinking", so give them room. OpenAI's newer models want
        // max_completion_tokens; xAI and Gemini's compatible endpoints take max_tokens.
        let budget = max(maxTokens * 3, 800)
        var body: [String: Any] = ["model": model, "messages": wire]
        body[provider == .openai ? "max_completion_tokens" : "max_tokens"] = budget

        var request = URLRequest(url: URL(string: baseURL + "/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Self.error(status: status, data: data) }
        return try Self.replyText(from: data)
    }

    func verify() async throws {
        _ = try await chat(system: nil, messages: [["role": "user", "content": "Reply with the word ok."]], maxTokens: 20)
    }

    /// Model ids this key can use (needs no special permission on most keys).
    static func availableModels(provider: AIProvider, apiKey: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: baseURL(for: provider) + "/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw error(status: status, data: data) }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return ((json?["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
            .map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }        // Gemini prefixes ids with "models/"
    }

    /// Anthropic-style blocks to OpenAI content parts. Plain strings pass through.
    static func convert(_ content: Any) -> Any {
        guard let blocks = content as? [[String: Any]] else { return content }
        return blocks.compactMap { block -> [String: Any]? in
            switch block["type"] as? String {
            case "text":
                return ["type": "text", "text": (block["text"] as? String) ?? ""]
            case "image":
                guard let source = block["source"] as? [String: Any],
                      let data = source["data"] as? String else { return nil }
                let media = (source["media_type"] as? String) ?? "image/jpeg"
                return ["type": "image_url", "image_url": ["url": "data:\(media);base64,\(data)"]]
            default:
                return nil
            }
        }
    }

    static func error(status: Int, data: Data) -> AnthropicClient.ClientError {
        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
        switch status {
        case 401, 403: return .invalidKey
        case 429:
            let lower = (message ?? "").lowercased()
            if lower.contains("quota") || lower.contains("billing") || lower.contains("credit") {
                return .rejected("This account has no credit or quota left. Check billing with the AI provider.")
            }
            return .rateLimited
        case 500...599: return .busy
        default: return .rejected(message ?? "The AI service returned an error (\(status)).")
        }
    }

    static func replyText(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = ((json["choices"] as? [[String: Any]])?.first?["message"]) as? [String: Any] else {
            throw AnthropicClient.ClientError.badResponse
        }
        var text = ""
        if let s = message["content"] as? String { text = s }
        else if let parts = message["content"] as? [[String: Any]] {
            text = parts.compactMap { $0["text"] as? String }.joined()
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AnthropicClient.ClientError.badResponse }
        return text
    }
}
