import ARKit
import SceneKit
import SwiftUI

/// Small helpers for turning two points in space into a plate diameter. Pure, so they're tested.
enum PlateMeasure {
    static let plausible = 10.0...45.0
    static func centimetres(from a: SIMD3<Float>, to b: SIMD3<Float>) -> Double { Double(simd_distance(a, b)) * 100 }
    static func isPlausible(_ cm: Double) -> Bool { plausible.contains(cm) }
}

/// Measures a plate with the camera: tap one edge, then the opposite edge. Uses ARKit (what Apple's own
/// Measure app is built on) to find the table and read real distances. Accurate to about a centimetre or two;
/// iPhones with LiDAR do better.
struct PlateMeasureView: View {
    /// Called with the measured diameter in whole centimetres.
    var onUse: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var centimetres: Double?
    @State private var status = "Hold your iPhone over the plate and move slowly until the table is found."
    @State private var resetToken = 0

    /// ARKit needs a real camera, so this is false in the Simulator.
    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    private var usable: Int? {
        guard let cm = centimetres, PlateMeasure.isPlausible(cm) else { return nil }
        return Int(cm.rounded())
    }

    var body: some View {
        ZStack {
            MeasureARView(centimetres: $centimetres, status: $status, resetToken: resetToken)
                .ignoresSafeArea()

            VStack {
                Text(status)
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
                    .padding(.top, 12).padding(.horizontal, 20)
                Spacer()
                VStack(spacing: 12) {
                    if let cm = centimetres {
                        Text(String(format: "%.1f cm", cm))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                    HStack(spacing: 10) {
                        Button("Cancel") { dismiss() }
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .background(.black.opacity(0.55), in: Capsule())
                        Button("Reset") { centimetres = nil; resetToken += 1 }
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .background(.black.opacity(0.55), in: Capsule())
                        Button { if let cm = usable { onUse(cm); dismiss() } } label: {
                            Text(usable.map { "Use \($0) cm" } ?? "Tap both edges")
                                .padding(.horizontal, 18).padding(.vertical, 11)
                                .background(usable == nil ? AnyShapeStyle(.gray.opacity(0.6)) : AnyShapeStyle(Theme.brandGradient), in: Capsule())
                        }
                        .disabled(usable == nil)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                }
                .padding(.bottom, 28)
            }
        }
    }
}

private struct MeasureARView: UIViewRepresentable {
    @Binding var centimetres: Double?
    @Binding var status: String
    var resetToken: Int

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.automaticallyUpdatesLighting = true
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        view.session.run(config)
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        if context.coordinator.lastReset != resetToken {
            context.coordinator.lastReset = resetToken
            context.coordinator.reset()
        }
    }

    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) { view.session.pause() }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: MeasureARView
        weak var view: ARSCNView?
        var lastReset = 0
        private var points: [SIMD3<Float>] = []
        private var nodes: [SCNNode] = []

        init(_ parent: MeasureARView) { self.parent = parent }

        func reset() {
            nodes.forEach { $0.removeFromParentNode() }
            nodes = []; points = []
            parent.status = "Tap one edge of the plate."
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let location = gesture.location(in: view)
            guard let query = view.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal),
                  let hit = view.session.raycast(query).first else {
                parent.status = "Couldn't find the table there. Move slowly, then tap the plate's edge again."
                return
            }
            if points.count == 2 { reset(); parent.centimetres = nil }
            let t = hit.worldTransform.columns.3
            let point = SIMD3<Float>(t.x, t.y, t.z)
            points.append(point)
            add(dotAt: point, in: view)

            guard points.count == 2 else { parent.status = "Now tap the opposite edge, straight across."; return }
            add(lineFrom: points[0], to: points[1], in: view)
            let cm = PlateMeasure.centimetres(from: points[0], to: points[1])
            parent.centimetres = cm
            parent.status = PlateMeasure.isPlausible(cm)
                ? "Looks right? Use it, or Reset to measure again."
                : "That doesn't look like a plate size. Reset and tap two opposite edges."
        }

        private func add(dotAt p: SIMD3<Float>, in view: ARSCNView) {
            let sphere = SCNSphere(radius: 0.006)
            sphere.firstMaterial?.diffuse.contents = UIColor.systemGreen
            let node = SCNNode(geometry: sphere)
            node.simdPosition = p
            view.scene.rootNode.addChildNode(node)
            nodes.append(node)
        }

        private func add(lineFrom a: SIMD3<Float>, to b: SIMD3<Float>, in view: ARSCNView) {
            let length = simd_distance(a, b)
            let cylinder = SCNCylinder(radius: 0.0015, height: CGFloat(length))
            cylinder.firstMaterial?.diffuse.contents = UIColor.white
            let node = SCNNode(geometry: cylinder)
            node.simdPosition = (a + b) / 2
            node.look(at: SCNVector3(b.x, b.y, b.z), up: view.scene.rootNode.worldUp, localFront: SCNVector3(0, 1, 0))
            view.scene.rootNode.addChildNode(node)
            nodes.append(node)
        }
    }
}
