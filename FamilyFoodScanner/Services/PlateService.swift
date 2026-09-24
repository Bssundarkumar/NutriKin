import Foundation
import UIKit

/// Sends a photo of a plate to the person's own AI and turns the answer into
/// editable estimates. The model only estimates; the person always reviews.
struct PlateService {
    var client: LLM

    static func systemPrompt(plateDiameterCm: Int) -> String {
        """
        You estimate the nutrition of a plate of food for a family health app. The photo shows one plate, \
        ideally from above. The plate is \(plateDiameterCm) cm across: use that as the scale reference, together \
        with how large the plate looks in the frame, to judge distance and how much food is on it.

        Identify each distinct food (at most 8). For each give: the cooked weight in grams as served, and typical \
        nutrition per 100 g. If you cannot tell what something is, give your best guess and mark confidence "low".
        List possible allergens only from: peanuts, nuts, milk, gluten, eggs, soybeans, fish, crustaceans, sesame.

        Reply with JSON only, no other text, in exactly this shape:
        {"items":[{"name":"Rice","grams":180,"per_100g":{"calories":130,"sugar_g":0.1,"carbs_g":28,"sodium_mg":1,"sat_fat_g":0.1,"protein_g":2.7},"confidence":"high","allergens":[]}],"note":"one short sentence about the biggest uncertainty"}
        If the photo does not show food, reply {"items":[],"note":"No food found in the photo."}
        """
    }

    func analyze(image: UIImage, plateDiameterCm: Int) async throws -> PlateAnalysis {
        guard let jpeg = Self.downscaledJPEG(image) else { throw AnthropicClient.ClientError.badResponse }
        let content: [[String: Any]] = [
            ["type": "image",
             "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
            ["type": "text", "text": "Estimate the food on this plate."],
        ]
        let text = try await client.send(
            system: Self.systemPrompt(plateDiameterCm: plateDiameterCm), content: content, maxTokens: 1500)
        return try PlateParser.parse(text)
    }

    /// Keeps uploads small: at most 1280 px on the long side.
    static func downscaledJPEG(_ image: UIImage, maxSide: CGFloat = 1280, quality: CGFloat = 0.75) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: quality)
    }
}

/// Turns the AI's JSON into checked numbers. Never trusts the model: values are
/// clamped to plausible ranges and unusable rows are dropped.
enum PlateParser {
    private struct DTO: Decodable {
        struct Item: Decodable {
            struct Per100: Decodable {
                var calories: Double?, sugarG: Double?, carbsG: Double?
                var sodiumMg: Double?, satFatG: Double?, proteinG: Double?
                enum CodingKeys: String, CodingKey {
                    case calories, sugarG = "sugar_g", carbsG = "carbs_g", sodiumMg = "sodium_mg"
                    case satFatG = "sat_fat_g", proteinG = "protein_g"
                }
            }
            var name: String?
            var grams: Double?
            var per100g: Per100?
            var confidence: String?
            var allergens: [String]?
            enum CodingKeys: String, CodingKey { case name, grams, per100g = "per_100g", confidence, allergens }
        }
        var items: [Item]?
        var note: String?
    }

    static func parse(_ reply: String) throws -> PlateAnalysis {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let dto = try? JSONDecoder().decode(DTO.self, from: Data(reply[start...end].utf8)) else {
            throw AnthropicClient.ClientError.badResponse
        }
        func clamp(_ v: Double?, _ hi: Double) -> Double { min(max(v ?? 0, 0), hi) }

        let items: [PlateItem] = (dto.items ?? []).prefix(8).compactMap { raw in
            let name = (raw.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let grams = raw.grams, grams > 0, let p = raw.per100g, let kcal = p.calories else { return nil }
            return PlateItem(
                name: String(name.prefix(60)),
                grams: min(max(grams, 5), 1500),
                per100g: .init(calories: clamp(kcal, 900), sugarG: clamp(p.sugarG, 100), carbsG: clamp(p.carbsG, 100),
                               sodiumMg: clamp(p.sodiumMg, 5000), satFatG: clamp(p.satFatG, 100), proteinG: clamp(p.proteinG, 100)),
                confidence: PlateItem.Confidence(rawValue: (raw.confidence ?? "").lowercased()) ?? .medium,
                allergens: (raw.allergens ?? []).compactMap { Allergen(rawValue: $0.lowercased()) }
            )
        }
        let note = dto.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PlateAnalysis(items: items, note: (note?.isEmpty == false) ? note : nil)
    }
}
