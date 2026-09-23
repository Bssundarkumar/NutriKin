import Foundation
import Supabase

/// The one shared Supabase client, plus the retry helper every store uses.
enum Backend {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            // Postgres timestamptz comes back as ISO 8601, with or without fractional seconds.
            let s = try decoder.singleValueContainer().decode(String.self)
            let plain = ISO8601DateFormatter()
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date: \(s)"))
        }
        return d
    }()

    static let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.anonKey,
        options: SupabaseClientOptions(db: .init(encoder: encoder, decoder: decoder))
    )

    /// Retries a network call a couple of times with a short backoff.
    /// The iOS Simulator's HTTP/3 stack occasionally stalls a connection
    /// outright (a known simulator bug); a real phone on a flaky network
    /// benefits from the same retry.
    @discardableResult
    static func withRetry<T>(attempts: Int = 3, _ operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
                }
            }
        }
        throw lastError ?? CancellationError()
    }
}
