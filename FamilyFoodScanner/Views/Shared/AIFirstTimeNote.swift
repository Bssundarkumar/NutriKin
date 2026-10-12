import SwiftUI

/// Shown once, the first time anyone sees an AI button, so nobody has to guess what "AI" or "sparkles" means here.
/// Dismissing it is permanent (stored on the phone); it never blocks using the button underneath.
struct AIFirstTimeNote: View {
    @AppStorage("seenAIIntro") private var seen = false

    var body: some View {
        if !seen {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Theme.brand)
                VStack(alignment: .leading, spacing: 4) {
                    Text("What's the sparkle icon?").readableFont(17, weight: .semibold, relativeTo: .subheadline)
                    Text("It's an optional AI helper — on your iPhone, or your own account. Nothing is sent unless you tap it, and every answer is clearly marked \u{201C}Written by AI\u{201D}.")
                        .readableFont(15, weight: .regular, relativeTo: .caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button { withAnimation(.snappy) { seen = true } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Dismiss")
            }
            .padding(12)
            .background(Theme.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }
}
