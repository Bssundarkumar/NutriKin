import PhotosUI
import SwiftUI

/// "No barcode?" flow. Photograph the package (or pick pictures), and the phone
/// reads them on-device (nothing is uploaded):
///  - the FRONT of the pack gives the product name, which is searched in the
///    food database; the person confirms the match and the real ingredients load;
///  - the INGREDIENT LIST or nutrition table is read directly, then checked and
///    corrected before it's scored;
///  - a barcode in the picture is used as-is.
struct PhotoScanView: View {
    /// A barcode turned up in the photos: use the normal lookup.
    var onBarcode: (String) -> Void
    /// The person confirmed the label text: score this product.
    var onProduct: (Product) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .choose
    @State private var picked: [PhotosPickerItem] = []
    @State private var showCamera = false
    @Environment(AIConnection.self) private var ai
    @AppStorage("photoUseAI") private var useAI = true
    @State private var brand = ""
    @State private var aiRead = false
    @State private var aiNote: String?
    @State private var spottedBarcode: String?
    @State private var showConnect = false
    @State private var aiReading = false

    @State private var name = ""
    @State private var ingredients = ""
    @State private var basis = "as printed"
    @State private var calories = ""
    @State private var sugar = ""
    @State private var carbs = ""
    @State private var sodium = ""
    @State private var satFat = ""
    @State private var protein = ""

    // Name search
    @State private var query = ""
    @State private var nameGuesses: [String] = []
    @State private var candidates: [ProductCandidate] = []
    @State private var selected: ProductCandidate?
    @State private var isSearching = false
    @State private var didSearch = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    private enum Phase: Equatable {
        case choose
        case reading
        case review(readNothing: Bool)
        case search
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .choose: chooser
                case .reading: reading
                case .review(let readNothing): review(readNothing: readNothing)
                case .search: search
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
            .sheet(isPresented: $showConnect) { ConnectAIView() }
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
            Text("No barcode? Show us the product.")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("Photograph the **front of the pack** and we'll find it by name, so you can confirm it and get its real ingredients. Or photograph the **ingredients list** and nutrition table. Use good light and keep the label flat.")
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
                Button { startSearch(prefill: "", alternates: [], run: false) } label: {
                    Label("Search by product name", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.horizontal, 32)

            if ai.isConnected {
                Toggle("Also read the label with my AI", isOn: $useAI)
                    .font(.subheadline)
                    .padding(.horizontal, 32)
            }
            Text(ai.isConnected && useAI
                 ? "Photos are read on your phone first. If it isn't a known barcode, they're also sent to \(ai.keyProvider?.vendorName ?? "your AI") under your own key so the AI can read the name, ingredients and nutrition. You confirm everything before it's scored."
                 : "Photos are read on your phone and are never uploaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    private var reading: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(aiReading ? "Asking your AI to read it\u{2026}" : "Reading the label\u{2026}").font(.headline)
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
                    Label(aiRead ? "Read by AI. Please confirm." : "Check what we read",
                          systemImage: aiRead ? "sparkles" : "checkmark.shield")
                        .font(.subheadline.weight(.semibold))
                    Text("Photos can be misread, by AI as well. Compare with the package and fix anything wrong, because allergy checks use this text.")
                        .font(.footnote)
                    if let aiNote { Text(aiNote).font(.footnote).foregroundStyle(.secondary) }
                }
                if let code = spottedBarcode {
                    Section {
                        Button("Look up barcode \(code) instead") { onBarcode(code); dismiss() }
                    } footer: {
                        Text("The AI spotted this number under a barcode. A match gives you the database's full details.")
                    }
                }
            }

            Section("Product (optional)") {
                TextField("Name, e.g. Oat biscuits", text: $name)
                TextField("Brand", text: $brand)
            }

            if !ai.isConnected {
                Section {
                    Button { showConnect = true } label: { Label("Read it with AI instead", systemImage: "sparkles") }
                } footer: {
                    Text("Link your own AI key (Claude, OpenAI, Grok or Gemini) and the AI can read the name, ingredients and nutrition from your photos. You confirm before it's scored.")
                }
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
                Button("Look it up by name instead") {
                    startSearch(prefill: name.isEmpty ? (nameGuesses.first ?? "") : name,
                                alternates: nameGuesses, run: !(name.isEmpty && nameGuesses.isEmpty))
                }
                .frame(maxWidth: .infinity)
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

    private var search: some View {
        List {
            Section {
                HStack {
                    TextField("e.g. Nutella Ferrero", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { runSearch() }
                    Button("Search") { runSearch() }
                        .disabled(query.trimmingCharacters(in: .whitespaces).count < 2 || isSearching)
                }
            } header: {
                Text("What's the product called?")
            } footer: {
                Text("Add the brand for better matches. Then pick the one that matches your pack (check the size) and confirm it.")
            }

            if nameGuesses.count > 1 {
                Section("Other names we read on the pack") {
                    FlowLayout(spacing: 6) {
                        ForEach(nameGuesses, id: \.self) { guess in
                            Button(guess) { query = guess; runSearch() }
                                .font(.footnote)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section("Matches") {
                if isSearching {
                    HStack(spacing: 10) { ProgressView(); Text("Searching\u{2026}").foregroundStyle(.secondary) }
                } else if let searchError {
                    Text(searchError).font(.footnote).foregroundStyle(.red)
                } else if didSearch && candidates.isEmpty {
                    Text("No match found. Try fewer words, or photograph the ingredients instead.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(candidates) { candidate in
                    Button { withAnimation(.snappy) { selected = candidate } } label: {
                        CandidateRow(candidate: candidate, isSelected: selected == candidate)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button("Use this product") { confirm() }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                    .disabled(selected == nil)
                Button("None of these \u{2014} photograph the ingredients") {
                    picked = []; phase = .choose
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.secondary)
            } footer: {
                if let selected {
                    Text("We'll load the ingredients for \u{201C}\(selected.name)\u{201D}\(selected.quantity.map { ", \($0)" } ?? "").")
                }
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
                case .label(let parsed, let guesses):
                    fill(from: parsed)
                    nameGuesses = guesses
                    aiRead = false; aiNote = nil; spottedBarcode = nil
                    if useAI, let client = ai.keyClient {
                        aiReading = true
                        defer { aiReading = false }
                        do {
                            let reading = ProductPhotoReader.merge(ai: try await ProductPhotoReader.read(images: images, client: client), ocr: parsed)
                            if reading.foundAnything {
                                apply(reading)
                                phase = .review(readNothing: false)
                                return
                            }
                            aiNote = "The AI couldn't read this photo either."
                        } catch {
                            aiNote = "The AI couldn't read the photo: \(error.localizedDescription)"
                        }
                    }
                    if parsed.ingredientsText != nil {
                        phase = .review(readNothing: false)               // an ingredient list was read
                    } else if let best = guesses.first {
                        startSearch(prefill: best, alternates: guesses, run: true)   // front of pack: find it by name
                    } else {
                        phase = .review(readNothing: true)
                    }
                }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func startSearch(prefill: String, alternates: [String], run: Bool) {
        query = prefill
        nameGuesses = alternates
        candidates = []; selected = nil; didSearch = false; searchError = nil
        phase = .search
        if run { runSearch() }
    }

    private func runSearch() {
        searchTask?.cancel()
        let text = query
        searchTask = Task {
            isSearching = true
            searchError = nil
            selected = nil
            defer { isSearching = false }
            do {
                let found = try await ProductService().search(text)
                guard !Task.isCancelled else { return }
                withAnimation(.snappy) { candidates = found }
                didSearch = true
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                candidates = []
                searchError = error.localizedDescription
                didSearch = true
            }
        }
    }

    /// The person confirmed the match: hand its barcode to the normal lookup,
    /// which loads the real ingredients and nutrition.
    private func confirm() {
        guard let selected else { return }
        onBarcode(selected.code)
        dismiss()
    }

    /// Puts the AI's reading into the review form for the person to confirm or correct.
    private func apply(_ r: ProductReading) {
        aiRead = true
        if let v = r.name { name = v }
        brand = r.brand ?? ""
        ingredients = r.ingredientsText ?? ""
        basis = r.nutrition.basis
        calories = Self.text(r.nutrition.calories); sugar = Self.text(r.nutrition.sugarG); carbs = Self.text(r.nutrition.carbsG)
        sodium = Self.text(r.nutrition.sodiumMg); satFat = Self.text(r.nutrition.satFatG); protein = Self.text(r.nutrition.proteinG)
        spottedBarcode = r.barcode
        aiNote = r.notes
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
            brand: brand.trimmingCharacters(in: .whitespaces).isEmpty ? nil : brand.trimmingCharacters(in: .whitespaces),
            imageURL: nil,
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


private struct CandidateRow: View {
    let candidate: ProductCandidate
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: candidate.imageURL) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                Color.secondary.opacity(0.12)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text([candidate.brand, candidate.quantity].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                .scaleEffect(isSelected ? 1.1 : 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
