import Metal
import Foundation
import Testing
@testable import MondayMetal

@Test @MainActor func transientTargetsPreserveSamplesAndDiscardOnlyUnneededAttachments() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let targets = try RenderTargets(device: device, width: 760, height: 1000)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 760, height: 1000, mipmapped: false)
    descriptor.usage = [.renderTarget, .shaderRead]
    let resolved = try #require(device.makeTexture(descriptor: descriptor))
    let pass = targets.pass(resolvingTo: resolved)
    for texture in [targets.color, targets.depth] {
        #expect(texture.sampleCount == 4)
        #expect(texture.storageMode == (device.supportsFamily(.apple2) ? .memoryless : .private))
        #expect(texture.usage == .renderTarget)
        #expect(texture.width == 760 && texture.height == 1000)
    }
    #expect(pass.colorAttachments[0].resolveTexture === resolved)
    #expect(pass.colorAttachments[0].storeAction == .multisampleResolve)
    #expect(pass.depthAttachment.storeAction == .dontCare)
    #expect(targets.matches(resolved))
    descriptor.width = 380
    #expect(!targets.matches(try #require(device.makeTexture(descriptor: descriptor))))
    let fallback = try RenderTargets(device: device, width: 760, height: 1000, storageMode: .private)
    #expect(fallback.color.storageMode == .private)
    #expect(fallback.depth.storageMode == .private)
    if device.supportsFamily(.apple2) {
        #expect(targets.color.allocatedSize + targets.depth.allocatedSize < fallback.color.allocatedSize + fallback.depth.allocatedSize)
    }
}

@Test @MainActor func inFlightPassesKeepTheirOwnResolvesAcrossTargetReuseAndResizing() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let queue = try #require(device.makeCommandQueue())
    let modes: [MTLStorageMode] = device.supportsFamily(.apple2) ? [.private, .memoryless] : [.private]
    for mode in modes {
        for batch in 0..<12 {
            let width = batch % 2 == 0 ? 257 : 131
            let height = batch % 2 == 0 ? 263 : 137
            let work = try autoreleasepool { () -> [(MTLCommandBuffer, MTLTexture, [UInt8])] in
                let targets = try RenderTargets(device: device, width: width, height: height, storageMode: mode)
                return try (0..<3).map { index in
                    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
                    descriptor.storageMode = .shared
                    descriptor.usage = [.renderTarget, .shaderRead]
                    let texture = try #require(device.makeTexture(descriptor: descriptor))
                    let pass = targets.pass(resolvingTo: texture)
                    pass.colorAttachments[0].clearColor = MTLClearColorMake(index == 0 ? 1 : 0, index == 1 ? 1 : 0, index == 2 ? 1 : 0, 1)
                    let command = try #require(queue.makeCommandBuffer())
                    let encoder = try #require(command.makeRenderCommandEncoder(descriptor: pass))
                    encoder.endEncoding()
                    command.commit()
                    let expected: [UInt8] = [index == 2 ? 255 : 0, index == 1 ? 255 : 0, index == 0 ? 255 : 0, 255]
                    return (command, texture, expected)
                }
            }
            for (command, texture, expected) in work {
                command.waitUntilCompleted()
                #expect(command.status == .completed)
                for (x, y) in [(0, 0), (width / 2, height / 2), (width - 1, height - 1)] {
                    var pixel = [UInt8](repeating: 0, count: 4)
                    pixel.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0) }
                    #expect(pixel == expected)
                }
            }
        }
    }
}
