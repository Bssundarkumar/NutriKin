import PhotosUI
import SwiftUI

/// Photograph a plate, let the person's own AI estimate what's on it, then review
/// and correct the portions. Everything shown is an estimate.
struct PlateScanView: View {
    @Environment(FamilyStore.self) private var family
    @Environment(AIConnection.self) private var ai
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable { case setup, analyzing, results, failed(String) }

    @AppStorage("plateDiameterCm") private var plateCm = 26
    @State private var phase: Phase = .setup
    @State private var image: UIImage?
    @State private var picked: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showConnect = false
    @State private var items: [PlateItem] = []
    @State private var note: String?
    @State private var task: Task<Void, Never>?

    private let sizes = [20, 23, 26, 28, 30]

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .setup: setup
                case .analyzing: analyzing
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
                    Text("How wide is your plate?").font(.subheadline.weight(.semibold))
                    Picker("Plate size", selection: $plateCm) {
                        ForEach(sizes, id: \.self) { Text("\($0) cm").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("Measure across the flat plate, edge to edge. It gives the AI a scale to judge how much food there is.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .card()

                if ai.isConnected {
                    if CameraPicker.isAvailable {
                        Button { showCamera = true } label: { bigButton("Take a photo", "camera.fill", filled: true) }
                            .buttonStyle(PressableStyle())
                    }
                    PhotosPicker(selection: $picked, matching: .images) {
                        bigButton("Choose a photo", "photo.on.rectangle", filled: !CameraPicker.isAvailable)
                    }
                    .buttonStyle(PressableStyle())
                } else {
                    VStack(spacing: 10) {
                        Label("Plate photos need a Claude key", systemImage: "key.fill").font(.headline).foregroundStyle(Theme.brand)
                        Text("Apple's on-device AI reads text, not photos, so this one feature uses your own Anthropic account. It takes a minute to set up.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
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

            Section {
                Button { phase = .setup; image = nil } label: { Label("Scan another plate", systemImage: "camera.viewfinder") }
                Text("Guidance only, not medical advice. Portions are estimated from a photo and can be significantly off.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .softList()
        .animation(.snappy, value: items)
    }

    private func macroRow(_ t: MealTotals) -> some View {
        HStack {
            macro("Carbs", "\(Int(t.carbsG.rounded())) g")
            macro("Protein", "\(Int(t.proteinG.rounded())) g")
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

    // MARK: Analysis

    private func analyze(_ picture: UIImage) {
        guard let key = ai.apiKey else { showConnect = true; return }
        image = picture
        phase = .analyzing
        task?.cancel()
        task = Task {
            do {
                let analysis = try await PlateService(apiKey: key).analyze(image: picture, plateDiameterCm: plateCm)
                guard !Task.isCancelled else { return }
                items = analysis.items
                note = analysis.note
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
