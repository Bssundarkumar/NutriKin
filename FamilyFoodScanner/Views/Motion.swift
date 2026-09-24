import SwiftUI

/// Small, consistent motion used across the app. Everything here respects the
/// system "Reduce Motion" setting by showing the final state immediately.

/// Fades and lifts a view in, one after another when several share a screen.
private struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true; return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.06 * Double(min(index, 10)))) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Fade and rise in on appear; `index` staggers items that appear together.
    func staggeredAppear(_ index: Int = 0) -> some View { modifier(StaggeredAppear(index: index)) }
}

/// Springs slightly smaller while pressed, for custom (non-system) buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Pops in with a spring; used for the logo on sign-in and onboarding.
private struct PopIn: ViewModifier {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.7)
            .opacity(shown ? 1 : 0)
            .onAppear {
                if reduceMotion { shown = true }
                else { withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { shown = true } }
            }
    }
}

extension View {
    func popIn() -> some View { modifier(PopIn()) }
}

/// A slow, gentle bob for a hero image such as the logo.
private struct Floating: ViewModifier {
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: up ? -6 : 6)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { up = true }
            }
    }
}

extension View {
    func floating() -> some View { modifier(Floating()) }
}

/// Slides between steps of a flow (e.g. email, then code).
extension AnyTransition {
    static var step: AnyTransition {
        .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity))
    }
}

/// Four corner marks that gently "breathe", telling people where to aim the barcode.
struct ScannerFrame: View {
    @State private var breathe = false
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CornerBrackets(length: 30, radius: 12)
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            .frame(width: 250, height: 150)
            .overlay {
                Capsule()
                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 210, height: 3)
                    .shadow(color: .white.opacity(0.8), radius: 6)
                    .offset(y: sweep ? 58 : -58)
                    .opacity(reduceMotion ? 0 : 1)
            }
            .scaleEffect(breathe ? 1.04 : 0.97)
            .shadow(color: .black.opacity(0.35), radius: 4)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathe = true }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { sweep = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct CornerBrackets: Shape {
    let length: CGFloat
    let radius: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        let l = length, c = radius
        // top-left
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        // top-right
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + c), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        // bottom-right
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        // bottom-left
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - c), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}
