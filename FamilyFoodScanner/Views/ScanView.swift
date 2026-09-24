import SwiftUI

struct ScanView: View {
    @Environment(FamilyStore.self) private var family
    @Environment(HistoryStore.self) private var history
    @State private var manualCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var product: Product?
    @State private var zoom = 1.0
    @State private var autoZoom = true
    @State private var hasRegion = false
    @State private var resetRegionToken = 0

    private let service = ProductService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Checking for \(family.members.count) family members")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                scannerArea

                HStack {
                    TextField("Or type a barcode", text: $manualCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Look up") { lookUp(manualCode) }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualCode.count < 8 || isLoading)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .navigationTitle("Scan a product")
            .navigationDestination(item: $product) { ResultView(product: $0) }
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
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .frame(maxHeight: .infinity)
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
            }
        }
    }
}
