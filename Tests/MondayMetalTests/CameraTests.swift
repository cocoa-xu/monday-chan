import CoreGraphics
import MondayCore
import MondayMetal
import simd
import Testing

@Test func projectionPreservesEqualHorizontalAndVerticalLengthsInPixels() {
    var bounds = Bounds3()
    bounds.include(Vector3(-0.6, 0, -0.3))
    bounds.include(Vector3(0.6, 1.4, 0.3))
    for yaw: Float in [0, .pi / 3, -.pi / 2] {
        var camera = RenderCamera(bounds: bounds)
        camera.yaw = yaw
        let forward = simd_normalize(camera.eye - bounds.center)
        let right = simd_normalize(simd_cross(Vector3(0, 1, 0), forward))
        let up = simd_cross(forward, right)
        for size in [CGSize(width: 95, height: 125), CGSize(width: 821, height: 1080), CGSize(width: 1915, height: 2160)] {
            let projection = camera.matrix(aspect: Float(size.width / size.height))
            let origin = projection.point(bounds.center)
            let horizontal = projection.point(bounds.center + right * 0.1) - origin
            let vertical = projection.point(bounds.center + up * 0.1) - origin
            let horizontalPixels = simd_length(SIMD2(horizontal.x * Float(size.width), horizontal.y * Float(size.height)))
            let verticalPixels = simd_length(SIMD2(vertical.x * Float(size.width), vertical.y * Float(size.height)))
            #expect(abs(horizontalPixels - verticalPixels) < 0.001)
        }
    }
}

@Test func fittedCameraContainsProjectedBoundsAcrossDisplayShapes() {
    var bounds = Bounds3()
    bounds.include(Vector3(-1.2, -0.15, -0.8))
    bounds.include(Vector3(0.9, 2.35, 0.65))
    for aspect: Float in [9 / 16, 16 / 9, 32 / 9] {
        for yaw: Float in [0, .pi / 3, -.pi / 2] {
            var camera = RenderCamera(bounds: bounds)
            camera.yaw = yaw
            camera.fit(aspect: aspect)
            let projection = camera.matrix(aspect: aspect)
            for corner in corners(of: bounds) {
                let point = projection.point(corner)
                #expect(abs(point.x) <= 1)
                #expect(abs(point.y) <= 1)
            }
        }
    }
}

@Test func fittedCameraUsesOneProportionalScaleForNegativeOriginPortraitAndWideDisplays() {
    var bounds = Bounds3()
    bounds.include(Vector3(-0.75, -0.2, -0.4))
    bounds.include(Vector3(0.95, 2.1, 0.55))
    let displays = [
        CGRect(x: -1080, y: -220, width: 1080, height: 1920),
        CGRect(x: -3440, y: 180, width: 3440, height: 1440)
    ]
    for display in displays {
        let aspect = Float(display.width / display.height)
        var camera = RenderCamera(bounds: bounds)
        camera.fit(aspect: aspect)
        let projection = camera.matrix(aspect: aspect)
        let forward = simd_normalize(camera.eye - bounds.center)
        let right = simd_normalize(simd_cross(Vector3(0, 1, 0), forward))
        let up = simd_cross(forward, right)
        let center = projection.point(bounds.center)
        let horizontal = projection.point(bounds.center + right * 0.1) - center
        let vertical = projection.point(bounds.center + up * 0.1) - center
        let horizontalPixels = simd_length(SIMD2(horizontal.x * Float(display.width), horizontal.y * Float(display.height)))
        let verticalPixels = simd_length(SIMD2(vertical.x * Float(display.width), vertical.y * Float(display.height)))
        #expect(abs(horizontalPixels - verticalPixels) < 0.001)
    }
}

private func corners(of bounds: Bounds3) -> [Vector3] {
    [bounds.minimum.x, bounds.maximum.x].flatMap { x in
        [bounds.minimum.y, bounds.maximum.y].flatMap { y in
            [bounds.minimum.z, bounds.maximum.z].map { z in Vector3(x, y, z) }
        }
    }
}
