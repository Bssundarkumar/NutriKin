import Foundation
import UIKit

/// NutriKin's own free, no-setup way to scan a plate: a few AI estimates a day per family, on NutriKin's own
/// Gemini key, no key or setup needed from anyone. Past the daily cap it fails with `.limitReached`, and the
/// caller falls back to the on-device guesser or a linked key, exactly as if this path didn't exist.
enum SharedPlateProxy {
    enum ProxyError: LocalizedError {
        case limitReached(String)
        case notConfigured
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .limitReached(let m), .failed(let m): m
            case .notConfigured: nil   // caller treats this the same as "no free proxy available", quietly
            }
        }
    }

    private struct Request: Encodable { var imageBase64: String; var plateDiameterCm: Int? }
    private struct Response: Decodable { var resultJSON: String?; var remaining: Int?; var error: String?; var message: String? }

    /// Nil result (not thrown) means only ONE thing: the server explicitly said this feature isn't set up
    /// yet (`not_configured`), which is expected before someone has deployed it and shouldn't alarm anyone.
    /// Everything else — a network problem, a decoding mismatch, an unexpected server error — is now thrown
    /// as `.failed` and shown on screen, rather than guessed at and hidden. Hiding those made a real,
    /// already-deployed, already-configured setup impossible to diagnose from the phone.
    static func estimate(image: UIImage, plateDiameterCm: Int?) async throws -> (analysis: PlateAnalysis, remaining: Int)? {
        guard let jpeg = PlateService.downscaledJPEG(image) else {
            throw ProxyError.failed("Couldn't prepare that photo to send.")
        }
        do {
            let response: Response = try await Backend.client.functions.invoke(
                "plate-scan", options: .init(body: Request(imageBase64: jpeg.base64EncodedString(), plateDiameterCm: plateDiameterCm))
            )
            if let error = response.error {
                if error == "limit_reached" { throw ProxyError.limitReached(response.message ?? "Today's free scans are used up.") }
                if error == "not_configured" { return nil }
                throw ProxyError.failed((response.message ?? "Couldn't get an estimate.") + " (\(error))")
            }
            guard let json = response.resultJSON else {
                throw ProxyError.failed("The free scan service replied with no result.")
            }
            return (try PlateParser.parse(json), response.remaining ?? 0)
        } catch let error as ProxyError {
            throw error
        } catch {
            throw ProxyError.failed("Free scan didn't work: \(error.localizedDescription)")
        }
    }
}
