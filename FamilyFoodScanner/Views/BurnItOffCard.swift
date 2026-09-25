import SwiftUI

/// A playful "how many steps is this plate?" card for the plate result. Adults only, guilt-free, and easy to turn off.
struct BurnItOffCard: View {
    let kcal: Double
    let foods: [String]
    let members: [Member]

    @AppStorage("funSuggestions") private var funOn = true
    @AppStorage("todayMemberID") private var lastMemberID = ""
    @State private var seed = 0
    @State private var chosenID: UUID?

    private var suitable: [Member] { members.filter(BurnItOff.isSuitable) }
    private var person: Member? {
        suitable.first { $0.id == chosenID } ?? suitable.first { $0.id.uuidString == lastMemberID } ?? suitable.first
    }

    var body: some View {
        if !suitable.isEmpty {
            if funOn, let person {
                let e = BurnItOff.equivalents(kcal: kcal, weightKg: person.weightKg)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Walk it off? (for fun)", systemImage: "figure.walk.motion").font(.subheadline.weight(.bold)).foregroundStyle(Theme.brand)
                        Spacer()
                        Menu {
                            Button("Another one", systemImage: "arrow.clockwise") { withAnimation(.snappy) { seed += 1 } }
                            if suitable.count > 1 {
                                Picker("For", selection: Binding(get: { person.id }, set: { chosenID = $0 })) {
                                    ForEach(suitable) { Text($0.name).tag($0.id) }
                                }
                            }
                            Button("Turn off fun ideas", systemImage: "hand.raised") { funOn = false }
                        } label: { Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary) }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(e.steps.formatted()).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text("steps for \(person.name)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        chip("figure.walk", "\(e.walkMinutes) min")
                        chip("figure.run", "\(e.runMinutes) min")
                        chip("music.note", "\(max(e.danceMinutes / 4, 1)) songs")
                    }
                    Text(BurnItOff.message(kcal: kcal, foods: foods, equivalent: e, seed: seed))
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                        .id(seed)
                        .transition(.opacity)
                }
                .padding(.vertical, 4)
            } else if !funOn {
                Button { funOn = true } label: { Label("Show the fun \u{201C}walk it off\u{201D} ideas", systemImage: "figure.walk.motion").font(.footnote) }
            }
        }
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Theme.brand.opacity(0.12), in: Capsule())
            .lineLimit(1).minimumScaleFactor(0.8)
    }
}
