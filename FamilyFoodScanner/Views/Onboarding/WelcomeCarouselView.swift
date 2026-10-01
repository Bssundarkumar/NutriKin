import SwiftUI

/// A short, swipeable "what NutriKin does" intro, shown once ever, before sign-in. Closeable at any
/// point — it's a pitch, not a gate, so nobody gets stuck looking at it to use the app.
struct WelcomeCarouselView: View {
    @Environment(\.dismiss) private var dismiss
    var onFinished: () -> Void
    @State private var page = 0

    private struct Slide {
        let title: String
        let symbol: String
        let body: String
    }

    private let slides: [Slide] = [
        Slide(title: "Crush Your Family's\nHealth & Nutrition Goals",
              symbol: "chart.pie.fill",
              body: "Track meals, scores and goals for everyone in your family, in one place."),
        Slide(title: "Scan a Plate,\nSkip the Guesswork",
              symbol: "camera.viewfinder",
              body: "Snap a photo and AI estimates calories, protein, carbs and more — no searching required."),
        Slide(title: "Built for the\nWhole Family",
              symbol: "person.3.fill",
              body: "Conditions, allergies and goals per person, so every scan is checked against who's eating."),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { i in
                    slide(slides[i]).tag(i)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button { finish() } label: {
                Image(systemName: "xmark.circle.fill")
                    .readableFont(24, weight: .regular, relativeTo: .title2)
                    .foregroundStyle(.secondary, Color(.tertiarySystemFill))
            }
            .padding(20)
            .accessibilityLabel("Close")
        }
        .background(AppBackground())
        .overlay(alignment: .bottom) {
            if page == slides.count - 1 {
                Button("Get Started") { finish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
        }
        .animation(.smooth(duration: 0.25), value: page)
    }

    private func slide(_ s: Slide) -> some View {
        ScrollView {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: s.symbol)
                .font(.system(size: 64))
                .foregroundStyle(Theme.brandGradient)
            Text(s.title)
                .readableFont(30, weight: .bold, relativeTo: .title)
                .multilineTextAlignment(.center)
            Text(s.body)
                .readableFont(17, weight: .regular, relativeTo: .subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 70)
        .padding(.bottom, 100)
        }
    }

    private func finish() {
        onFinished()
    }
}

#Preview {
    WelcomeCarouselView(onFinished: {})
}
