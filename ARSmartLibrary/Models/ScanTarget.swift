import CoreGraphics

enum ScanTarget {
    private static let preferredSize = CGSize(width: 210, height: 100)

    static func size(in viewportSize: CGSize) -> CGSize {
        CGSize(
            width: min(preferredSize.width, viewportSize.width * 0.8),
            height: min(preferredSize.height, viewportSize.height * 0.2)
        )
    }

    static func viewRect(in viewportSize: CGSize) -> CGRect {
        let targetSize = size(in: viewportSize)
        return CGRect(
            x: (viewportSize.width - targetSize.width) / 2,
            y: (viewportSize.height - targetSize.height) / 2,
            width: targetSize.width,
            height: targetSize.height
        )
    }

    static func rawImagePoint(
        fromROIVisionPoint point: CGPoint,
        regionOfInterest: CGRect
    ) -> CGPoint {
        let fullVisionPoint = CGPoint(
            x: regionOfInterest.minX + (point.x * regionOfInterest.width),
            y: regionOfInterest.minY + (point.y * regionOfInterest.height)
        )
        return CGPoint(x: 1 - fullVisionPoint.y, y: 1 - fullVisionPoint.x)
    }
}
