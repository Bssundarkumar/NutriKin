import SwiftUI

struct ScanView: View {
    @Environment(FamilyStore.self) private var family
    @Environment(HistoryStore.self) private var history
    @State private var manualCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var product: Product? = Demo.product
    @State private var zoom = 1.0
    @State private var autoZoom = true
    @State private var hasRegion = false
    @State private var resetRegionToken = 0
    @State private var showPhoto = false
    @State private var showPlate = Demo.opensPlate
    /// Set by the photo sheet, acted on once the sheet has closed.
    @State private var photoProduct: Product?
    @State private var photoBarcode: String?
    @State private var lookupWasNotFound = false

    private let service = ProductService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                familyChip

                scannerArea

                HStack(spacing: 10) {
                    Image(systemName: "number").foregroundStyle(.secondary)
                    TextField("Or type a barcode", text: $manualCode)
                        .keyboardType(.numberPad)
                    Button("Look up") { lookUp(manualCode) }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .disabled(manualCode.count < 8 || isLoading)
                }
                .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)

                Button { showPhoto = true } label: {
                    Label("No barcode? Take a photo or upload one", systemImage: "camera.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.white)
                        .background(Theme.brandGradient, in: Capsule())
                        .shadow(color: Theme.brand.opacity(0.35), radius: 10, y: 5)
                }
                .buttonStyle(PressableStyle())

                Button { showPlate = true } label: {
                    Label("Scan a plate (estimate calories)", systemImage: "fork.knife")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(Theme.brand)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.brand.opacity(0.35)))
                }
                .buttonStyle(PressableStyle())

                if let errorMessage {
                    VStack(spacing: 6) {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                        if lookupWasNotFound {
                            Button("Photograph the label instead") { showPhoto = true }
                                .font(.footnote.weight(.semibold))
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding()
            .background(AppBackground())
            .animation(.smooth(duration: 0.25), value: errorMessage)
            .navigationTitle("Scan a product")
            .navigationDestination(item: $product) { ResultView(product: $0) }
            .sheet(isPresented: $showPlate) { PlateScanView() }
            .sheet(isPresented: $showPhoto, onDismiss: photoSheetClosed) {
                PhotoScanView(
                    onBarcode: { photoBarcode = $0 },
                    onProduct: { photoProduct = $0 }
                )
            }
        }
    }

    @ViewBuilder
    private var scannerArea: some View {
        ZStack {
            if BarcodeScannerView.isAvailable && product == nil {
                BarcodeScannerView(
                    onScan: { code in lookUp(code) },
                    zoom: zoom,
                    resetRegionToken: resetRegionToken,
                    autoZoom: autoZoom,
                    onRegionChange: { hasRegion = $0 },
                    onZoomChange: { zoom = $0 }
                )
                if !hasRegion { ScannerFrame().transition(.opacity) }
                scannerControls
            } else {
                Color.black.opacity(0.85)
                if !BarcodeScannerView.isAvailable {
                    Text("Camera scanning needs a real iPhone.\nType a barcode below to test.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                }
            }
            if isLoading { ProgressView().tint(.white).controlSize(.large) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 2))
        .shadow(color: Theme.brand.opacity(0.3), radius: 16, y: 8)
        .frame(maxHeight: .infinity)
    }

    private var familyChip: some View {
        HStack(spacing: 10) {
            HStack(spacing: -10) {
                ForEach(Array(family.members.prefix(4))) { m in
                    Avatar(name: m.name, size: 30).overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                }
            }
            Text("Checking for \(family.members.count) family member\(family.members.count == 1 ? "" : "s")")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// Hint, zoom buttons and (after a tap) a way back to scanning the whole view.
    private var scannerControls: some View {
        VStack {
            Text(hasRegion ? "Scanning inside the box" : "Tap the barcode to focus \u{00B7} pinch or use \u{00D7} to zoom")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.black.opacity(0.55), in: Capsule())
                .foregroundStyle(.white)
                .padding(.top, 10)
            Spacer()
            HStack(spacing: 8) {
                Button { autoZoom.toggle() } label: {
                    Text("Auto")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(autoZoom ? Color.white : Color.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(autoZoom ? Color.black : Color.white)
                }
                ForEach([1.0, 2.0, 3.0], id: \.self) { level in
                    Button { autoZoom = false; zoom = level } label: {
                        Text("\(Int(level))\u{00D7}")
                            .font(.footnote.weight(.semibold))
                            .frame(width: 40, height: 30)
                            .background(zoom == level ? Color.white : Color.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(zoom == level ? Color.black : Color.white)
                    }
                    .buttonStyle(PressableStyle())
                }
                if hasRegion {
                    Button { resetRegionToken += 1 } label: {
                        Label("Scan whole view", systemImage: "viewfinder")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(Color.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func lookUp(_ code: String) {
        guard !isLoading, product == nil else { return } // ignore repeat scans
        isLoading = true
        errorMessage = nil
        lookupWasNotFound = false
        Task {
            defer { isLoading = false }
            do {
                let fetched = try await service.fetch(barcode: code)
                product = fetched
                manualCode = ""
                // Save to history without holding up the result screen.
                Task { await history.record(fetched, family: family) }
            } catch {
                errorMessage = error.localizedDescription
                if let e = error as? ProductError, case .notFound = e { lookupWasNotFound = true }
            }
        }
    }

    /// Acts on what the photo sheet produced, after it has finished closing
    /// (pushing a screen while a sheet is still dismissing is unreliable).
    private func photoSheetClosed() {
        if let code = photoBarcode {
            photoBarcode = nil
            lookUp(code)
        } else if let scanned = photoProduct {
            photoProduct = nil
            product = scanned
            Task { await history.record(scanned, family: family) }
        }
    }
}
