import MondayCore

public struct BoardAttachment: Equatable, Sendable {
    public var anchorNode: String
    public var size: SIMD2<Float>
    public var offset: Vector3
    public var rotation: Vector3
    public var isVisible: Bool

    public init(anchorNode: String, size: SIMD2<Float>, offset: Vector3, rotation: Vector3 = .zero, isVisible: Bool = true) {
        self.anchorNode = anchorNode
        self.size = size
        self.offset = offset
        self.rotation = rotation
        self.isVisible = isVisible
    }
}
