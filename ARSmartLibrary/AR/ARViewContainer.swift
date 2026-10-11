import RealityKit
import SwiftUI

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var controller: ARSessionController
    let viewportSize: CGSize

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.renderOptions.insert(.disableMotionBlur)
        controller.attach(to: arView)
        controller.updateViewportSize(viewportSize)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        controller.updateViewportSize(viewportSize)
    }
}
