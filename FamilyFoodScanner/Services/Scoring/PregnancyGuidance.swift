import Foundation

/// Foods commonly advised against in pregnancy by health services such as the NHS and ACOG: alcohol, raw or
/// undercooked animal foods, unpasteurised dairy, liver, high-mercury fish and lots of caffeine. It flags
/// products and meals; it is general guidance, not medical advice, and always points people to their midwife or doctor.
enum PregnancyGuidance {
    struct Rule {
        let id: String
        let title: String
        let terms: [String]
        /// The most a product with this can score for a pregnant person: 39 or lower is "Avoid", 40 to 69 "Caution".
        let cap: Int
        let severity: IngredientFlag.Severity
        let reason: String
    }

    static let rules: [Rule] = [
        Rule(id: "preg-alcohol", title: "Contains alcohol", terms: ["alcohol", "ethanol", "beer", "liqueur", "rum", "whisky", "whiskey", "brandy", "vodka", "red wine", "white wine", "rice wine", "cooking wine", "alcoholic beverage",
                     // Open Food Facts category names are plural
                     "alcoholic beverages", "beers", "wines", "spirits", "liqueurs", "cider", "ciders", "cocktails"],
             cap: 20, severity: .warning,
             reason: "Health services advise avoiding alcohol in pregnancy, as no amount is known to be safe. Ask your midwife or doctor if unsure."),
        Rule(id: "preg-raw", title: "Raw or undercooked", terms: ["raw egg", "raw eggs", "uncooked egg", "runny egg", "raw fish", "sushi", "sashimi", "raw oyster", "raw shellfish", "raw meat", "carpaccio", "tartare", "raw sprouts", "raw sprout"],
             cap: 35, severity: .warning,
             reason: "Raw or undercooked eggs, meat, fish and shellfish are commonly advised against in pregnancy because of food-poisoning risks. Well-cooked versions are usually fine."),
        Rule(id: "preg-unpasteurised", title: "Unpasteurised dairy", terms: ["unpasteurized", "unpasteurised", "raw milk"],
             cap: 35, severity: .warning,
             reason: "Unpasteurised milk and the cheeses made from it can carry listeria, and are commonly advised against in pregnancy."),
        Rule(id: "preg-liver", title: "Liver, pate or retinol", terms: ["liver", "pate", "p\u{00E2}t\u{00E9}", "pat\u{00E9}", "cod liver oil", "retinol"],
             cap: 55, severity: .warning,
             reason: "Liver, pate and cod liver oil are high in vitamin A, which is commonly advised to be limited in pregnancy."),
        Rule(id: "preg-mercury", title: "High-mercury fish", terms: ["shark", "swordfish", "king mackerel", "marlin", "tilefish", "orange roughy"],
             cap: 55, severity: .warning,
             reason: "These fish can be high in mercury and are commonly advised against in pregnancy."),
        Rule(id: "preg-caffeine", title: "Caffeine", terms: ["caffeine", "guarana", "energy drink", "coffee", "yerba mate", "matcha"],
             cap: 65, severity: .note,
             reason: "Caffeine is usually limited in pregnancy (often to about 200 mg a day, roughly two cups of coffee). Check your total for the day."),
    ]

    /// Lowercase text to search for a product: its name, ingredient text and Open Food Facts tags.
    static func searchText(for product: Product) -> String {
        let tags = (product.ingredientTags + product.categoryTags).map {
            $0.replacingOccurrences(of: "en:", with: "").replacingOccurrences(of: "-", with: " ")
        }
        return ([product.name, product.ingredientsText ?? ""] + tags).joined(separator: " , ").lowercased()
    }

    static func matches(text: String) -> [Rule] {
        let lower = text.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)
        return rules.filter { rule in rule.terms.contains { IngredientAnalyzer.regex(for: $0)?.firstMatch(in: lower, range: range) != nil } }
    }

    static func matches(in product: Product) -> [Rule] { matches(text: searchText(for: product)) }

    /// The same rules as flags for the ingredient alerts (shown only when someone in the family is pregnant).
    static var flags: [IngredientFlag] {
        rules.map { IngredientFlag($0.id, $0.title, $0.severity, .condition(.pregnancy), terms: $0.terms, reason: $0.reason) }
    }
}
