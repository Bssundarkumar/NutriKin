import PhotosUI
import SwiftUI

/// Photograph a plate, let the person's own AI estimate what's on it, then review
/// and correct the portions. Everything shown is an estimate.
struct PlateScanView: View {
    @Environment(FamilyStore.self) private var family
    @Environment(AIConnection.self) private var ai
    @Environment(TrackingStore.self) private var tracking
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable { case setup, analyzing, describe, results, failed(String) }

    @AppStorage("plateDiameterCm") private var plateCm = 26
    @State private var phase: Phase = .setup
    @State private var image: UIImage?
    @State private var picked: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showConnect = false
    @State private var items: [PlateItem] = []
    @State private var note: String?
    @State private var task: Task<Void, Never>?

    private let sizes = [0, 20, 23, 26, 28, 30]      // 0 = let the AI estimate it
    @State private var showMeasure = false
    @State private var foodsText = ""
    @State private var loggedNote: String?
    @State private var lastFoods: String?
    @FocusState private var foodsFocused: Bool
    @State private var usedCm = 26
    @State private var usedWasEstimated = false
    @State private var editedCm = 26

    /// The presets, plus a measured size if it isn't one of them.
    private var sizeOptions: [Int] { Array(Set(sizes + (plateCm > 0 ? [plateCm] : []))).sorted() }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .setup: setup
                case .analyzing: analyzing
                case .describe: describe
                case .results: results
                case .failed(let message): failed(message)
                }
            }
            .background(AppBackground())
            .navigationTitle("Scan a plate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { task?.cancel(); dismiss() } } }
            .onAppear {
                if Demo.plateResults, phase == .setup { items = Demo.plateItems; note = "The chutney amount is a guess."; phase = .results }
            }
            .sheet(isPresented: $showConnect) { ConnectAIView() }
            .fullScreenCover(isPresented: $showMeasure) { PlateMeasureView { plateCm = $0 } }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { analyze($0) }.ignoresSafeArea()
            }
            .onChange(of: picked) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        analyze(img)
                    }
                    picked = nil
                }
            }
        }
    }

    // MARK: Setup

    private var setup: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.brandGradient)
                    .padding(.top, 8)
                Text("Estimate a meal's calories")
                    .font(.title2.bold())
                Text("Take a photo of your plate from directly above. NutriKin's AI spots each food, estimates the portions and works out what it means for everyone in your family.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 8) {
                    Text("How wide is your plate? (cm)").font(.subheadline.weight(.semibold))
                    Picker("Plate size", selection: $plateCm) {
                        ForEach(sizeOptions, id: \.self) { Text($0 == 0 ? "AI" : "\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(plateCm == 0
                         ? "The AI will estimate the plate's size from the photo. Measuring is more accurate."
                         : "Across the flat plate, edge to edge. It gives the AI a scale to judge how much food there is.")
                        .font(.caption).foregroundStyle(.secondary)
                    if PlateMeasureView.isSupported {
                        Button { showMeasure = true } label: { Label("Measure it with the camera", systemImage: "ruler") }
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .card()

                if ai.keyClient != nil || ai.appleStatus.isAvailable {
                    if ai.keyClient == nil {
                        Label("Uses Apple Intelligence on your iPhone. Nothing is uploaded.", systemImage: "apple.intelligence")
                            .font(.footnote).foregroundStyle(Theme.brand).multilineTextAlignment(.center)
                    }
                    if CameraPicker.isAvailable {
                        Button { showCamera = true } label: { bigButton("Take a photo", "camera.fill", filled: true) }
                            .buttonStyle(PressableStyle())
                    }
                    PhotosPicker(selection: $picked, matching: .images) {
                        bigButton("Choose a photo", "photo.on.rectangle", filled: !CameraPicker.isAvailable)
                    }
                    .buttonStyle(PressableStyle())
                    if ai.keyClient == nil {
                        Button { image = nil; lastFoods = nil; foodsText = ""; phase = .describe } label: {
                            Label("Describe what you ate instead", systemImage: "text.cursor").font(.subheadline.weight(.semibold))
                        }
                        Text("Apple's on-device AI can't see photos. It recognises what's on the plate on your phone, you confirm the foods, then it estimates the portions. A linked AI key can read the photo directly for better accuracy.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                } else {
                    VStack(spacing: 10) {
                        Label("Link an AI to scan plates", systemImage: "key.fill").font(.headline).foregroundStyle(Theme.brand)
                        Text("Apple Intelligence isn't available on this iPhone, so plate scanning needs your own AI account (Claude, OpenAI, Grok or Gemini). It takes a minute to set up.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if case .unavailable(let reason) = ai.appleStatus {
                            Text(reason).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        Button { showConnect = true } label: { bigButton("Link your key", "key", filled: true) }
                            .buttonStyle(PressableStyle())
                    }
                    .card()
                }

                Text("Estimates can be off by 20 to 30 percent. Not for insulin dosing or medical decisions.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    private func bigButton(_ title: String, _ symbol: String, filled: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(filled ? Color.white : Theme.brand)
            .background {
                if filled { Capsule().fill(Theme.brandGradient) }
                else { Capsule().fill(Color(.secondarySystemGroupedBackground)) }
            }
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    // MARK: Describe (on-device path)

    private var describe: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 150, height: 150)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .shadow(color: Theme.brand.opacity(0.3), radius: 10, y: 5)
                }
                Text("What's on the plate?").font(.title3.bold())
                Text(image == nil
                     ? "List the foods, with amounts if you know them: \"2 rotis, a bowl of dal, mixed vegetable curry\"."
                     : "Your iPhone recognised these from the photo. Fix anything wrong and add amounts, for example \"2 rotis\" or \"a small bowl of dal\".")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                TextField("e.g. rice, dal, chicken curry", text: $foodsText, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($foodsFocused)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Button { foodsFocused = false; estimateOnDevice(foodsText) } label: {
                    bigButton("Estimate calories", "sparkles", filled: true)
                }
                .buttonStyle(PressableStyle())
                .disabled(foodsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Back") { phase = .setup }.foregroundStyle(.secondary)
            }
            .padding()
        }
        .onAppear { if foodsText.isEmpty { foodsFocused = image == nil } }
    }

    /// Recognises the foods in a photo on the phone, then lets the person confirm them before estimating.
    private func beginOnDevice(_ picture: UIImage) {
        image = picture
        lastFoods = nil
        phase = .analyzing
        task?.cancel()
        task = Task {
            let foods = (try? await FoodClassifier.classify(picture)) ?? []
            guard !Task.isCancelled else { return }
            foodsText = foods.joined(separator: ", ")
            phase = .describe
        }
    }

    private func estimateOnDevice(_ foods: String, sizeOverride: Int? = nil) {
        let requested: Int? = sizeOverride ?? (plateCm == 0 ? nil : plateCm)
        lastFoods = foods
        phase = .analyzing
        task?.cancel()
        task = Task {
            do {
                let analysis = try await PlateService.estimateOnDevice(foods: foods, plateDiameterCm: requested)
                guard !Task.isCancelled else { return }
                items = analysis.items
                note = analysis.note ?? "Estimated on your iPhone from the foods you confirmed."
                usedWasEstimated = false
                usedCm = requested ?? 26
                editedCm = usedCm
                phase = .results
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Analysing

    private var analyzing: some View {
        VStack(spacing: 22) {
            Spacer()
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 240, height: 240)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                    .shadow(color: Theme.brand.opacity(0.35), radius: 16, y: 8)
                    .overlay { PulsingRing() }
            }
            Text("Looking at your plate\u{2026}").font(.headline)
            Text("Spotting foods and estimating portions. This takes a few seconds.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
            Text("Couldn't analyse the plate").font(.headline)
            Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Try again") { phase = .setup }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            Spacer()
        }
        .padding()
    }

    // MARK: Results

    private var results: some View {
        let totals = MealTotals.of(items)
        let allergens = Set(items.flatMap(\.allergens))
        return List {
            Section {
                HStack(spacing: 14) {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(totals.calories.rounded()))")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .contentTransition(.numericText(value: totals.calories))
                        Text("estimated calories").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("ESTIMATE").font(.caption2.weight(.bold)).tracking(1)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.18), in: Capsule()).foregroundStyle(.orange)
                }
                macroRow(totals)
            }
            .listRowBackground(Color(.secondarySystemGroupedBackground))

            Section {
                Stepper(value: $editedCm, in: 10...45) {
                    Text("Plate size: \(editedCm) cm" + (usedWasEstimated && editedCm == usedCm ? " (AI estimate)" : ""))
                }
                if editedCm != usedCm, image != nil || lastFoods != nil {
                    Button {
                        if let foods = lastFoods { estimateOnDevice(foods, sizeOverride: editedCm) }
                        else if let image { analyze(image, sizeOverride: editedCm) }
                    } label: {
                        Label("Re-estimate with a \(editedCm) cm plate", systemImage: "arrow.clockwise")
                    }
                }
            } footer: {
                Text("Portions are judged against the plate's size. If the size looks wrong, fix it and re-estimate.")
            }

            if items.isEmpty {
                Section { Text(note ?? "No food found in the photo. Try again from directly above, with good light.").font(.subheadline) }
            } else {
                Section {
                    ForEach($items) { $item in PlateItemRow(item: $item) }
                        .onDelete { items.remove(atOffsets: $0) }
                } header: {
                    Text("What's on the plate")
                } footer: {
                    Text("Adjust the grams if the estimate looks wrong. Swipe to remove something that isn't there.")
                }
            }

            if !items.isEmpty {
                Section {
                    ForEach(family.members.map { PlateMath.impact(of: totals, allergens: allergens, for: $0) }) { impact in
                        MemberImpactRow(impact: impact)
                    }
                } header: {
                    Text("For each family member")
                } footer: {
                    Text("Shares of each person's daily sugar, sodium and saturated-fat limits. Allergens are the AI's guess: always check the ingredients yourself.")
                }
            }

            if let note, !items.isEmpty {
                Section { Label(note, systemImage: "info.circle").font(.footnote) }
            }

            if !items.isEmpty {
                Section {
                    Menu {
                        ForEach(family.members) { m in Button(m.name) { logMeal(for: m) } }
                    } label: { Label(loggedNote ?? "Log this meal for\u{2026}", systemImage: loggedNote == nil ? "plus.circle.fill" : "checkmark.circle.fill") }
                } footer: { Text("Adds it to that person's day on the Today tab.") }
            }

            Section {
                Button { phase = .setup; image = nil; lastFoods = nil; loggedNote = nil } label: { Label("Scan another plate", systemImage: "camera.viewfinder") }
                Text("Guidance only, not medical advice. Portions are estimated from a photo and can be significantly off.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .softList()
        .animation(.snappy, value: items)
    }

    private func macroRow(_ t: MealTotals) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
            macro("Protein", "\(Int(t.proteinG.rounded())) g")
            macro("Carbs", "\(Int(t.carbsG.rounded())) g")
            macro("Fat", "\(Int(t.fatG.rounded())) g")
            macro("Fibre", "\(Int(t.fiberG.rounded())) g")
            macro("Sugar", "\(Int(t.sugarG.rounded())) g")
            macro("Sodium", "\(Int(t.sodiumMg.rounded())) mg")
        }
    }

    private func macro(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func logMeal(for member: Member) {
        let entry = PortionScaler.entry(for: items, memberId: member.id, householdId: family.householdId, at: tracking.timestampForNewItem)
        Task {
            if await tracking.add(entry) { loggedNote = "Logged for \(member.name)"; UINotificationFeedbackGenerator().notificationOccurred(.success) }
            else { loggedNote = nil }
        }
    }

    // MARK: Analysis

    /// `sizeOverride` re-runs the same photo with a corrected plate size.
    private func analyze(_ picture: UIImage, sizeOverride: Int? = nil) {
        guard let client = ai.keyClient else {
            if ai.appleStatus.isAvailable { beginOnDevice(picture) } else { showConnect = true }
            return
        }
        lastFoods = nil
        let requested: Int? = sizeOverride ?? (plateCm == 0 ? nil : plateCm)
        image = picture
        phase = .analyzing
        task?.cancel()
        task = Task {
            do {
                let analysis = try await PlateService(client: client).analyze(image: picture, plateDiameterCm: requested)
                guard !Task.isCancelled else { return }
                items = analysis.items
                note = analysis.note
                usedWasEstimated = requested == nil
                usedCm = requested ?? analysis.estimatedPlateCm ?? 26
                editedCm = usedCm
                phase = .results
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

private struct PlateItemRow: View {
    @Binding var item: PlateItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name).font(.headline)
                if item.confidence == .low {
                    Text("unsure").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
                Spacer()
                Text("\(Int(item.calories.rounded())) kcal").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Stepper(value: $item.grams, in: 5...1500, step: 10) {
                Text("\(Int(item.grams.rounded())) g").font(.subheadline.monospacedDigit())
            }
        }
        .padding(.vertical, 2)
    }
}

private struct MemberImpactRow: View {
    let impact: MemberImpact

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Avatar(name: impact.member.name, size: 34)
                Text(impact.member.name).font(.headline)
                Spacer()
                Text("\(Int((impact.caloriePct * 100).rounded()))% of daily calories")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !impact.allergyHits.isEmpty {
                Label("Possible \(impact.allergyHits.map { $0.rawValue }.joined(separator: ", ")). Check the ingredients.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.red)
            }
            bar("Sugar", impact.sugarPct)
            bar("Sodium", impact.sodiumPct)
            bar("Sat. fat", impact.satFatPct)
        }
        .padding(.vertical, 4)
    }

    private func bar(_ title: String, _ share: Double) -> some View {
        let color: Color = share >= 0.6 ? .red : share >= 0.35 ? .orange : .green
        return HStack(spacing: 8) {
            Text(title).font(.caption).frame(width: 52, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule().fill(color.gradient).frame(width: geo.size.width * min(share, 1))
                }
            }
            .frame(height: 8)
            Text("\(Int((share * 100).rounded()))%").font(.caption.monospacedDigit()).frame(width: 40, alignment: .trailing)
        }
    }
}

private struct PulsingRing: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(Theme.brandLight.opacity(0.6), lineWidth: 3)
            .scaleEffect(on ? 1.18 : 1)
            .opacity(on ? 0 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true }
            }
    }
}
