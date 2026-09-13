import Foundation
import MondayCore
import Metal
import Testing
@testable import MondayMetal

@Test func coverageBuffersStayImmutableWhileReadersRetainThem() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let pool = CoverageReadbackPool(device: device)
    var retained: [CoverageMask] = []
    for value in 1...12 {
        let readback = pool.acquire(width: 64, height: 64)
        readback.buffer.contents().initializeMemory(as: UInt8.self, repeating: UInt8(value), count: 4096)
        retained.append(readback.mask)
    }
    for (index, mask) in retained.enumerated() {
        #expect(mask.alpha == Data(repeating: UInt8(index + 1), count: 4096))
    }
    retained.removeAll()
    var address: UInt = 0
    autoreleasepool {
        let readback = pool.acquire(width: 64, height: 64)
        address = UInt(bitPattern: readback.buffer.contents())
    }
    let reused = pool.acquire(width: 64, height: 64)
    #expect(UInt(bitPattern: reused.buffer.contents()) == address)
    #expect(pool.acquire(width: 128, height: 128).mask.alpha.count == 16384)
}

@Test(.enabled(if: localAssetsAvailable)) @MainActor
func concurrentGPUCoverageRemainsImmutableAfterResolveAndResize() throws {
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let renderer = try CharacterRenderer(model: CharacterModel(url: library.url(for: "models/06002.glb")))
    var retained: [(CoverageMask, Data)] = []
    for width in [127, 127, 257, 131] {
        let work = try autoreleasepool { () -> [(MTLCommandBuffer, CoverageMask, Data)] in
            let targets = try RenderTargets(device: renderer.device, width: width, height: 137)
            return try (0..<3).map { index in
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: 137, mipmapped: false)
                descriptor.storageMode = .private
                descriptor.usage = [.renderTarget, .shaderRead]
                let texture = try #require(renderer.device.makeTexture(descriptor: descriptor))
                let pass = targets.pass(resolvingTo: texture)
                pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, Double(index) / 2)
                let command = try #require(renderer.queue.makeCommandBuffer())
                let encoder = try #require(command.makeRenderCommandEncoder(descriptor: pass))
                encoder.endEncoding()
                let readback = try #require(renderer.encodeCoverage(command: command, texture: texture))
                command.commit()
                let expected = Data(repeating: [UInt8(0), 128, 255][index], count: width * 137)
                return (command, readback.mask, expected)
            }
        }
        for (command, mask, expected) in work {
            command.waitUntilCompleted()
            #expect(command.status == .completed)
            #expect(mask.alpha == expected)
            retained.append((mask, expected))
        }
    }
    for (mask, expected) in retained { #expect(mask.alpha == expected) }
}

@Test(.enabled(if: localAssetsAvailable)) @MainActor
func coveragePreservesEveryRenderedAlphaAcrossFramesAndResizes() throws {
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let renderer = try CharacterRenderer(model: CharacterModel(url: library.url(for: "models/06002.glb")))
    var retained: [(CoverageMask, Data)] = []
    for (index, size) in [240, 240, 240, 240, 480, 240].enumerated() {
        renderer.camera.yaw = Float(index) * 0.6
        let pixels = try renderer.snapshot(width: size, height: size, captureCoverage: true)
        let expected = Data(stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] })
        let mask = try #require(renderer.coverage)
        #expect(mask.alpha == expected)
        retained.append((mask, expected))
    }
    for (mask, expected) in retained { #expect(mask.alpha == expected) }
}
