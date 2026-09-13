import Foundation
import MondayCore
import MetalKit
import simd

private struct DrawUniforms {
    var viewProjection: Matrix4
    var model: Matrix4
    var color: SIMD4<Float>
    var parameters: SIMD4<Float>
    var alphaMode: UInt32
}

private struct RenderPrimitive {
    let source: CharacterPrimitive
    let vertices: MTLBuffer
    let indices: MTLBuffer
    let morphs: MTLBuffer
    var influences: [MorphInfluence] = []
}

private struct BoardMesh {
    let frontVertices: MTLBuffer
    let frontIndices: MTLBuffer
    let shellVertices: MTLBuffer
    let shellIndices: MTLBuffer
    let texture: MTLTexture
    var attachment: BoardAttachment
    var anchorNode: Int
    var restAnchorInverse: Matrix4
}

final class CharacterRenderScene {
    static let sampleCount = 4
    let device: MTLDevice
    let queue: MTLCommandQueue
    let rig: CharacterRig
    var camera: RenderCamera
    var faceWeights: [String: Float] = [:] {
        didSet {
            guard faceWeights != oldValue else { return }
            for index in primitives.indices {
                primitives[index].influences = MorphInfluence.active(names: primitives[index].source.morphNames, weights: faceWeights)
            }
        }
    }
    var mouthIndex: Int? = 0
    let resources: RendererResources
    private let textures: [MTLTexture]
    private var primitives: [RenderPrimitive]
    private let jointOffsets: [Int]
    private let jointBufferLength: Int
    private var mouth: MouthSurface?
    private var board: BoardMesh?

    var boardAttachment: BoardAttachment? {
        get { board?.attachment }
        set {
            guard var current = board else { return }
            guard let newValue else {
                current.attachment.isVisible = false
                board = current
                return
            }
            guard let node = rig.node(newValue.anchorNode) else { return }
            if newValue.anchorNode != current.attachment.anchorNode {
                current.anchorNode = node
                current.restAnchorInverse = simd_inverse(restWorldTransform(for: node))
            }
            current.attachment = newValue
            board = current
        }
    }

    init(model: CharacterModel, device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device, let queue = device.makeCommandQueue() else { throw AssetError.missing("Metal device") }
        self.device = device
        self.queue = queue
        let rig = try CharacterRig(model: model)
        self.rig = rig
        camera = RenderCamera(bounds: rig.bounds())
        resources = try RendererResources(device: device)
        let loader = MTKTextureLoader(device: device)
        textures = try model.images.map { try loader.newTexture(data: $0, options: [.SRGB: true, .generateMipmaps: true, .origin: MTKTextureLoader.Origin.topLeft.rawValue]) }
        let buffers = ImmutableBufferCache(device: device)
        primitives = model.primitives.map { source in
            RenderPrimitive(source: source,
                            vertices: buffers.buffer(source.vertices),
                            indices: buffers.buffer(source.indices),
                            morphs: buffers.buffer(source.morphDeltas.isEmpty ? [SIMD4<Float>.zero] : source.morphDeltas))
        }
        var offset = 0
        jointOffsets = model.skins.map { skin in
            defer { offset += skin.joints.count * MemoryLayout<Matrix4>.stride }
            return offset
        }
        jointBufferLength = max(64, offset)
    }

    func makeJointBuffer() -> MTLBuffer {
        device.makeBuffer(length: jointBufferLength, options: .storageModeShared)!
    }

    func loadMouths(library: AssetLibrary, character: CharacterDescriptor, indices: Set<Int>? = nil, conformToFace: Bool = false) throws {
        mouth = try MouthSurface(device: device, rig: rig, library: library, character: character, indices: indices, conformToFace: conformToFace)
    }

    func attachBoard(textureData: Data, attachment: BoardAttachment) throws {
        guard let node = rig.node(attachment.anchorNode) else { throw AssetError.missing("accessory anchor \(attachment.anchorNode)") }
        let loader = MTKTextureLoader(device: device)
        let texture = try loader.newTexture(data: textureData, options: [.SRGB: true, .generateMipmaps: true, .origin: MTKTextureLoader.Origin.topLeft.rawValue])
        let front = [
            MeshVertex(position: SIMD4(-0.5, -0.5, 0.5, 1), uv: SIMD4(0, 1, 0, 0)),
            MeshVertex(position: SIMD4(0.5, -0.5, 0.5, 1), uv: SIMD4(1, 1, 0, 0)),
            MeshVertex(position: SIMD4(0.5, 0.5, 0.5, 1), uv: SIMD4(1, 0, 0, 0)),
            MeshVertex(position: SIMD4(-0.5, 0.5, 0.5, 1), uv: SIMD4(0, 0, 0, 0))
        ]
        let shellPositions: [SIMD3<Float>] = [
            [-0.5,-0.5,-0.5], [0.5,-0.5,-0.5], [0.5,0.5,-0.5], [-0.5,0.5,-0.5],
            [-0.5,-0.5,0.5], [0.5,-0.5,0.5], [0.5,0.5,0.5], [-0.5,0.5,0.5]
        ]
        let shell = shellPositions.map { MeshVertex(position: SIMD4($0, 1), uv: .zero) }
        let shellIndices: [UInt32] = [0,2,1, 0,3,2, 0,4,7, 0,7,3, 1,2,6, 1,6,5, 3,7,6, 3,6,2, 0,1,5, 0,5,4]
        board = BoardMesh(frontVertices: Self.buffer(device, front), frontIndices: Self.buffer(device, [UInt32(0),1,2, 0,2,3]),
                          shellVertices: Self.buffer(device, shell), shellIndices: Self.buffer(device, shellIndices), texture: texture,
                          attachment: attachment, anchorNode: node, restAnchorInverse: simd_inverse(restWorldTransform(for: node)))
    }

    func snapshot(width: Int, height: Int, beforeCommit: ((MTLCommandBuffer, MTLTexture) -> Void)? = nil) throws -> Data {
        let color = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        color.usage = [.renderTarget, .shaderRead]
        color.storageMode = .shared
        let texture = device.makeTexture(descriptor: color)!
        let targets = try RenderTargets(device: device, width: width, height: height)
        let joints = makeJointBuffer()
        let command = queue.makeCommandBuffer()!
        encode(command: command, pass: targets.pass(resolvingTo: texture), width: width, height: height, joints: joints)
        beforeCommit?(command, texture)
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
        return data
    }

    func encode(command: MTLCommandBuffer, pass: MTLRenderPassDescriptor, width: Int, height: Int, joints: MTLBuffer) {
        updateJointPalette(joints)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(resources.pipeline)
        encoder.setCullMode(.none)
        encoder.setFragmentSamplerState(resources.sampler, index: 0)
        var emptyInfluence = MorphInfluence(index: 0, weight: 0)
        encoder.setVertexBytes(&emptyInfluence, length: MemoryLayout<MorphInfluence>.stride, index: 4)
        let projection = camera.matrix(aspect: Float(width) / Float(height))
        for primitive in primitives { drawPrimitive(primitive, with: encoder, projection: projection, joints: joints) }
        drawBoard(with: encoder, projection: projection)
        drawMouth(with: encoder, projection: projection)
        encoder.endEncoding()
    }

    private func drawBoard(with encoder: MTLRenderCommandEncoder, projection: Matrix4) {
        guard let board, board.attachment.isVisible else { return }
        let attachment = board.attachment
        let x = Quaternion(angle: attachment.rotation.x, axis: SIMD3(1, 0, 0))
        let y = Quaternion(angle: attachment.rotation.y, axis: SIMD3(0, 1, 0))
        let z = Quaternion(angle: attachment.rotation.z, axis: SIMD3(0, 0, 1))
        let local = Transform(translation: attachment.offset, rotation: z * y * x,
                              scale: SIMD3(attachment.size.x, attachment.size.y, 0.015)).matrix
        let model = rig.world[board.anchorNode] * board.restAnchorInverse * local
        encoder.setDepthStencilState(resources.depthWrite)
        var uniforms = DrawUniforms(viewProjection: projection, model: model, color: SIMD4(repeating: 1), parameters: .zero,
                                    alphaMode: MaterialAlphaMode.opaque.rawValue)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<DrawUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DrawUniforms>.stride, index: 1)
        encoder.setFragmentTexture(board.texture, index: 0)
        encoder.setVertexBuffer(board.frontVertices, offset: 0, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: 6, indexType: .uint32, indexBuffer: board.frontIndices, indexBufferOffset: 0)
        uniforms.color = SIMD4(0.82, 0.48, 0.015, 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<DrawUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DrawUniforms>.stride, index: 1)
        encoder.setFragmentTexture(resources.fallbackTexture, index: 0)
        encoder.setVertexBuffer(board.shellVertices, offset: 0, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: 30, indexType: .uint32, indexBuffer: board.shellIndices, indexBufferOffset: 0)
    }

    private func updateJointPalette(_ joints: MTLBuffer) {
        rig.updateWorld()
        for index in rig.model.skins.indices {
            let skin = rig.model.skins[index]
            let palette = joints.contents().advanced(by: jointOffsets[index]).bindMemory(to: Matrix4.self, capacity: skin.joints.count)
            for joint in skin.joints.indices { palette[joint] = rig.world[skin.joints[joint]] * skin.inverseBindMatrices[joint] }
        }
    }

    private func drawPrimitive(_ primitive: RenderPrimitive, with encoder: MTLRenderCommandEncoder, projection: Matrix4, joints: MTLBuffer) {
        let source = primitive.source
        let material = source.material.map { rig.model.materials[$0] }
        let alphaMode = material?.alphaMode ?? .opaque
        guard alphaMode != .blend || material?.color.w ?? 1 > 0 else { return }
        encoder.setDepthStencilState(material?.blended == true ? resources.depthRead : resources.depthWrite)
        var uniforms = DrawUniforms(viewProjection: projection, model: rig.world[source.node],
                                    color: material?.color ?? SIMD4(repeating: 1),
                                    parameters: SIMD4(material?.alphaCutoff ?? 0.5, Float(primitive.influences.count), Float(source.vertices.count), source.skin == nil ? 0 : 1),
                                    alphaMode: alphaMode.rawValue)
        encoder.setVertexBuffer(primitive.vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<DrawUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DrawUniforms>.stride, index: 1)
        encoder.setVertexBuffer(joints, offset: source.skin.map { jointOffsets[$0] } ?? 0, index: 2)
        encoder.setVertexBuffer(primitive.morphs, offset: 0, index: 3)
        if !primitive.influences.isEmpty {
            primitive.influences.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 4) }
        }
        encoder.setFragmentTexture(material?.image.map { textures[$0] } ?? resources.fallbackTexture, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: source.indices.count, indexType: .uint32, indexBuffer: primitive.indices, indexBufferOffset: 0)
    }

    private func drawMouth(with encoder: MTLRenderCommandEncoder, projection: Matrix4) {
        guard let mouth, let mouthIndex, let texture = mouth.textures[mouthIndex] else { return }
        let transform = rig.world[mouth.head] * mouth.local
        let faceNormal = transform.direction(Vector3(0, 0, 1))
        let directionToCamera = camera.eye - transform.position
        guard simd_dot(faceNormal, directionToCamera) > 0 else { return }
        encoder.setDepthStencilState(resources.depthRead)
        var uniforms = DrawUniforms(viewProjection: projection, model: transform, color: SIMD4(repeating: 1), parameters: .zero,
                                    alphaMode: MaterialAlphaMode.blend.rawValue)
        encoder.setVertexBuffer(mouth.vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<DrawUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DrawUniforms>.stride, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mouth.vertexCount)
    }

    static func buffer<T>(_ device: MTLDevice, _ values: [T]) -> MTLBuffer {
        values.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)! }
    }

    private func restWorldTransform(for node: Int) -> Matrix4 {
        var chain: [Int] = []
        var current: Int? = node
        while let index = current {
            chain.append(index)
            current = rig.parents[index]
        }
        return chain.reversed().reduce(matrix_identity_float4x4) { $0 * rig.rest[$1].matrix }
    }
}
