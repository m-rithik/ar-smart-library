import SwiftUI

struct NavigationArrowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double
    let bearingDegrees: Double

    init(bearingDegrees: Double) {
        self.bearingDegrees = bearingDegrees
        _rotation = State(initialValue: bearingDegrees)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(220, min(geometry.size.width, geometry.size.height) * 0.88)
            ArrowShape()
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
                .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, lifted in
                    content.offset(y: lifted ? -size * 0.035 : 0)
                } animation: { _ in
                    .easeInOut(duration: 0.9)
                }
                .rotationEffect(.degrees(rotation))
                .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: rotation)
                .shadow(color: .black.opacity(0.7), radius: 6, y: 3)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .onChange(of: bearingDegrees) { _, bearing in
            rotation = NavigationArrowRotation.angle(from: rotation, to: bearing)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.height * 0.84))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height * 0.16))
        path.move(to: CGPoint(x: rect.width * 0.23, y: rect.height * 0.43))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.width * 0.77, y: rect.height * 0.43))
        return path
    }
}
