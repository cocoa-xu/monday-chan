import MondayCore
import MetalKit

final class RendererResources {
    let pipeline: MTLRenderPipelineState
    let coveragePipeline: MTLComputePipelineState
    let depthWrite: MTLDepthStencilState
    let depthRead: MTLDepthStencilState
    let sampler: MTLSamplerState
    let fallbackTexture: MTLTexture

    init(device: MTLDevice) throws {
        let bundle = Bundle.main.url(forResource: "MondayChan_MondayMetal", withExtension: "bundle").flatMap(Bundle.init(url:)) ?? Bundle.module
        guard let shaderURL = bundle.url(forResource: "MondayMetal", withExtension: "metallib") else {
            throw AssetError.missing("character shaders")
        }
        let library = try device.makeLibrary(URL: shaderURL)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "characterVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "characterFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.rasterSampleCount = CharacterRenderScene.sampleCount
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        coveragePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "extractCoverage")!)
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .lessEqual
        depth.isDepthWriteEnabled = true
        depthWrite = device.makeDepthStencilState(descriptor: depth)!
        depth.isDepthWriteEnabled = false
        depthRead = device.makeDepthStencilState(descriptor: depth)!
        let sampling = MTLSamplerDescriptor()
        sampling.minFilter = .linear
        sampling.magFilter = .linear
        sampling.mipFilter = .linear
        sampling.sAddressMode = .repeat
        sampling.tAddressMode = .repeat
        sampler = device.makeSamplerState(descriptor: sampling)!
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: 1, height: 1, mipmapped: false)
        fallbackTexture = device.makeTexture(descriptor: textureDescriptor)!
        var pixel: UInt32 = .max
        fallbackTexture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)
    }
}
