import MondayCore
import simd

public struct RenderCamera {
    public var yaw: Float = 0
    public var zoom: Float = 1
    public var presentationOffset = SIMD2<Float>.zero
    public var bounds: Bounds3

    public init(bounds: Bounds3) { self.bounds = bounds }

    public mutating func fit(aspect: Float, margin: Float = 1.03) {
        let aspect = max(aspect, 0.1)
        let view = Matrix4.lookAt(eye: eye, target: bounds.center)
        var projected = Bounds3()
        for x in [bounds.minimum.x, bounds.maximum.x] {
            for y in [bounds.minimum.y, bounds.maximum.y] {
                for z in [bounds.minimum.z, bounds.maximum.z] {
                    projected.include(view.point(Vector3(x, y, z)))
                }
            }
        }
        let height = max(projected.size.y, projected.size.x / aspect) * max(margin, 1)
        let standardHeight = max(bounds.size.y, max(bounds.size.x, bounds.size.z) / aspect) * 1.16
        zoom = standardHeight / max(height, 0.001)
    }

    public var eye: Vector3 {
        bounds.center + Vector3(sin(yaw) * 5, 0.35, cos(yaw) * 5)
    }

    public func matrix(aspect: Float) -> Matrix4 {
        let height = max(bounds.size.y * 1.16, max(bounds.size.x, bounds.size.z) / max(aspect, 0.1) * 1.16) / max(zoom, 0.1)
        var projection = Matrix4.orthographic(width: height * aspect, height: height, near: 0.01, far: 30)
        projection.columns.3.x += presentationOffset.x
        projection.columns.3.y += presentationOffset.y
        return projection * Matrix4.lookAt(eye: eye, target: bounds.center)
    }
}
