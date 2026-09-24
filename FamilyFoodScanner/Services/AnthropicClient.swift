import Foundation

/// Talks straight to the Anthropic Messages API with the user's own key.
/// The key is only ever sent to api.anthropic.com.
struct AnthropicClient {
    let apiKey: String
    static let model = "claude-sonnet-5"

    enum ClientError: LocalizedError, Equatable {
        case invalidKey
        case rateLimited
        case busy
        case rejected(String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .invalidKey: "That key wasn't accepted. Check it and try again."
            case .rateLimited: "Too many requests right now. Wait a minute and try again."
            case .busy: "The AI service is busy. Try again in a moment."
            case .rejected(let message): message
            case .badResponse: "Couldn't read the AI's answer. Try again."
            }
        }
    }

    /// Sends one user turn (text and/or images) and returns the reply text.
    func send(system: String?, content: [[String: Any]], maxTokens: Int) async throws -> String {
        try await chat(system: system, messages: [["role": "user", "content": content]], maxTokens: maxTokens)
    }

    /// Sends a whole conversation (alternating user/assistant messages, starting with the user).
    func chat(system: String?, messages: [[String: Any]], maxTokens: Int) async throws -> String {
        var body: [String: Any] = [
            "model": Self.model,
            "max_tokens": maxTokens,
            "messages": messages,
        ]
        if let system { body["system"] = system }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Self.error(status: status, data: data) }
        return try Self.replyText(from: data)
    }

    /// A tiny request that proves the key works (costs a fraction of a cent).
    func verify() async throws {
        _ = try await send(system: nil, content: [["type": "text", "text": "Reply with the word ok."]], maxTokens: 5)
    }

    static func error(status: Int, data: Data) -> ClientError {
        switch status {
        case 401, 403: return .invalidKey
        case 429: return .rateLimited
        case 500...599: return .busy
        default:
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            return .rejected(message ?? "The AI service returned an error (\(status)).")
        }
    }

    static func replyText(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]] else { throw ClientError.badResponse }
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        guard !text.isEmpty else { throw ClientError.badResponse }
        return text
    }
}
