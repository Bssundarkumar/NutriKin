import Foundation
import UIKit

/// Sends a photo of a plate to the person's own AI and turns the answer into
/// editable estimates. The model only estimates; the person always reviews.
struct PlateService {
    var client: LLM

    /// Reference portions the AI is told to anchor on. Includes Indian staples, since many families eat them.
    static let portionAnchors = """
    a cup of cooked rice or pasta is about 160 g; a roti or chapati about 40 g; a paratha about 80 g; a dosa about 80 g; \
    an idli about 45 g; a katori (small bowl) of dal, curry or sabzi about 150 g; a cup of curd or yoghurt 245 g; \
    a boiled egg 50 g; a slice of bread 30 g; a palm-sized piece of cooked chicken, meat or fish about 100 g; \
    a tablespoon of oil, ghee or butter 14 g; a teaspoon of sugar 4 g; a glass of milk, juice or lassi 240 g
    """

    /// The nutrients asked for per 100 g, in the order they appear in the reply.
    static let nutrientList = "calories (kcal), protein_g, carbs_g, sugar_g, fiber_g, fat_g, sat_fat_g and sodium_mg"

    static let allergenList = "peanuts, nuts, milk, gluten, eggs, soybeans, fish, crustaceans, sesame"

    static func jsonShape(includePlateSize: Bool) -> String {
        let size = includePlateSize ? #""plate_diameter_cm":26,"# : ""
        return #"{\#(size)"items":[{"name":"Basmati rice","grams":180,"per_100g":{"calories":130,"protein_g":2.7,"carbs_g":28,"sugar_g":0.1,"fiber_g":0.4,"fat_g":0.3,"sat_fat_g":0.1,"sodium_mg":250},"confidence":"high","allergens":[],"alternatives":[]}],"note":"one short sentence about the biggest uncertainty"}"#
    }

    /// The full prompt for a photo of a plate. `plateDiameterCm` nil means the person doesn't know it,
    /// so the AI estimates the plate size first.
    static func systemPrompt(plateDiameterCm: Int?) -> String {
        let scale: String
        if let cm = plateDiameterCm {
            scale = "The plate is \(cm) cm across. Use that as your ruler: compare how much of the plate each food covers, and how high it is piled, to work out how much food there is."
        } else {
            scale = "The plate's size is unknown. First estimate its diameter in cm from the photo, using cues such as cutlery, a glass, hands or the table edge and typical sizes (dinner plate 24 to 28 cm, side plate 18 to 20 cm, bowl 15 to 20 cm), then use it as your ruler. Report it as plate_diameter_cm."
        }
        return """
        \(AIGuardrails.taskRules)

        You are a registered-dietitian-level nutrition estimator for a family health app. You estimate what is on ONE plate from a photo, ideally taken from above.

        SCALE. \(scale)

        METHOD
        1. Identify every distinct food. Split mixed dishes into their main parts (for example biryani: rice, chicken, and the oil or ghee it was cooked in). Include sauces, chutneys, dressings, cooking fat and drinks. Skip tiny garnishes. At most 10 items.
        2. Estimate the cooked weight in grams AS SERVED. Useful anchors: \(portionAnchors).
        3. Give typical nutrition PER 100 g of the food as prepared and served (cooked, not raw), using standard food-composition values (USDA, Indian Food Composition Tables): \(nutrientList). Count the fat and salt that cooking usually adds: fried, buttery, creamy, coconut-milk and restaurant dishes are richer than plain home cooking, and cooked dishes normally contain salt, so never use raw-ingredient sodium.
        4. Keep the numbers consistent: calories per 100 g should be close to 4 x protein + 4 x (carbs minus fibre) + 2 x fibre + 9 x fat.
        5. Never invent food that is not visible. If you cannot tell what something is, name your best guess and set confidence "low". Set confidence "low" or "medium" when the amount is hard to judge (food hidden under other food, deep bowls, sauces).
        6. Only list actual food and drink. Never list the plate, bowl, tray, board, cutlery, napkin, table, hands or anything else the food sits on or is eaten with.
        7. When you're not sure exactly what a food is (confidence "low" or "medium"), put your 1 or 2 next-best guesses in "alternatives" (just the names, most likely first), so the person can pick the right one instead of you guessing wrong silently. Leave "alternatives" empty when confidence is "high".
        8. CHECK FIRST: does this photo actually show food on a plate, bowl or similar, ready to eat? If it shows a landscape, scenery, sky, trees, a person, an animal, an object, a screenshot, or anything else that is not a meal, you MUST reply {"items":[],"note":"No food found in the photo."} and stop there. Do not describe clouds, trees, a sky or other non-food shapes as if they were food, even loosely or as a joke.
        List possible allergens only from: \(allergenList).

        Reply with JSON only, no other text, in exactly this shape:
        \(jsonShape(includePlateSize: plateDiameterCm == nil))
        If the photo does not show food, reply {"items":[],"note":"No food found in the photo."}
        """
    }

    /// The prompt for a written description ("2 rotis, a bowl of dal"). Shorter, so it also fits Apple's small
    /// on-device model. `structuredOutput` is true when the reply format is enforced separately.
    static func descriptionPrompt(plateDiameterCm: Int?, structuredOutput: Bool) -> String {
        let scale = plateDiameterCm.map { "The plate is \($0) cm across." } ?? "Assume a normal dinner plate, about 26 cm across."
        return """
        \(AIGuardrails.taskRules)

        You are a registered-dietitian-level nutrition estimator for a family health app. \(scale) The person lists what they ate, sometimes with amounts ("2 rotis", "small bowl of dal").

        For each food: estimate a realistic cooked weight in grams as served (a normal single serving if no amount is given; anchors: \(portionAnchors)) and typical nutrition per 100 g of the food as prepared: \(nutrientList). Count the oil, ghee, butter and salt that cooking usually adds. Keep calories consistent with the macros (about 4 x protein + 4 x carbs + 9 x fat, fibre counting half). Split mixed dishes into parts. Never invent foods that were not listed; mark confidence "low" when unsure, and when unsure put 1 or 2 next-best guesses in "alternatives". List possible allergens only from: \(allergenList).
        \(structuredOutput ? "" : "\nReply with JSON only, in exactly this shape:\n\(jsonShape(includePlateSize: false))")
        """
    }

    func analyze(image: UIImage, plateDiameterCm: Int?) async throws -> PlateAnalysis {
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

    /// Apple's on-device AI can't see photos, so it estimates from a description of the foods (recognised from
    /// the photo on the phone, then confirmed or edited by the person). Nothing leaves the phone.
    static func estimateOnDevice(foods: String, plateDiameterCm: Int?) async throws -> PlateAnalysis {
        let system = descriptionPrompt(plateDiameterCm: plateDiameterCm, structuredOutput: true)
        return try PlateParser.parse(try await AppleAI.plateJSON(system: system, foods: foods))
    }

    /// Estimates from a typed description ("2 rotis and a bowl of dal") with whichever AI the person has.
    /// The description is screened first, and the estimate is always shown for the person to confirm.
    static func estimateFromDescription(_ text: String, provider: AIProvider, client: LLM?) async throws -> PlateAnalysis {
        let foods: String
        switch AIGuardrails.screen(text) {
        case .allow(let clean): foods = clean
        case .notice(_, let reply): throw AIFailure(message: reply)
        }
        if provider == .apple {
            do { return try await estimateOnDevice(foods: foods, plateDiameterCm: nil) }
            catch { guard client != nil else { throw error } }      // fall back to the person's own key
        }
        guard let client else { throw AnthropicClient.ClientError.invalidKey }
        let system = descriptionPrompt(plateDiameterCm: nil, structuredOutput: false)
        let reply = try await client.send(system: system,
                                          content: [["type": "text", "text": AIGuardrails.untrusted(foods, tag: "foods")]], maxTokens: 900)
        return try PlateParser.parse(reply)
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
                var fiberG: Double?, fatG: Double?
                enum CodingKeys: String, CodingKey {
                    case calories, sugarG = "sugar_g", carbsG = "carbs_g", sodiumMg = "sodium_mg"
                    case satFatG = "sat_fat_g", proteinG = "protein_g", fiberG = "fiber_g", fatG = "fat_g"
                }
            }
            var name: String?
            var grams: Double?
            var per100g: Per100?
            var confidence: String?
            var allergens: [String]?
            var alternatives: [String]?
            enum CodingKeys: String, CodingKey { case name, grams, per100g = "per_100g", confidence, allergens, alternatives }
        }
        var items: [Item]?
        var note: String?
        var plateDiameterCm: Double?
        enum CodingKeys: String, CodingKey { case items, note, plateDiameterCm = "plate_diameter_cm" }
    }

    /// Calories that can be worked out from the macros: 4 per g of protein and of carbs (fibre counts 2), 9 per g of fat.
    static func macroCalories(_ p: PlateItem.Per100g) -> Double {
        4 * p.proteinG + 4 * max(p.carbsG - p.fiberG, 0) + 2 * p.fiberG + 9 * p.fatG
    }

    /// If reported calories are more than about a third away from what the macros add up to, pulls them halfway
    /// together. Returns true when it changed anything.
    @discardableResult
    static func reconcile(_ p: inout PlateItem.Per100g) -> Bool {
        let derived = macroCalories(p)
        guard derived > 20 else { return false }
        if p.calories <= 0 { p.calories = derived; return true }
        let ratio = p.calories / derived
        guard ratio < 0.65 || ratio > 1.35 else { return false }
        p.calories = ((p.calories + derived) / 2).rounded()
        return true
    }

    /// The AI sometimes mistakes what's under or around the food (a board, the table, a hand, cutlery) for a
    /// food item. This catches the obvious ones so they never reach the log or a score, without blocking a
    /// legitimate dish that happens to share a word (a "wooden bowl of curry" still starts with "curry").
    private static let nonFoodTerms: Set<String> = [
        "wood", "wooden", "wooden board", "wooden plate", "cutting board", "chopping board", "table", "tablecloth",
        "placemat", "napkin", "tissue", "plate", "bowl", "glass", "cup", "mug", "cutlery", "fork", "spoon", "knife",
        "chopsticks", "hand", "hands", "finger", "fingers", "background", "wall", "floor", "phone", "plastic",
        "metal", "tray", "basket", "paper", "foil", "cloth", "surface", "counter", "countertop",
        // Scenery and other non-food things a photo taken outdoors, or of the wrong subject, might contain.
        "sky", "skies", "cloud", "clouds", "tree", "trees", "grass", "leaf", "leaves", "mountain", "mountains",
        "hill", "hills", "building", "buildings", "road", "street", "car", "vehicle", "water", "lake", "river",
        "sea", "ocean", "sand", "beach", "sun", "sunset", "flower", "flowers", "bird", "birds", "animal", "dog",
        "cat", "person", "people", "face", "clothing", "shirt", "shoe", "shoes", "furniture", "chair", "sofa",
        "bed", "ceiling", "window", "door", "screen", "book", "toy", "plant", "pot", "vase",
    ]

    private static func isPlausibleFood(_ name: String) -> Bool {
        !nonFoodTerms.contains(name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func parse(_ reply: String) throws -> PlateAnalysis {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let dto = try? JSONDecoder().decode(DTO.self, from: Data(reply[start...end].utf8)) else {
            throw AnthropicClient.ClientError.badResponse
        }
        func clamp(_ v: Double?, _ hi: Double) -> Double { min(max(v ?? 0, 0), hi) }

        let items: [PlateItem] = (dto.items ?? []).prefix(8).compactMap { raw in
            let name = (raw.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, isPlausibleFood(name), let grams = raw.grams, grams > 0, let p = raw.per100g, let kcal = p.calories else { return nil }
            var per100 = PlateItem.Per100g(calories: clamp(kcal, 900), sugarG: clamp(p.sugarG, 100), carbsG: clamp(p.carbsG, 100),
                                           sodiumMg: clamp(p.sodiumMg, 5000), satFatG: clamp(p.satFatG, 100), proteinG: clamp(p.proteinG, 100),
                                           fiberG: clamp(p.fiberG, 100), fatG: clamp(p.fatG, 100))
            var confidence = PlateItem.Confidence(rawValue: (raw.confidence ?? "").lowercased()) ?? .medium
            // Only when the AI gave the macros to check against: an estimate whose calories don't match its own
            // protein, carbs and fat is corrected, and its confidence lowered.
            if p.fatG != nil, p.proteinG != nil, p.carbsG != nil, reconcile(&per100), confidence == .high { confidence = .medium }
            let alternatives = (raw.alternatives ?? [])
                .map { AIGuardrails.sanitize($0, max: 60) }
                .filter { !$0.isEmpty && $0.lowercased() != name.lowercased() }
            return PlateItem(
                name: AIGuardrails.sanitize(name, max: 60),
                grams: min(max(grams, 5), 1500),
                per100g: per100,
                confidence: confidence,
                allergens: (raw.allergens ?? []).compactMap { Allergen(rawValue: $0.lowercased()) },
                alternatives: Array(alternatives.prefix(2))
            )
        }
        let note = dto.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let plate = dto.plateDiameterCm.flatMap { PlateMeasure.isPlausible($0) ? Int($0.rounded()) : nil }
        return PlateAnalysis(items: items, note: (note?.isEmpty == false) ? note : nil, estimatedPlateCm: plate)
    }
}
