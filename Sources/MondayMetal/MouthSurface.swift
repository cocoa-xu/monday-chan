import MondayCore
import MetalKit
import simd

final class MouthSurface {
    let head: Int
    let local: Matrix4
    let vertices: MTLBuffer
    let vertexCount: Int
    let textures: [Int: MTLTexture]

    init(device: MTLDevice, rig: CharacterRig, library: AssetLibrary, character: CharacterDescriptor,
         indices: Set<Int>? = nil, conformToFace: Bool = false) throws {
        guard let head = rig.node("jnt_C_head00_00"), let anchor = rig.node("Mouth") else { throw AssetError.missing("mouth attachment") }
        self.head = head
        let catalog = try library.mouths(for: character)
        var position = rig.world[anchor].position
        var front: Float = -.infinity
        var faceTriangles: [[Vector3]] = []
        for primitive in rig.model.primitives where primitive.name.contains("Body") || primitive.name.contains("Eye") {
            let points = rig.positions(for: primitive)
            for offset in stride(from: 0, to: primitive.indices.count, by: 3) {
                let a = points[Int(primitive.indices[offset])], b = points[Int(primitive.indices[offset + 1])], c = points[Int(primitive.indices[offset + 2])]
                if conformToFace { faceTriangles.append([a, b, c]) }
                let denominator = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
                if abs(denominator) < 0.0000001 { continue }
                let u = ((b.y - c.y) * (position.x - c.x) + (c.x - b.x) * (position.y - c.y)) / denominator
                let v = ((c.y - a.y) * (position.x - c.x) + (a.x - c.x) * (position.y - c.y)) / denominator
                if u >= 0, v >= 0, u + v <= 1 { front = max(front, u * a.z + v * b.z + (1 - u - v) * c.z) }
            }
        }
        if front.isFinite { position.z = front + 0.001 }
        local = simd_inverse(rig.world[head]) * Transform(translation: position).matrix
        let width = catalog.projector_size.x / 2, height = catalog.projector_size.y / 2
        let corners: [(Float, Float, Float, Float)] = [(-width, -height, 0, 1), (width, -height, 1, 1), (-width, height, 0, 0),
                                                      (-width, height, 0, 0), (width, -height, 1, 1), (width, height, 1, 0)]
        let plane = corners.map { MeshVertex(position: SIMD4($0.0, $0.1, 0, 1), uv: SIMD4($0.2, $0.3, 0, 0)) }
        let projected = conformToFace ? Self.project(faceTriangles, around: position, halfSize: SIMD2(width, height)) : []
        let mesh = projected.isEmpty ? plane : projected
        vertices = CharacterRenderScene.buffer(device, mesh)
        vertexCount = mesh.count
        let loader = MTKTextureLoader(device: device)
        textures = try Dictionary(uniqueKeysWithValues: catalog.cells.filter { indices?.contains($0.value) ?? true }.map { name, index in
            let texture = try loader.newTexture(URL: library.url(for: character.mouths + name + ".png"), options: [.SRGB: true, .origin: MTKTextureLoader.Origin.topLeft.rawValue])
            return (index, texture)
        })
    }

    private static func project(_ triangles: [[Vector3]], around center: Vector3, halfSize: SIMD2<Float>) -> [MeshVertex] {
        let polygons = triangles.compactMap { triangle -> [Vector3]? in
            var polygon = triangle
            for axis in 0...1 {
                polygon = clip(polygon, axis: axis, boundary: center[axis] - halfSize[axis], keepGreater: true)
                polygon = clip(polygon, axis: axis, boundary: center[axis] + halfSize[axis], keepGreater: false)
            }
            return polygon.count >= 3 ? polygon : nil
        }
        func vertex(_ point: Vector3) -> MeshVertex {
            let local = point - center
            return MeshVertex(position: SIMD4(local + Vector3(0, 0, 0.001), 1),
                              uv: SIMD4(local.x / (halfSize.x * 2) + 0.5, 0.5 - local.y / (halfSize.y * 2), 0, 0))
        }
        var vertices: [MeshVertex] = []
        for polygon in polygons {
            let midpoint = polygon.reduce(Vector3.zero, +) / Float(polygon.count)
            let front = triangles.compactMap { depth(at: midpoint, triangle: $0) }.max() ?? midpoint.z
            guard abs(front - midpoint.z) < 0.0001 else { continue }
            for index in 1..<(polygon.count - 1) {
                vertices += [vertex(polygon[0]), vertex(polygon[index]), vertex(polygon[index + 1])]
            }
        }
        return vertices
    }

    private static func clip(_ polygon: [Vector3], axis: Int, boundary: Float, keepGreater: Bool) -> [Vector3] {
        guard var previous = polygon.last else { return [] }
        func inside(_ point: Vector3) -> Bool { keepGreater ? point[axis] >= boundary : point[axis] <= boundary }
        var output: [Vector3] = []
        for point in polygon {
            if inside(point) != inside(previous) {
                let fraction = (boundary - previous[axis]) / (point[axis] - previous[axis])
                output.append(previous + (point - previous) * fraction)
            }
            if inside(point) { output.append(point) }
            previous = point
        }
        return output
    }

    private static func depth(at point: Vector3, triangle: [Vector3]) -> Float? {
        let a = triangle[0], b = triangle[1], c = triangle[2]
        let denominator = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
        guard abs(denominator) > 0.0000001 else { return nil }
        let u = ((b.y - c.y) * (point.x - c.x) + (c.x - b.x) * (point.y - c.y)) / denominator
        let v = ((c.y - a.y) * (point.x - c.x) + (a.x - c.x) * (point.y - c.y)) / denominator
        return u >= -0.00001 && v >= -0.00001 && u + v <= 1.00001 ? u * a.z + v * b.z + (1 - u - v) * c.z : nil
    }
}
