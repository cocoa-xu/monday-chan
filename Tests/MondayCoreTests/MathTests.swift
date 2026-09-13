import Testing
import simd
@testable import MondayCore

@Test func reflectedTransformRoundTrips() {
    let source = Transform(translation: Vector3(2, 3, 4), rotation: Quaternion(angle: 0.7, axis: Vector3(0, 1, 0)), scale: Vector3(-1, 2, 3))
    let restored = Transform(matrix: source.matrix)
    let point = Vector3(0.4, -1, 2)
    #expect(simd_distance(source.matrix.point(point), restored.matrix.point(point)) < 0.00001)
}

@Test func metalDepthMapsNearAndFarToZeroAndOne() {
    let projection = Matrix4.orthographic(width: 3, height: 4, near: 0.1, far: 10)
    #expect(abs(projection.point(Vector3(0, 0, -0.1)).z) < 0.00001)
    #expect(abs(projection.point(Vector3(0, 0, -10)).z - 1) < 0.00001)
}
