import SwiftUI
import VisionKit

/// Wraps VisionKit's live barcode scanner. Requires a real device
/// (it is not supported in the Simulator).
struct BarcodeScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    /// Pulls a product number (GTIN) out of a scanned payload.
    /// Plain barcodes are numeric; QR codes only count if they hold a bare
    /// number or a GS1 Digital Link (".../01/<gtin>"). Any other QR (a brand's
    /// website, say) returns nil so it doesn't trigger a bogus lookup.
    static func productCode(from payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if (8...14).contains(trimmed.count), trimmed.allSatisfy(\.isNumber) { return trimmed }
        if let range = trimmed.range(of: #"/01/(\d{8,14})"#, options: .regularExpression) {
            return String(trimmed[range].dropFirst(4))
        }
        return nil
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .qr])],
            // .fast suits large, close-up codes like a package held to the camera.
            qualityLevel: .fast,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd items: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in items {
                if case .barcode(let code) = item,
                   let payload = code.payloadStringValue,
                   let value = BarcodeScannerView.productCode(from: payload) {
                    onScan(value)
                    return
                }
            }
        }
    }
}
