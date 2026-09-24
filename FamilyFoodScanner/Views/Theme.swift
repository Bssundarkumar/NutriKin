import SwiftUI

/// The app's look: one brand colour, soft backgrounds, rounded cards.
enum Theme {
    static let brand = Color(red: 0.12, green: 0.45, blue: 0.29)
    static let brandLight = Color(red: 0.36, green: 0.72, blue: 0.42)

    static func color(for verdict: Verdict) -> Color {
        switch verdict {
        case .okay: .green
        case .caution: .orange
        case .avoid: .red
        }
    }

    static let brandGradient = LinearGradient(colors: [brandLight, brand], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// A soft green wash behind screens, so lists don't sit on flat grey.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [Theme.brandLight.opacity(scheme == .dark ? 0.14 : 0.22), .clear],
                startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// A rounded, softly shadowed card.
    func card(padding: CGFloat = 16, radius: CGFloat = 22) -> some View {
        self.padding(padding)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
    }

    /// Screens built on `List`: soft background, no separators between cards.
    func softList() -> some View {
        self.scrollContentBackground(.hidden).background(AppBackground())
    }
}

/// A circular gauge that draws itself from 0 up to the score.
struct ScoreRing: View {
    let score: Int
    let color: Color
    var size: CGFloat = 60
    var lineWidth: CGFloat = 7
    var animate = true

    @State private var progress = 0.0
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(shown)")
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(value: Double(shown)))
        }
        .frame(width: size, height: size)
        .onAppear {
            let target = Double(min(max(score, 0), 100)) / 100
            guard animate, !reduceMotion else { progress = target; shown = score; return }
            withAnimation(.easeOut(duration: 1.0).delay(0.2)) { progress = target; shown = score }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(score) out of 100")
    }
}

/// A coloured circle with a person's initial.
struct Avatar: View {
    let name: String
    var size: CGFloat = 40

    private static let palette: [Color] = [
        Color(red: 0.12, green: 0.45, blue: 0.29), .blue, .orange, .pink, .purple, .teal,
    ]

    var body: some View {
        let color = Self.palette[abs(name.unicodeScalars.enumerated().reduce(7) { ($0 &* 31) &+ Int($1.element.value) &+ $1.offset }) % Self.palette.count]
        Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: Circle())
            .accessibilityHidden(true)
    }
}
