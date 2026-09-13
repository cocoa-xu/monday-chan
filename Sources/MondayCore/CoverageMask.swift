import Foundation
import CoreGraphics

public struct CoverageMask: Sendable {
    public let width: Int
    public let height: Int
    public let alpha: Data

    public init(width: Int, height: Int, alpha: Data) {
        self.width = width
        self.height = height
        self.alpha = alpha
    }

    public func contains(normalizedX x: Double, normalizedY y: Double, threshold: UInt8 = 16) -> Bool {
        guard x.isFinite, y.isFinite, x >= 0, x < 1, y >= 0, y < 1,
              width > 0, height > 0, alpha.count == width * height else { return false }
        return alpha[Int(y * Double(height)) * width + Int(x * Double(width))] > threshold
    }

    public func contains(point: CGPoint, in size: CGSize) -> Bool {
        guard width > 0, height > 0, size.width > 0, size.height > 0 else { return false }
        let scale = min(size.width / Double(width), size.height / Double(height))
        let fittedWidth = Double(width) * scale
        let fittedHeight = Double(height) * scale
        let x = (point.x - (size.width - fittedWidth) / 2) / fittedWidth
        let y = 1 - (point.y - (size.height - fittedHeight) / 2) / fittedHeight
        return contains(normalizedX: x, normalizedY: y)
    }
}
