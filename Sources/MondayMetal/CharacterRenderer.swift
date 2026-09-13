import Foundation
import MondayCore
import MetalKit
import simd

@MainActor
public final class CharacterRenderer {
    public nonisolated static let sampleCount = CharacterRenderScene.sampleCount
    public var device: MTLDevice { scene.device }
    public var queue: MTLCommandQueue { scene.queue }
    public var rig: CharacterRig { scene.rig }
    public var camera: RenderCamera { get { scene.camera } set { scene.camera = newValue } }
    public var faceWeights: [String: Float] { get { scene.faceWeights } set { scene.faceWeights = newValue } }
    public var mouthIndex: Int? { get { scene.mouthIndex } set { scene.mouthIndex = newValue } }
    public var boardAttachment: BoardAttachment? { get { scene.boardAttachment } set { scene.boardAttachment = newValue } }
    public private(set) var coverage: CoverageMask?
    public private(set) var completedFrames = 0
    public private(set) var requestedFrames = 0
    public private(set) var busyFrames = 0
    public private(set) var totalGPUTime: Double = 0
    public var coverageUpdated: (() -> Void)?
    public var gpuMilliseconds: Double = 0

    private let scene: CharacterRenderScene
    private let jointBuffers: [MTLBuffer]
    private let coverageBuffers: CoverageReadbackPool
    private var nextFrameSlot = 0
    private let availableFrames = DispatchSemaphore(value: 3)
    private var targets: RenderTargets?

    public init(model: CharacterModel, device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        let scene = try CharacterRenderScene(model: model, device: device)
        self.scene = scene
        coverageBuffers = CoverageReadbackPool(device: scene.device)
        jointBuffers = (0..<3).map { _ in scene.makeJointBuffer() }
    }

    public func loadMouths(library: AssetLibrary, character: CharacterDescriptor, conformToFace: Bool = false) throws {
        try scene.loadMouths(library: library, character: character, conformToFace: conformToFace)
    }

    public func attachBoard(textureData: Data, attachment: BoardAttachment) throws {
        try scene.attachBoard(textureData: textureData, attachment: attachment)
    }

    public func draw(in view: MTKView, onCompleted: (@MainActor @Sendable () -> Void)? = nil) {
        requestedFrames += 1
        guard availableFrames.wait(timeout: .now()) == .success else {
            busyFrames += 1
            return
        }
        guard let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer() else {
            availableFrames.signal()
            return
        }
        if targets?.matches(drawable.texture) != true {
            targets = try? RenderTargets(device: device, width: drawable.texture.width, height: drawable.texture.height)
        }
        guard let targets else {
            availableFrames.signal()
            return
        }
        let slot = nextFrameSlot
        nextFrameSlot = (nextFrameSlot + 1) % 3
        scene.encode(command: command, pass: targets.pass(resolvingTo: drawable.texture), width: drawable.texture.width,
               height: drawable.texture.height, joints: jointBuffers[slot])
        let readback = encodeCoverage(command: command, texture: drawable.texture)
        let semaphore = availableFrames
        command.addCompletedHandler { [weak self] command in
            let elapsed = (command.gpuEndTime - command.gpuStartTime) * 1000
            let completed = command.status == .completed
            semaphore.signal()
            Task { @MainActor [weak self] in
                guard let self, completed else { return }
                self.coverage = readback?.mask
                self.completedFrames += 1
                self.gpuMilliseconds = elapsed
                self.totalGPUTime += elapsed
                self.coverageUpdated?()
                onCompleted?()
            }
        }
        command.present(drawable)
        command.commit()
    }

    public func snapshot(width: Int, height: Int, captureCoverage: Bool = false) throws -> Data {
        var readback: CoverageReadback?
        let data = try scene.snapshot(width: width, height: height) { command, texture in
            if captureCoverage { readback = self.encodeCoverage(command: command, texture: texture) }
        }
        if captureCoverage { coverage = readback?.mask }
        return data
    }

    func encodeCoverage(command: MTLCommandBuffer, texture: MTLTexture) -> CoverageReadback? {
        let readback = coverageBuffers.acquire(width: texture.width, height: texture.height)
        guard let encoder = command.makeComputeCommandEncoder() else { return nil }
        encoder.setComputePipelineState(scene.resources.coveragePipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBuffer(readback.buffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: texture.width, height: texture.height, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()
        return readback
    }

}
