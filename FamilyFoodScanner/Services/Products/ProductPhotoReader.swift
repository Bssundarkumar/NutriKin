import Foundation
import UIKit

/// What the AI read off a product's packaging. Every field is optional: the person
/// reviews and corrects it before anything is scored.
struct ProductReading: Equatable {
    var name: String?
    var brand: String?
    /// Digits printed under a barcode, if the photo shows them.
    var barcode: String?
    /// Ingredient list, with any "Contains" / "May contain" statement appended so allergy checks see it.
    var ingredientsText: String?
    var nutrition: Nutrition
    var notes: String?

    var foundAnything: Bool { name != nil || ingredientsText != nil || nutrition.hasAnyValue }
}

/// Reads packaging photos with the person's own AI key (Apple's on-device model can't see images).
enum ProductPhotoReader {
    static let systemPrompt = """
    \(AIGuardrails.taskRules)

    You read photos of food packaging for a family nutrition app. Copy what is PRINTED; never guess or invent.
    The photos may show the front of the pack, the ingredient list, the nutrition table, or a barcode.

    Reply with JSON only, in exactly this shape (use null for anything you cannot read clearly):
    {"name":"Oat biscuits","brand":"Acme","barcode_digits":"8901234567890","ingredients":"Wheat flour, sugar, ...","allergens_statement":"Contains: wheat, milk. May contain: nuts.","serving_size":"30 g","nutrition_basis":"per 100 g","nutrition":{"calories":450,"sugar_g":22,"carbs_g":65,"sodium_mg":320,"sat_fat_g":6,"protein_g":7},"notes":"what was blurry, cut off or unreadable"}

    Rules:
    - nutrition_basis is "per 100 g" or "per serving". Use the column the label shows; prefer per 100 g if both are shown.
    - Sodium is in mg. If only salt is listed, sodium_mg = salt in g x 400.
    - Keep the ingredient list exactly as printed, including percentages and E-numbers, in the original language.
    - If a value is not visible, use null. It is far better to leave a field empty than to guess.
    """

    static func read(images: [UIImage], client: LLM) async throws -> ProductReading {
        var content: [[String: Any]] = []
        for image in images.prefix(3) {
            guard let jpeg = PlateService.downscaledJPEG(image, maxSide: 1600, quality: 0.8) else { continue }
            content.append(["type": "image",
                            "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }
        guard !content.isEmpty else { throw AnthropicClient.ClientError.badResponse }
        content.append(["type": "text", "text": "Read this product's packaging."])
        let reply = try await client.send(system: systemPrompt, content: content, maxTokens: 1800)
        return try parse(reply)
    }

    /// Reads a label with Apple's on-device AI from the text the phone already recognised. Nothing leaves the phone.
    static func readOnDevice(rows: [String]) async throws -> ProductReading {
        let text = rows.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIFailure(message: "No text was found in the photo.") }
        return try parse(try await AppleAI.productLabelJSON(ocrText: text))
    }

    private struct DTO: Decodable {
        struct Nut: Decodable {
            var calories: Double?, sugarG: Double?, carbsG: Double?, sodiumMg: Double?, satFatG: Double?, proteinG: Double?
            enum CodingKeys: String, CodingKey {
                case calories, sugarG = "sugar_g", carbsG = "carbs_g", sodiumMg = "sodium_mg"
                case satFatG = "sat_fat_g", proteinG = "protein_g"
            }
        }
        var name: String?, brand: String?, ingredients: String?, notes: String?
        var barcodeDigits: String?, allergensStatement: String?, servingSize: String?, nutritionBasis: String?
        var nutrition: Nut?
        enum CodingKeys: String, CodingKey {
            case name, brand, ingredients, notes, nutrition
            case barcodeDigits = "barcode_digits", allergensStatement = "allergens_statement"
            case servingSize = "serving_size", nutritionBasis = "nutrition_basis"
        }
    }

    static func parse(_ reply: String) throws -> ProductReading {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let dto = try? JSONDecoder().decode(DTO.self, from: Data(reply[start...end].utf8)) else {
            throw AnthropicClient.ClientError.badResponse
        }
        func clean(_ s: String?, max: Int) -> String? {
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let safe = AIGuardrails.sanitize(t, max: max, keepNewlines: true)
            return safe.isEmpty || safe.lowercased() == "null" ? nil : safe
        }
        func clamp(_ v: Double?, _ hi: Double) -> Double? { v.map { min(max($0, 0), hi) } }

        var ingredients = clean(dto.ingredients, max: 3000)
        if let statement = clean(dto.allergensStatement, max: 400) {
            ingredients = [ingredients, statement].compactMap { $0 }.joined(separator: "\n")
        }
        let serving = clean(dto.servingSize, max: 30)
        let perServing = (dto.nutritionBasis ?? "").lowercased().contains("serving")
        let basis = perServing ? "per serving" + (serving.map { " (\($0))" } ?? "") : "per 100 g"
        let n = dto.nutrition
        let digits = (dto.barcodeDigits ?? "").filter(\.isNumber)

        return ProductReading(
            name: clean(dto.name, max: 80),
            brand: clean(dto.brand, max: 60),
            barcode: (8...14).contains(digits.count) ? digits : nil,
            ingredientsText: ingredients,
            nutrition: Nutrition(calories: clamp(n?.calories, 3000), sugarG: clamp(n?.sugarG, 500), carbsG: clamp(n?.carbsG, 500),
                                 sodiumMg: clamp(n?.sodiumMg, 20000), satFatG: clamp(n?.satFatG, 500), transFatG: nil,
                                 proteinG: clamp(n?.proteinG, 500), basis: basis),
            notes: clean(dto.notes, max: 200))
    }

    /// AI values win; anything the AI left blank keeps what the on-device reader found.
    static func merge(ai: ProductReading, ocr: ParsedLabel) -> ProductReading {
        var out = ai
        if out.ingredientsText == nil { out.ingredientsText = ocr.ingredientsText }
        var n = ai.nutrition
        let o = ocr.nutrition
        n.calories = n.calories ?? o.calories; n.sugarG = n.sugarG ?? o.sugarG; n.carbsG = n.carbsG ?? o.carbsG
        n.sodiumMg = n.sodiumMg ?? o.sodiumMg; n.satFatG = n.satFatG ?? o.satFatG; n.proteinG = n.proteinG ?? o.proteinG
        out.nutrition = n
        return out
    }
}
