import Foundation
import MondayCore
import simd
import Testing
@testable import MondayMetal

@Test(.enabled(if: FileManager.default.fileExists(atPath: "data/models/06002.glb"))) @MainActor
func projectedMouthKeepsItsUpperInteriorInFrontOfTheFace() throws {
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let character = try library.character("06002")
    let renderer = try CharacterRenderer(model: CharacterModel(url: library.url(for: character.model)))
    try renderer.loadMouths(library: library, character: character, conformToFace: true)
    let surface = try MouthSurface(device: renderer.device, rig: renderer.rig, library: library, character: character,
                                   indices: [7], conformToFace: true)
    let point = try projectedPoint(uv: SIMD2(0.5, 0.4), surface: surface)
    let world = (renderer.rig.world[surface.head] * surface.local).point(point)
    for yaw: Float in [0, -0.35, 0.35] {
        renderer.camera.yaw = yaw
        renderer.camera.zoom = 1.5
        let clip = renderer.camera.matrix(aspect: 1).point(world)
        let x = Int((clip.x * 0.5 + 0.5) * 768)
        let y = Int((0.5 - clip.y * 0.5) * 768)
        try #require((1..<767).contains(x) && (1..<767).contains(y))
        for mouth in [7, 17, 35] {
            renderer.mouthIndex = mouth
            let pixels = try renderer.snapshot(width: 768, height: 768)
            let index = (y * 768 + x) * 4
            #expect(Float(pixels[index + 2]) > Float(pixels[index + 1]) * 1.2)
            #expect(pixels[index] > 80)
        }
    }
    renderer.camera.yaw = .pi
    renderer.mouthIndex = nil
    let back = try renderer.snapshot(width: 240, height: 320)
    renderer.mouthIndex = 35
    #expect(try renderer.snapshot(width: 240, height: 320) == back)
}

private func projectedPoint(uv: SIMD2<Float>, surface: MouthSurface) throws -> Vector3 {
    let vertices = surface.vertices.contents().bindMemory(to: MeshVertex.self, capacity: surface.vertexCount)
    for index in stride(from: 0, to: surface.vertexCount, by: 3) {
        let a = vertices[index], b = vertices[index + 1], c = vertices[index + 2]
        let u = SIMD2(b.uv.x - a.uv.x, b.uv.y - a.uv.y)
        let v = SIMD2(c.uv.x - a.uv.x, c.uv.y - a.uv.y)
        let p = uv - SIMD2(a.uv.x, a.uv.y)
        let determinant = u.x * v.y - u.y * v.x
        guard abs(determinant) > 0.000001 else { continue }
        let s = (p.x * v.y - p.y * v.x) / determinant
        let t = (u.x * p.y - u.y * p.x) / determinant
        if s >= 0, t >= 0, s + t <= 1 {
            return a.position.xyz * (1 - s - t) + b.position.xyz * s + c.position.xyz * t
        }
    }
    throw AssetError.invalid("projected mouth UV coverage")
}
