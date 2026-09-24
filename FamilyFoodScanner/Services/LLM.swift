import Foundation

/// One interface over the two key-based AIs, so every feature works with either.
/// Content blocks use the Anthropic shape (text and base64 image blocks); the OpenAI
/// client translates them.
enum LLM {
    case claude(key: String)
    case openai(key: String, model: String)

    var vendorName: String {
        switch self { case .claude: "Anthropic"; case .openai: "OpenAI" }
    }

    func send(system: String?, content: [[String: Any]], maxTokens: Int) async throws -> String {
        try await chat(system: system, messages: [["role": "user", "content": content]], maxTokens: maxTokens)
    }

    /// `messages` alternate user/assistant; content is a string or a list of blocks.
    func chat(system: String?, messages: [[String: Any]], maxTokens: Int) async throws -> String {
        switch self {
        case .claude(let key):
            return try await AnthropicClient(apiKey: key).chat(system: system, messages: messages, maxTokens: maxTokens)
        case .openai(let key, let model):
            return try await OpenAIClient(apiKey: key, model: model).chat(system: system, messages: messages, maxTokens: maxTokens)
        }
    }

    func verify() async throws {
        switch self {
        case .claude(let key): try await AnthropicClient(apiKey: key).verify()
        case .openai(let key, let model): try await OpenAIClient(apiKey: key, model: model).verify()
        }
    }
}

/// Talks straight to OpenAI's Chat Completions API with the user's own key.
struct OpenAIClient {
    let apiKey: String
    let model: String

    /// Best first. The app asks the key which of these it can use, so it keeps working as names change.
    static let preferredModels = ["gpt-5.5", "gpt-5", "gpt-5-mini", "gpt-4.1", "gpt-4o", "gpt-4o-mini"]
    static let fallbackModel = "gpt-4o"

    static func pickModel(from ids: [String]) -> String {
        let available = Set(ids)
        return preferredModels.first(where: available.contains) ?? fallbackModel
    }

    func chat(system: String?, messages: [[String: Any]], maxTokens: Int) async throws -> String {
        var wire: [[String: Any]] = []
        if let system { wire.append(["role": "system", "content": system]) }
        for m in messages {
            wire.append(["role": (m["role"] as? String) ?? "user", "content": Self.convert(m["content"] ?? "")])
        }
        // Newer models spend part of this budget "thinking", so give them room.
        let body: [String: Any] = ["model": model, "messages": wire, "max_completion_tokens": max(maxTokens * 3, 800)]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
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
    static func availableModels(apiKey: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw error(status: status, data: data) }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return ((json?["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
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
        case 401: return .invalidKey
        case 429:
            if (message ?? "").lowercased().contains("quota") || (message ?? "").lowercased().contains("billing") {
                return .rejected("Your OpenAI account has no credit left. Add billing at platform.openai.com.")
            }
            return .rateLimited
        case 500...599: return .busy
        default: return .rejected(message ?? "OpenAI returned an error (\(status)).")
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
