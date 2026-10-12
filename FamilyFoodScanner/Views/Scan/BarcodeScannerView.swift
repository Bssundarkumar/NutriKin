import SwiftUI
import VisionKit

/// Wraps VisionKit's live barcode scanner. Requires a real device
/// (it is not supported in the Simulator).
///
/// - Barcodes are found at any angle, so upright, sideways and rotated codes all work.
/// - Tap anywhere to make the scanner concentrate on that spot (a box appears);
///   useful for small or crowded barcodes. `resetRegionToken` clears it.
/// - Pinch to zoom is on, and `zoom` sets the zoom from buttons.
struct BarcodeScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var zoom: Double = 1
    var resetRegionToken = 0
    /// When on, the scanner searches by stepping the zoom if it finds nothing.
    var autoZoom = true
    var onRegionChange: (Bool) -> Void = { _ in }
    /// Called when the scanner changes the zoom itself (auto zoom).
    var onZoomChange: (Double) -> Void = { _ in }
    /// A code was seen that isn't a product barcode (a website QR, say).
    var onIgnored: () -> Void = {}

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

    /// The square the scanner should focus on after a tap: centred on the tap,
    /// about half the screen's short side, and kept fully inside the view.
    static func regionRect(around point: CGPoint, in size: CGSize) -> CGRect {
        let side = min(size.width, size.height) * 0.55
        let x = min(max(point.x - side / 2, 0), max(size.width - side, 0))
        let y = min(max(point.y - side / 2, 0), max(size.height - side, 0))
        return CGRect(x: x, y: y, width: side, height: side)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .qr])],
            // .balanced reads more reliably than .fast; .fast missed codes on some packs.
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        vc.view.addGestureRecognizer(tap)
        context.coordinator.scanner = vc
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        let c = context.coordinator
        c.onScan = onScan
        c.onRegionChange = onRegionChange
        c.onZoomChange = onZoomChange
        c.onIgnored = onIgnored
        if !vc.isScanning { try? vc.startScanning() }
        c.setAutoZoom(autoZoom)
        if !c.didTuneFocus {
            c.didTuneFocus = true
            // Give the scanner a moment to start its camera before adjusting it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { CameraFocus.tuneForBarcodes() }
        }

        // Apply button zoom only when it changes, so a pinch isn't undone by an unrelated redraw.
        if zoom != c.lastZoom {
            c.lastZoom = zoom
            vc.zoomFactor = min(max(zoom, vc.minZoomFactor), vc.maxZoomFactor)
        }
        if resetRegionToken != c.lastResetToken {
            c.lastResetToken = resetRegionToken
            c.clearRegion()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onRegionChange: onRegionChange, onZoomChange: onZoomChange)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void
        var onRegionChange: (Bool) -> Void
        var onZoomChange: (Double) -> Void
        var onIgnored: () -> Void = {}
        weak var scanner: DataScannerViewController?
        var lastZoom: Double = 1
        var lastResetToken = 0
        var didTuneFocus = false
        private var box: UIView?
        private var autoZoomTask: Task<Void, Never>?

        init(onScan: @escaping (String) -> Void,
             onRegionChange: @escaping (Bool) -> Void,
             onZoomChange: @escaping (Double) -> Void) {
            self.onScan = onScan
            self.onRegionChange = onRegionChange
            self.onZoomChange = onZoomChange
        }

        // MARK: Auto zoom

        func setAutoZoom(_ on: Bool) {
            if on, autoZoomTask == nil {
                autoZoomTask = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(AutoZoom.idleSeconds))
                        guard !Task.isCancelled, let self else { return }
                        self.apply(zoom: AutoZoom.next(after: self.scanner?.zoomFactor ?? 1))
                    }
                }
            } else if !on {
                autoZoomTask?.cancel()
                autoZoomTask = nil
            }
        }

        private func apply(zoom: Double) {
            guard let scanner else { return }
            let clamped = min(max(zoom, scanner.minZoomFactor), scanner.maxZoomFactor)
            lastZoom = clamped            // so the next SwiftUI update doesn't re-apply it
            scanner.zoomFactor = clamped
            onZoomChange(clamped)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scanner, let view = gesture.view else { return }
            let rect = BarcodeScannerView.regionRect(around: gesture.location(in: view), in: view.bounds.size)
            scanner.regionOfInterest = rect
            showBox(rect, in: view)
            onRegionChange(true)
            CameraFocus.focus(atSensorPoint: CameraFocus.sensorPoint(
                forViewPoint: gesture.location(in: view), viewSize: view.bounds.size))
        }

        func clearRegion() {
            scanner?.regionOfInterest = nil
            box?.removeFromSuperview()
            box = nil
            onRegionChange(false)
        }

        private func showBox(_ rect: CGRect, in view: UIView) {
            box?.removeFromSuperview()
            let b = UIView(frame: rect)
            b.isUserInteractionEnabled = false
            b.layer.borderColor = UIColor.white.cgColor
            b.layer.borderWidth = 3
            b.layer.cornerRadius = 14
            b.alpha = 0
            view.addSubview(b)
            UIView.animate(withDuration: 0.15) { b.alpha = 1 }
            box = b
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd items: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in items {
                guard case .barcode(let code) = item else { continue }
                if let payload = code.payloadStringValue {
                    if let value = BarcodeScannerView.productCode(from: payload) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onScan(value)
                        return
                    } else {
                        onIgnored()
                    }
                } else {
                    // Seen but not readable yet (too small or blurry): move closer.
                    apply(zoom: AutoZoom.stepIn(from: scanner.zoomFactor))
                }
            }
        }
    }
}
