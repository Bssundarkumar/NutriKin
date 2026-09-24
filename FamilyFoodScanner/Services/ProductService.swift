import Foundation

enum ProductError: LocalizedError {
    case notFound
    case badResponse
    /// The database is overloaded right now (Open Food Facts limits searches).
    case busy

    var errorDescription: String? {
        switch self {
        case .notFound: "This product isn't in the database yet. Try photographing the label."
        case .badResponse: "Couldn't reach the product database. Check your connection."
        case .busy: "The food database is busy right now. Wait a moment and try again."
        }
    }
}

/// One possible match from a name search, shown for the person to confirm.
struct ProductCandidate: Identifiable, Hashable {
    var code: String
    var name: String
    var brand: String?
    var quantity: String?
    var imageURL: URL?
    var id: String { code }
}

/// Looks products up in Open Food Facts (free, open data).
/// Docs: https://openfoodfacts.github.io/openfoodfacts-server/api/
struct ProductService {
    // Open Food Facts asks every app to identify itself. Put your real contact here.
    private let userAgent = "FamilyFoodScanner/0.1 (bssundarkumar@gmail.com)"

    /// Searches the database by product name (for when there's no barcode).
    /// Most popular matches first. Retries briefly if the search is busy.
    func search(_ text: String, limit: Int = 12) async throws -> [ProductCandidate] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        var comps = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(limit)),
            URLQueryItem(name: "sort_by", value: "unique_scans_n"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,quantity,image_front_small_url"),
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        var lastStatus = 0
        for attempt in 0..<3 {
            let (data, response) = try await URLSession.shared.data(for: request)
            lastStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            if lastStatus == 200 { return try Self.decodeCandidates(data) }
            guard lastStatus == 503 || lastStatus == 429 else { break }
            try? await Task.sleep(for: .milliseconds(700 * (attempt + 1)))
        }
        throw (lastStatus == 503 || lastStatus == 429) ? ProductError.busy : ProductError.badResponse
    }

    /// Pure, so it can be tested without the network.
    static func decodeCandidates(_ data: Data) throws -> [ProductCandidate] {
        struct Response: Decodable { let products: [Row]? }
        struct Row: Decodable {
            let code: String?
            let product_name: String?
            let brands: String?
            let quantity: String?
            let image_front_small_url: String?
        }
        let rows = try JSONDecoder().decode(Response.self, from: data).products ?? []
        return rows.compactMap { r in
            let name = (r.product_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let code = r.code, code.allSatisfy(\.isNumber), code.count >= 8, !name.isEmpty else { return nil }
            let brand = r.brands?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
            let qty = r.quantity?.trimmingCharacters(in: .whitespaces)
            return ProductCandidate(code: code, name: name,
                                    brand: (brand?.isEmpty == false) ? brand : nil,
                                    quantity: (qty?.isEmpty == false) ? qty : nil,
                                    imageURL: r.image_front_small_url.flatMap(URL.init(string:)))
        }
    }

    func fetch(barcode: String) async throws -> Product {
        let code = barcode.filter(\.isNumber)
        var comps = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json")!
        comps.queryItems = [URLQueryItem(
            name: "fields",
            value: "product_name,brands,image_front_small_url,ingredients_text,ingredients_tags,ingredients,additives_tags,allergens_tags,serving_size,nutriments"
        )]
        var request = URLRequest(url: comps.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw ProductError.notFound }
        guard status == 200 else { throw ProductError.badResponse }

        let decoded = try JSONDecoder().decode(OFFResponse.self, from: data)
        guard decoded.status == 1, let p = decoded.product else { throw ProductError.notFound }
        return p.toProduct(barcode: code)
    }
}

// MARK: - Open Food Facts response shapes

private struct OFFResponse: Decodable {
    let status: Int
    let product: OFFProduct?
}

private struct OFFProduct: Decodable {
    let product_name: String?
    let brands: String?
    let image_front_small_url: String?
    let ingredients_text: String?
    let allergens_tags: [String]?
    let ingredients_tags: [String]?
    let ingredients: [OFFIngredient]?
    let additives_tags: [String]?
    let serving_size: String?
    let nutriments: Nutriments?

    func toProduct(barcode: String) -> Product {
        let nut = nutriments?.values ?? [:]
        // Prefer per-serving values when the product has them.
        let useServing = nut["energy-kcal_serving"] != nil
        let suffix = useServing ? "_serving" : "_100g"
        func v(_ key: String) -> Double? { nut[key + suffix] }

        let basis = useServing
            ? "per serving" + (serving_size.map { " (\($0))" } ?? "")
            : "per 100 g"

        let name = (product_name?.isEmpty == false) ? product_name! : "Unnamed product"

        return Product(
            barcode: barcode,
            name: name,
            brand: brands?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces),
            imageURL: image_front_small_url.flatMap(URL.init(string:)),
            ingredientsText: ingredients_text,
            allergenTags: allergens_tags ?? [],
            nutrition: Nutrition(
                calories: v("energy-kcal"),
                sugarG: v("sugars"),
                carbsG: v("carbohydrates"),
                sodiumMg: v("sodium").map { $0 * 1000 }, // OFF stores sodium in grams
                satFatG: v("saturated-fat"),
                transFatG: v("trans-fat"),
                proteinG: v("proteins"),
                basis: basis
            ),
            ingredientTags: ingredients_tags ?? [],
            additivesTags: additives_tags ?? [],
            ingredientAmounts: (ingredients ?? []).compactMap(\.asAmount)
        )
    }
}

/// One entry of Open Food Facts' parsed ingredient list.
struct OFFIngredient: Decodable {
    let id: String?
    let text: String?
    let percent: Double?
    let percent_estimate: Double?

    enum CodingKeys: String, CodingKey { case id, text, percent, percent_estimate }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decode(String.self, forKey: .id)
        text = try? c.decode(String.self, forKey: .text)
        percent = Self.number(c, .percent)
        percent_estimate = Self.number(c, .percent_estimate)
    }

    // Numbers sometimes arrive as strings.
    private static func number(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let d = try? c.decode(Double.self, forKey: key) { return d }
        if let s = try? c.decode(String.self, forKey: key) { return Double(s) }
        return nil
    }

    /// Nil when there's no usable name.
    var asAmount: IngredientAmount? {
        let name = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty || id != nil else { return nil }
        let stated = percent != nil
        return IngredientAmount(id: id ?? "", text: name, percent: percent ?? percent_estimate, isStated: stated)
    }
}

/// Nutriment values arrive as numbers or strings, mixed with unit fields.
/// Keep whatever parses as a number and skip the rest.
private struct Nutriments: Decodable {
    let values: [String: Double]

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        var out: [String: Double] = [:]
        for key in c.allKeys {
            if let d = try? c.decode(Double.self, forKey: key) {
                out[key.stringValue] = d
            } else if let s = try? c.decode(String.self, forKey: key), let d = Double(s) {
                out[key.stringValue] = d
            }
        }
        values = out
    }
}
