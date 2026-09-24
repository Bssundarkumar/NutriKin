import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One AI suggestion: a kind of product to look for, and why it's a better choice for this family.
struct AlternativeIdea: Equatable {
    var search: String
    var why: String
}

/// The AI proposes *kinds* of better products; the app then finds real ones in the food database and scores
/// them against the family itself. The AI never decides what's safe.
enum AlternativeIdeasService {
    static func systemPrompt(product: Product, members: [Member], expectJSON: Bool = true) -> String {
        """
        You suggest healthier store-bought alternatives to a food a family just scanned.

        Family:
        \(AIContext.family(members))

        The scanned product:
        \(AIContext.product(product, members: members))

        Suggest exactly 3 different kinds of product that do the same job (same meal or craving) but suit this \
        family better: less sugar, salt or saturated fat, fewer additives, more fibre or protein, as their conditions need. \
        Each "search" is a short generic product name someone would type into a food database (no brand names). \
        NEVER suggest anything containing an ingredient a family member is allergic to. Real, common products only.
        \(expectJSON ? """

        Reply with JSON only, in exactly this shape:
        {"ideas":[{"search":"unsweetened almond butter","why":"No added sugar and mostly healthy fats."}]}
        """ : "")
        """
    }

    static func ideas(for product: Product, members: [Member], provider: AIProvider, client: LLM?) async throws -> [AlternativeIdea] {
        let request = "Suggest 3 better alternatives to \(product.name)."
        let text: String
        switch provider {
        case .apple:
            do {
                text = try await AppleAI.alternativeIdeasJSON(
                    system: systemPrompt(product: product, members: members, expectJSON: false), prompt: request)
            } catch {
                guard let client else { throw error }
                text = try await client.send(system: systemPrompt(product: product, members: members),
                                             content: [["type": "text", "text": request]], maxTokens: 600)
            }
        case .claude, .openai, .grok, .gemini:
            guard let client else { throw AnthropicClient.ClientError.invalidKey }
            text = try await client.send(system: systemPrompt(product: product, members: members),
                                         content: [["type": "text", "text": request]], maxTokens: 600)
        }
        return try AlternativeIdeasParser.parse(text, members: members)
    }

    /// Looks each idea up in Open Food Facts and keeps only real products that are usable, safe for the
    /// whole family and better than the scanned one.
    static func resolve(ideas: [AlternativeIdea], current: Product, members: [Member]) async -> [Alternative] {
        let service = ProductService()
        var pool: [Product] = []
        var whyByBarcode: [String: String] = [:]
        for (i, idea) in ideas.prefix(3).enumerated() {
            if i > 0 { try? await Task.sleep(for: .milliseconds(400)) }      // the food database limits searches
            guard let found = try? await service.search(idea.search, limit: 6) else { continue }
            for candidate in found.prefix(3) {
                guard candidate.code != current.barcode, let product = try? await service.fetch(barcode: candidate.code) else { continue }
                pool.append(product)
                whyByBarcode[product.barcode] = idea.why
            }
        }
        let ranked = AlternativeRanker().rank(current: current, candidates: pool, members: members, limit: 3,
                                              requireSimilarCategory: false)
        return ranked.map { var a = $0; a.why = whyByBarcode[a.product.barcode]; return a }
    }
}

enum AlternativeIdeasParser {
    private struct DTO: Decodable {
        struct Idea: Decodable { var search: String?; var why: String? }
        var ideas: [Idea]?
    }

    static func parse(_ reply: String, members: [Member]) throws -> [AlternativeIdea] {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let dto = try? JSONDecoder().decode(DTO.self, from: Data(reply[start...end].utf8)) else {
            throw AnthropicClient.ClientError.badResponse
        }
        var out: [AlternativeIdea] = []
        for raw in dto.ideas ?? [] {
            let search = (raw.search ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard search.count >= 3 else { continue }
            // Never even look up something that names a family member's allergen.
            let blocked = members.contains { !MealSafety.allergenHits(name: search, ingredients: [], for: $0).isEmpty }
            if blocked { continue }
            out.append(AlternativeIdea(search: String(search.prefix(60)),
                                       why: String((raw.why ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))))
            if out.count == 3 { break }
        }
        guard !out.isEmpty else { throw AnthropicClient.ClientError.badResponse }
        return out
    }
}
