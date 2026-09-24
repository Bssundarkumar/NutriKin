import PhotosUI
import SwiftUI

/// "No barcode?" flow: take photos of the package or pick them from the photo
/// library, let the phone read them, then check and correct what it read
/// before it's scored. Reading is on-device; the pictures are never uploaded.
struct PhotoScanView: View {
    /// A barcode turned up in the photos: use the normal lookup.
    var onBarcode: (String) -> Void
    /// The person confirmed the label text: score this product.
    var onProduct: (Product) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .choose
    @State private var picked: [PhotosPickerItem] = []
    @State private var showCamera = false

    @State private var name = ""
    @State private var ingredients = ""
    @State private var basis = "as printed"
    @State private var calories = ""
    @State private var sugar = ""
    @State private var carbs = ""
    @State private var sodium = ""
    @State private var satFat = ""
    @State private var protein = ""

    private enum Phase: Equatable {
        case choose
        case reading
        case review(readNothing: Bool)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .choose: chooser
                case .reading: reading
                case .review(let readNothing): review(readNothing: readNothing)
                case .failed(let message): failed(message)
                }
            }
            .animation(.smooth(duration: 0.3), value: phase)
            .navigationTitle("Scan a label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .fullScreenCover(isPresented: $showCamera) {
                DocumentCameraView(
                    onFinish: { images in showCamera = false; process(images) },
                    onCancel: { showCamera = false }
                )
                .ignoresSafeArea()
            }
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                Task { await load(items) }
            }
        }
    }

    // MARK: - Steps

    private var chooser: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "text.viewfinder")
                .font(.system(size: 54))
                .foregroundStyle(Color.accentColor)
                .popIn()
            Text("No barcode? Photograph the label.")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("Take a clear photo of the **ingredients list**, and the **nutrition table** if you can. Use good light and keep the label flat. If a barcode is in the picture, we'll use it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                if DocumentCameraView.isSupported {
                    Button { showCamera = true } label: {
                        Label("Take photos", systemImage: "camera.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                PhotosPicker(selection: $picked, maxSelectionCount: 4, matching: .images) {
                    Label("Choose from photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.horizontal, 32)

            Text("Photos are read on your phone and are never uploaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
    }

    private var reading: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Reading the label\u{2026}").font(.headline)
        }
    }

    private func review(readNothing: Bool) -> some View {
        Form {
            if readNothing {
                Section {
                    Label("We couldn't read an ingredient list.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Type it in below, or go back and try a sharper, closer photo.")
                        .font(.footnote)
                }
            } else {
                Section {
                    Label("Check what we read", systemImage: "checkmark.shield")
                        .font(.subheadline.weight(.semibold))
                    Text("Photos can be misread. Compare with the package and fix anything wrong, because allergy checks use this text.")
                        .font(.footnote)
                }
            }

            Section("Product name (optional)") {
                TextField("e.g. Oat biscuits", text: $name)
            }

            Section("Ingredients") {
                TextEditor(text: $ingredients)
                    .frame(minHeight: 150)
                    .font(.callout)
            }

            Section {
                numberRow("Calories", "kcal", $calories)
                numberRow("Sugar", "g", $sugar)
                numberRow("Carbohydrate", "g", $carbs)
                numberRow("Sodium", "mg", $sodium)
                numberRow("Saturated fat", "g", $satFat)
                numberRow("Protein", "g", $protein)
            } header: {
                Text("Nutrition (\(basis))")
            } footer: {
                Text("Leave blank anything the label doesn't show.")
            }

            Section {
                Button("Score it") { finish() }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                    .disabled(!canScore)
                Button("Start over") { picked = []; phase = .choose }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text("Couldn't read that photo").font(.headline)
            Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Try again") { picked = []; phase = .choose }.buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private func numberRow(_ title: String, _ unit: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("\u{2014}", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit).font(.footnote).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }

    // MARK: - Work

    private var canScore: Bool {
        !ingredients.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || [calories, sugar, carbs, sodium, satFat, protein].contains { Self.number($0) != nil }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        phase = .reading
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { images.append(image) }
        }
        picked = []
        guard !images.isEmpty else { phase = .failed("None of the chosen photos could be opened."); return }
        process(images)
    }

    private func process(_ images: [UIImage]) {
        phase = .reading
        Task {
            do {
                switch try await LabelReader.read(images) {
                case .barcode(let code):
                    onBarcode(code)
                    dismiss()
                case .label(let parsed):
                    fill(from: parsed)
                    phase = .review(readNothing: parsed.ingredientsText == nil)
                }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func fill(from parsed: ParsedLabel) {
        ingredients = parsed.ingredientsText ?? ""
        let n = parsed.nutrition
        basis = n.basis
        calories = Self.text(n.calories); sugar = Self.text(n.sugarG); carbs = Self.text(n.carbsG)
        sodium = Self.text(n.sodiumMg); satFat = Self.text(n.satFatG); protein = Self.text(n.proteinG)
    }

    private func finish() {
        let text = ingredients.trimmingCharacters(in: .whitespacesAndNewlines)
        let product = Product(
            barcode: "photo-" + UUID().uuidString.prefix(8).lowercased(),
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Photographed label" : name.trimmingCharacters(in: .whitespaces),
            brand: nil, imageURL: nil,
            ingredientsText: text.isEmpty ? nil : text,
            allergenTags: [],
            nutrition: Nutrition(calories: Self.number(calories), sugarG: Self.number(sugar), carbsG: Self.number(carbs),
                                 sodiumMg: Self.number(sodium), satFatG: Self.number(satFat), transFatG: nil,
                                 proteinG: Self.number(protein), basis: basis)
        )
        onProduct(product)
        dismiss()
    }

    private static func number(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private static func text(_ v: Double?) -> String {
        guard let v else { return "" }
        return v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
    }
}
