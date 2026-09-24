import Foundation

/// Turns the raw ingredient paragraph from a label into a clean list, in label
/// order (labels list ingredients from largest to smallest amount).
///
/// Real labels are messy: decimal commas ("7,4%"), nested brackets
/// ("Broth (water, salt, ...)"), unbalanced brackets, SHOUTED allergens
/// (NOISETTES, LAIT), markup underscores and a trailing claim like "Sans gluten."
enum IngredientParser {
    static func items(from text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        let chars = Array(text)

        for (i, ch) in chars.enumerated() {
            switch ch {
            case "(", "[", "{": depth += 1
            case ")", "]", "}": depth = max(0, depth - 1)
            default: break
            }

            if depth == 0, isSeparator(ch, at: i, in: chars) {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        parts.append(current)

        return parts.compactMap(tidy)
    }

    // MARK: - Splitting

    private static func isSeparator(_ ch: Character, at i: Int, in chars: [Character]) -> Bool {
        switch ch {
        case ";": return true
        case ",":
            // A comma between two digits is a decimal comma ("7,4%"), not a separator.
            let prev = i > 0 ? chars[i - 1] : " "
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            return !(prev.isNumber && next.isNumber)
        case ".":
            // A full stop that ends a sentence ("... vanilline. Sans gluten.").
            let prev = i > 0 ? chars[i - 1] : " "
            guard !prev.isNumber, i + 1 < chars.count, chars[i + 1] == " " else { return false }
            let rest = chars[(i + 1)...].first(where: { !$0.isWhitespace })
            return rest?.isUppercase == true
        default: return false
        }
    }

    // MARK: - Tidying one item

    private static func tidy(_ raw: String) -> String? {
        var s = raw
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "*", with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,;:"))

        // Drop a leading "Ingredients:" heading (any language that ends in a colon).
        let lower = s.lowercased()
        for heading in ["ingredients:", "ingrédients:", "ingredientes:", "zutaten:", "ingredienti:"] where lower.hasPrefix(heading) {
            s = String(s.dropFirst(heading.count)).trimmingCharacters(in: .whitespaces)
        }
        guard s.contains(where: \.isLetter) else { return nil }

        // Tone down shouting: lowercase words that are ALL capital letters
        // (NOISETTES -> noisettes) but leave codes like "E150d" alone.
        s = s.split(separator: " ", omittingEmptySubsequences: true).map { word -> String in
            let w = String(word)
            let letters = w.filter(\.isLetter)
            let lettersOnly = w.allSatisfy(\.isLetter)
            return (lettersOnly && letters.count > 1 && w == w.uppercased()) ? w.lowercased() : w
        }.joined(separator: " ")

        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
