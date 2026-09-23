import SwiftUI

struct ScanView: View {
    @Environment(FamilyStore.self) private var family
    @State private var manualCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var product: Product?

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
                BarcodeScannerView { code in lookUp(code) }
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

    private func lookUp(_ code: String) {
        guard !isLoading, product == nil else { return } // ignore repeat scans
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                product = try await service.fetch(barcode: code)
                manualCode = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
