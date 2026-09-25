import AVFoundation
import CoreGraphics

/// How the scanner searches by zooming when it can't find a barcode.
enum AutoZoom {
    static let levels: [Double] = [1, 2, 3]
    /// Seconds with nothing detected before stepping to the next level.
    static let idleSeconds: Double = 3.5

    /// The next level in the search cycle: 1x, 2x, 3x, then back to 1x.
    static func next(after current: Double) -> Double {
        guard let i = levels.lastIndex(where: { $0 <= current + 0.01 }) else { return levels[0] }
        return levels[(i + 1) % levels.count]
    }

    /// One step closer, stopping at the highest level. Used when a barcode is
    /// seen but is too small or blurry to read.
    static func stepIn(from current: Double) -> Double {
        levels.first(where: { $0 > current + 0.01 }) ?? levels.last!
    }
}

/// Best-effort tuning of the phone's camera focus while scanning.
///
/// VisionKit owns the scanner's camera session and doesn't expose it, so this
/// adjusts the back camera hardware directly. That works when we reach the same
/// camera the scanner is using; if not, it's harmless and the scanner's own
/// continuous autofocus carries on.
enum CameraFocus {
    /// Where a tap in the on-screen preview lands on the camera sensor, as the
    /// 0...1 point AVFoundation expects. The preview is upright portrait and
    /// scaled to fill the view, so the sensor's long edge runs along the view's
    /// height and the sides of the picture are cropped.
    static func sensorPoint(forViewPoint p: CGPoint, viewSize: CGSize, sensorAspect: CGFloat = 3.0 / 4.0) -> CGPoint {
        guard viewSize.width > 0, viewSize.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        let nx = min(max(p.x / viewSize.width, 0), 1)
        let ny = min(max(p.y / viewSize.height, 0), 1)
        // Fraction of the sensor's short edge that's visible (rest is cropped away).
        let visible = min((viewSize.width / viewSize.height) / sensorAspect, 1)
        let shortEdge = 0.5 + (nx - 0.5) * visible
        // Sensor is landscape-oriented: its x runs down the screen, its y across (flipped).
        return CGPoint(x: ny, y: 1 - shortEdge)
    }

    private static var backCameras: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera],
            mediaType: .video, position: .back
        ).devices
    }

    /// Favour close-up focus (barcodes on a pack held near) and keep autofocus continuous.
    static func tuneForBarcodes() {
        for device in backCameras {
            configure(device) {
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
                if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = false }
            }
        }
    }

    /// Focus (and expose) at a sensor point, then hand back to continuous focus.
    static func focus(atSensorPoint point: CGPoint) {
        for device in backCameras {
            configure(device) {
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .continuousAutoExposure
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { tuneForBarcodes() }
    }

    private static func configure(_ device: AVCaptureDevice, _ change: () -> Void) {
        do {
            try device.lockForConfiguration()
            change()
            device.unlockForConfiguration()
        } catch {
            // Another owner holds the camera configuration; nothing to do.
        }
    }
}
