import Foundation
import Metal
import MondayCore

final class UnityTextureDecoder {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              device.supportsFamily(.apple2) || device.supportsFamily(.metal3),
              let queue = device.makeCommandQueue() else { throw AssetError.missing("ASTC-capable Metal device") }
        self.device = device
        self.queue = queue
        guard let shaderURL = MondayImportResources.bundle.url(forResource: "MondayImport", withExtension: "metallib") else {
            throw AssetError.missing("texture decoder shaders")
        }
        let library = try device.makeLibrary(URL: shaderURL)
        guard let function = library.makeFunction(name: "decodeASTC") else { throw AssetError.invalid("ASTC decoder shader") }
        pipeline = try device.makeComputePipelineState(function: function)
    }

    func decode(texture: UnityValue, bundle: UnityAssetBundle) throws -> RGBAImage {
        let width = try texture.requiredInt("m_Width")
        let height = try texture.requiredInt("m_Height")
        let format = try texture.requiredInt("m_TextureFormat")
        var data = texture["image data"]?.bytes ?? Data()
        if data.isEmpty {
            let stream = try texture.required("m_StreamData")
            let offset = try stream.requiredInt("offset")
            let size = try stream.requiredInt("size")
            let path = try stream.requiredString("path")
            let resource = try bundle.externalResourceData(named: (path as NSString).lastPathComponent)
            guard offset >= 0, size > 0, offset <= resource.count, size <= resource.count - offset else {
                throw AssetError.invalid("texture stream range")
            }
            data = resource.subdata(in: offset..<(offset + size))
        }
        return try decode(width: width, height: height, format: format, data: data)
    }

    func decode(width: Int, height: Int, format: Int, data: Data) throws -> RGBAImage {
        guard width > 0, height > 0, width <= 8192, height <= 8192 else { throw AssetError.invalid("texture dimensions") }
        if format == 4 {
            guard data.count >= width * height * 4 else { throw AssetError.invalid("RGBA texture bytes") }
            var flipped = Data(capacity: width * height * 4)
            for row in (0..<height).reversed() {
                flipped.append(data[(row * width * 4)..<((row + 1) * width * 4)])
            }
            return try RGBAImage(width: width, height: height, pixels: flipped)
        }
        guard format == 50 else { throw AssetError.invalid("unsupported texture format \(format)") }
        let rowBytes = ((width + 5) / 6) * 16
        let length = rowBytes * ((height + 5) / 6)
        guard data.count >= length else { throw AssetError.invalid("ASTC texture bytes") }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .astc_6x6_ldr,
                                                                  width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw AssetError.invalid("ASTC texture") }
        data.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: bytes.baseAddress!, bytesPerRow: rowBytes)
        }
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                        width: width, height: height, mipmapped: false)
        outputDescriptor.storageMode = .shared
        outputDescriptor.usage = .shaderWrite
        guard let output = device.makeTexture(descriptor: outputDescriptor),
              let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            throw AssetError.invalid("ASTC decode command")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(output, index: 1)
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { throw command.error ?? AssetError.invalid("ASTC decoding") }
        var pixels = Data(count: width * height * 4)
        pixels.withUnsafeMutableBytes {
            output.getBytes($0.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return try RGBAImage(width: width, height: height, pixels: pixels)
    }
}
