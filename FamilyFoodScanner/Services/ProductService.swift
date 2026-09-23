import Foundation

enum ProductError: LocalizedError {
    case notFound
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notFound: "This product isn't in the database yet. Try photographing the label."
        case .badResponse: "Couldn't reach the product database. Check your connection."
        }
    }
}

/// Looks products up in Open Food Facts (free, open data).
/// Docs: https://openfoodfacts.github.io/openfoodfacts-server/api/
struct ProductService {
    // Open Food Facts asks every app to identify itself. Put your real contact here.
    private let userAgent = "FamilyFoodScanner/0.1 (bssundarkumar@gmail.com)"

    func fetch(barcode: String) async throws -> Product {
        let code = barcode.filter(\.isNumber)
        var comps = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json")!
        comps.queryItems = [URLQueryItem(
            name: "fields",
            value: "product_name,brands,image_front_small_url,ingredients_text,ingredients_tags,additives_tags,allergens_tags,serving_size,nutriments"
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
            additivesTags: additives_tags ?? []
        )
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
