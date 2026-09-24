import UIKit
import Vision

/// Reads photos of packaging using Apple's on-device Vision framework. Nothing
/// is uploaded: the pictures never leave the phone.
enum LabelReader {
    enum Outcome: Equatable {
        /// A barcode was found, so the normal product lookup can be used.
        case barcode(String)
        /// No barcode: the label text was read and parsed, along with the
        /// most likely product names (from the biggest lettering).
        case label(ParsedLabel, nameGuesses: [String])
    }

    /// Reads one or more photos. A barcode in any photo wins; otherwise the
    /// text of every photo is combined (front, ingredients and nutrition
    /// table can be separate pictures) and parsed.
    static func read(_ images: [UIImage]) async throws -> Outcome {
        let prepared = images.map { downscaled($0) }
        for image in prepared {
            if let code = try await barcode(in: image) { return .barcode(code) }
        }
        var rows: [String] = []
        var pieces: [Piece] = []
        for image in prepared {
            let found = try await textPieces(in: image)
            pieces += found
            rows += groupRows(found)
        }
        return .label(LabelParser.parse(rows), nameGuesses: ProductNameGuesser.guesses(from: pieces))
    }

    // MARK: - Barcode

    static func barcode(in image: UIImage) async throws -> String? {
        guard let cg = image.cgImage else { return nil }
        let orientation = cgOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.ean13, .ean8, .upce, .code128, .qr]
            useCPUInSimulator(request)
            try VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request])
            for observation in request.results ?? [] {
                if let payload = observation.payloadStringValue,
                   let code = BarcodeScannerView.productCode(from: payload) { return code }
            }
            return nil
        }.value
    }

    // MARK: - Text

    /// Recognised text as rows, top to bottom. Pieces on the same line (the
    /// name and value cells of a nutrition table) are joined into one row.
    static func textRows(in image: UIImage) async throws -> [String] {
        groupRows(try await textPieces(in: image))
    }

    /// Every recognised piece of text with where it sits and how tall its lettering is.
    static func textPieces(in image: UIImage) async throws -> [Piece] {
        guard let cg = image.cgImage else { return [] }
        let orientation = cgOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            useCPUInSimulator(request)
            try VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request])
            return (request.results ?? []).compactMap { obs in
                guard let text = obs.topCandidates(1).first?.string else { return nil }
                return Piece(text: text, minX: obs.boundingBox.minX, midY: obs.boundingBox.midY, height: obs.boundingBox.height)
            }
        }.value
    }

    struct Piece: Equatable {
        var text: String
        var minX: CGFloat
        /// Vision's origin is the bottom-left, so a larger `midY` is higher on the page.
        var midY: CGFloat
        var height: CGFloat
    }

    /// Sorts text pieces top to bottom and joins pieces that sit on the same
    /// line (left to right) into a single row.
    static func groupRows(_ pieces: [Piece]) -> [String] {
        var rows: [[Piece]] = []
        for piece in pieces.sorted(by: { $0.midY > $1.midY }) {
            if let last = rows.last, let first = last.first,
               abs(first.midY - piece.midY) < max(first.height, piece.height) * 0.5 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { $0.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ") }
    }

    /// The iOS Simulator has no neural engine, so Vision fails there ("Could not
    /// create inference context") unless told to use the CPU. Real phones are
    /// unaffected, and this compiles to nothing in device builds.
    private static func useCPUInSimulator(_ request: VNRequest) {
        #if targetEnvironment(simulator)
        request.setValue(true, forKey: "usesCPUOnly")
        #endif
    }

    // MARK: - Image helpers

    /// Big photos are slow to read and no more accurate past about 2200 px.
    static func downscaled(_ image: UIImage, maxSide: CGFloat = 2200) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
