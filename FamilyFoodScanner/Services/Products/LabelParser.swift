import Foundation

/// What was read from a photo of a package label.
struct ParsedLabel: Equatable {
    /// The ingredient list, plus any "Contains ..." / "May contain ..." allergen
    /// statements, so the allergy checks see them.
    var ingredientsText: String?
    var nutrition: Nutrition
    var foundAnything: Bool { ingredientsText != nil || nutrition.hasAnyValue }
}

extension Nutrition {
    var hasAnyValue: Bool {
        [calories, sugarG, carbsG, sodiumMg, satFatG, transFatG, proteinG].contains { $0 != nil }
    }
}

/// Pulls the ingredient list and nutrition facts out of recognised text lines.
/// Works on English, French, Spanish, German and Italian labels and on the
/// common Indian layout ("Total Carbohydrate", "Added Sugars", "Sodium (mg)").
/// Text recognition is imperfect, so the result is always shown to the person
/// to correct before anything is scored.
enum LabelParser {
    static func parse(_ rows: [String]) -> ParsedLabel {
        let rows = rows.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let block = extractIngredients(rows)
        var ingredients = block?.text
        let statements = allergenStatements(rows)
        if !statements.isEmpty {
            ingredients = ((ingredients ?? "") + ". " + statements.joined(separator: ". ")).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        }
        // Nutrition values come only from rows outside the ingredient paragraph
        // (which is full of numbers like "13%" and "INS 500").
        let tableRows = rows.enumerated().filter { !(block?.rows.contains($0.offset) ?? false) }.map(\.element)
        return ParsedLabel(ingredientsText: ingredients?.isEmpty == false ? ingredients : nil,
                           nutrition: extractNutrition(tableRows))
    }

    // MARK: - Ingredients

    private static let headingPattern =
        #"(?i)\b(ingredients?|ingr[ée]dients?|ingredientes?|zutaten|ingredienti|composition|composici[oó]n)\b\s*[:：\-–]?\s*(.*)$"#

    /// Rows that end the ingredient paragraph.
    private static let stopPattern = #"(?i)^\s*(nutrition|nutritional|nutrient|valeurs?\s+nutri|informaci[oó]n\s+nutri|n[aä]hrwert|typical\s+values|per\s+100|energy|[ée]nergie|energ[ií]a|brennwert|best\s+before|use\s+by|store|storage|keep|manufactured|marketed|packed|net\s+(wt|weight|qty|quantity|content)|mrp|batch|lot\b|fssai|customer\s+care|www\.|barcode|veg\b|non[- ]veg|allergen|contains|may\s+contain|contient|peut\s+contenir|contiene|puede\s+contener|enth[aä]lt|kann\s+.*enthalten)"#

    private static func extractIngredients(_ rows: [String]) -> (text: String, rows: Range<Int>)? {
        guard let regex = try? NSRegularExpression(pattern: headingPattern) else { return nil }
        for (i, row) in rows.enumerated() {
            let range = NSRange(row.startIndex..., in: row)
            guard let m = regex.firstMatch(in: row, range: range), let r = Range(m.range(at: 2), in: row) else { continue }
            // Skip nutrition-table headers like "Composition per 100 g".
            let after = String(row[r])
            if after.lowercased().hasPrefix("per 100") || after.lowercased().hasPrefix("nutri") { continue }

            var parts = [after]
            var last = i
            for (offset, next) in rows.enumerated().dropFirst(i + 1).prefix(30) {
                if next.range(of: stopPattern, options: .regularExpression) != nil { break }
                parts.append(next)
                last = offset
            }
            let joined = parts.reduce(into: "") { acc, part in
                if acc.hasSuffix("-") { acc.removeLast(); acc += part }          // hyphenated line break
                else { acc += (acc.isEmpty ? "" : " ") + part }
            }
            let text = joined.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:"))
            return text.isEmpty ? nil : (text, i..<(last + 1))
        }
        return nil
    }

    /// "Contains soy." / "May contain traces of nuts." lines, wherever they are.
    private static func allergenStatements(_ rows: [String]) -> [String] {
        let pattern = #"(?i)^\s*(allergen(s| advice| information)?|allergy advice|contains|may contain|contient|peut contenir|traces?|contiene|puede contener|enth[aä]lt|kann [^:]* enthalten)\b.*"#
        return rows.filter { $0.range(of: pattern, options: .regularExpression) != nil }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .")) }
    }

    // MARK: - Nutrition

    private static func extractNutrition(_ rows: [String]) -> Nutrition {
        let all = rows.joined(separator: "\n").lowercased()
        let basis: String
        if all.range(of: #"per\s*100\s*(g|ml)|100\s*(g|ml)\b"#, options: .regularExpression) != nil { basis = "per 100 g" }
        else if all.range(of: #"per\s+serving|serving size|per\s+portion|par\s+portion"#, options: .regularExpression) != nil { basis = "per serving" }
        else { basis = "as printed" }

        func value(_ label: String, excluding: String? = nil) -> (number: Double, unit: String)? {
            for row in rows {
                let low = row.lowercased()
                // A nutrition row starts with its label ("of which sugars", "dont sucres", "Total Fat").
                guard let hit = low.range(of: label, options: .regularExpression),
                      low.distance(from: low.startIndex, to: hit.lowerBound) <= 24 else { continue }
                if let excluding, low.range(of: excluding, options: .regularExpression) != nil { continue }
                if let hit = firstNumber(in: low, after: label) { return hit }
            }
            return nil
        }

        var calories: Double?
        for row in rows where row.range(of: #"(?i)energy|[ée]nergie|energ[ií]a|brennwert|calories|kcal"#, options: .regularExpression) != nil {
            let low = row.lowercased()
            if let m = low.range(of: #"(\d+(?:[.,]\d+)?)\s*kcal"#, options: .regularExpression),
               let n = number(String(low[m]).replacingOccurrences(of: "kcal", with: "")) { calories = n; break }
            if let m = low.range(of: #"(\d+(?:[.,]\d+)?)\s*kj"#, options: .regularExpression),
               let n = number(String(low[m]).replacingOccurrences(of: "kj", with: "")) { calories = (n / 4.184).rounded(); break }
        }

        let sat = value(#"saturat|satur[ée]s?|saturadas?|ges[aä]ttigte"#)
        let trans = value(#"\btrans\b"#)
        let carbs = value(#"carbohydrate|carbs|glucides|hidratos|kohlenhydrate|carboidrat"#, excluding: #"sugar|sucre"#)
            ?? value(#"carbohydrate|carbs|glucides|hidratos|kohlenhydrate|carboidrat"#)
        let sugars = value(#"total sugars?|sugars?|sucres?|az[uú]cares|zucker|zuccheri"#, excluding: #"added"#)
            ?? value(#"added sugars?"#)
        let protein = value(#"protein|prot[ée]ines?|prote[ií]nas?|eiwei[sß]|proteine"#)
        let sodium = value(#"sodium|sodio|natrium"#)
        let salt = value(#"\bsalt\b|\bsel\b|\bsal\b|\bsalz\b|\bsale\b"#, excluding: #"sodium"#)

        var sodiumMg: Double?
        if let sodium { sodiumMg = sodium.unit == "g" ? sodium.number * 1000 : sodium.number }
        else if let salt { sodiumMg = (salt.unit == "mg" ? salt.number / 1000 : salt.number) * 400 }   // salt g x 400 = sodium mg

        func sane(_ v: (number: Double, unit: String)?, max: Double = 1000) -> Double? {
            guard let v, v.number >= 0, v.number <= max else { return nil }
            return v.number
        }
        return Nutrition(calories: calories.flatMap { $0 <= 2500 ? $0 : nil },
                         sugarG: sane(sugars, max: 100_000), carbsG: sane(carbs, max: 100_000),
                         sodiumMg: sodiumMg.flatMap { $0 <= 100_000 ? $0 : nil },
                         satFatG: sane(sat, max: 100_000), transFatG: sane(trans, max: 100_000),
                         proteinG: sane(protein, max: 100_000),
                         basis: basis)
    }

    /// The first number after `label` in `text`, with its unit ("g", "mg", ...).
    private static func firstNumber(in text: String, after label: String) -> (number: Double, unit: String)? {
        guard let labelRange = text.range(of: label, options: .regularExpression) else { return nil }
        let tail = String(text[labelRange.upperBound...])
        guard let m = tail.range(of: #"(\d+(?:[.,]\d+)?)\s*(mg|g|kcal|kj|µg|mcg)?"#, options: .regularExpression) else { return nil }
        let hit = String(tail[m])
        guard let n = number(hit) else { return nil }
        let unit = hit.range(of: #"(mg|kcal|kj|µg|mcg|g)$"#, options: .regularExpression).map { String(hit[$0]) } ?? "g"
        return (n, unit)
    }

    /// "12,5" or "12.5" (optionally followed by a unit) -> 12.5
    private static func number(_ s: String) -> Double? {
        guard let m = s.range(of: #"\d+(?:[.,]\d+)?"#, options: .regularExpression) else { return nil }
        return Double(String(s[m]).replacingOccurrences(of: ",", with: "."))
    }
}
