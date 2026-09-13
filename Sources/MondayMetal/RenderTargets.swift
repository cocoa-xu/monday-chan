import MondayCore
import Metal

final class RenderTargets {
    let color: MTLTexture
    let depth: MTLTexture

    init(device: MTLDevice, width: Int, height: Int, storageMode: MTLStorageMode? = nil) throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        descriptor.textureType = .type2DMultisample
        descriptor.sampleCount = CharacterRenderScene.sampleCount
        descriptor.storageMode = storageMode ?? (device.supportsFamily(.apple2) ? .memoryless : .private)
        descriptor.usage = .renderTarget
        guard let color = device.makeTexture(descriptor: descriptor) else { throw AssetError.missing("multisample color target") }
        self.color = color
        descriptor.pixelFormat = .depth32Float
        guard let depth = device.makeTexture(descriptor: descriptor) else { throw AssetError.missing("multisample depth target") }
        self.depth = depth
        color.label = "Monday-chan multisample color"
        depth.label = "Monday-chan depth"
    }

    func matches(_ texture: MTLTexture) -> Bool { color.width == texture.width && color.height == texture.height }

    func pass(resolvingTo texture: MTLTexture) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].resolveTexture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        return pass
    }
}
