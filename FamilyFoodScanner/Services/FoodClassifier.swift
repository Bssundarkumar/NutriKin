import UIKit
import Vision

/// Names what's on a plate using Apple's on-device image classifier, so plate scanning can work without
/// a key. The person always confirms or edits the list, because classifiers make mistakes.
enum FoodClassifier {
    /// Labels that describe the scene, not the food.
    private static let generic: Set<String> = [
        "food", "dish", "plate", "tableware", "dishware", "cuisine", "meal", "table", "indoor", "kitchen", "restaurant",
        "cookware", "bowl", "cutlery", "fork", "spoon", "knife", "glass", "cup", "drink", "beverage", "lunch", "dinner",
        "breakfast", "snack", "ingredient", "produce", "vegetable", "fruit", "baked goods", "still life", "photography",
        "container", "serveware", "utensil", "material", "wood", "furniture", "textile", "ceramic", "market",
        "outdoor", "sky", "night sky", "cloud", "nature", "plant", "people", "adult", "person", "hand", "text", "screenshot",
        "cartoon", "art", "illustration", "pattern", "sport", "structure", "room", "floor", "wall", "black", "white",
    ]

    /// Turns raw (label, confidence) pairs into a short, readable list of likely foods. Pure, so it's tested.
    static func foods(from observations: [(label: String, confidence: Float)], minimumConfidence: Float = 0.25, limit: Int = 6) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for o in observations.sorted(by: { $0.confidence > $1.confidence }) where o.confidence >= minimumConfidence {
            let label = o.label.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces).lowercased()
            guard !label.isEmpty, !generic.contains(label), seen.insert(label).inserted else { continue }
            out.append(label)
            if out.count == limit { break }
        }
        return out
    }

    static func classify(_ image: UIImage) async throws -> [String] {
        guard let cg = LabelReader.downscaled(image, maxSide: 1200).cgImage else { return [] }
        let orientation = LabelReader.cgOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            #if targetEnvironment(simulator)
            request.setValue(true, forKey: "usesCPUOnly")
            #endif
            try VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request])
            let pairs = (request.results ?? []).map { (label: $0.identifier, confidence: $0.confidence) }
            return foods(from: pairs)
        }.value
    }
}
