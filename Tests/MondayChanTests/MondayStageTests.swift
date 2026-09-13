import AppKit
import MondayCore
import MondayMetal
import simd
import Testing
@testable import MondayChan

@Test func mondayStageCloseupsReturnToTheCanonicalCameraAndRemainSmooth() {
    var bounds = Bounds3()
    bounds.include(Vector3(-0.5, 0, -0.3))
    bounds.include(Vector3(0.5, 2, 0.3))
    let aspect: Float = 9 / 16
    let base = MondayStage.camera(bounds: bounds, aspect: aspect, time: 0)
    for time in [2.4, 4.6, 7.4, 9.4] {
        let camera = MondayStage.camera(bounds: bounds, aspect: aspect, time: time)
        #expect(simd_distance(camera.bounds.minimum, base.bounds.minimum) < 0.00001)
        #expect(simd_distance(camera.bounds.maximum, base.bounds.maximum) < 0.00001)
        #expect(abs(camera.zoom - base.zoom) < 0.00001)
    }
    let closeup = MondayStage.camera(bounds: bounds, aspect: aspect, time: 3.2)
    #expect(closeup.zoom > base.zoom * 1.9)
    #expect(simd_distance(closeup.bounds.size, base.bounds.size) < 0.00001)
    let projection = closeup.matrix(aspect: aspect)
    let center = closeup.bounds.center
    let forward = simd_normalize(center - closeup.eye)
    let right = simd_normalize(simd_cross(forward, Vector3(0, 1, 0)))
    let up = simd_normalize(simd_cross(right, forward))
    let projectedCenter = projection.point(center)
    let horizontalPixels = simd_distance(projection.point(center + right), projectedCenter) * aspect
    let verticalPixels = simd_distance(projection.point(center + up), projectedCenter)
    #expect(abs(horizontalPixels - verticalPixels) < 0.0001)

    var previous = base
    for frame in 1...Int(MondayHopTimeline.duration * 60) {
        let current = MondayStage.camera(bounds: bounds, aspect: aspect, time: Double(frame) / 60)
        #expect(abs(current.zoom - previous.zoom) < 0.08)
        #expect(simd_distance(current.bounds.center, previous.bounds.center) < 0.025)
        previous = current
    }
}

@Test(.enabled(if: mondayStageAssetsAreAvailable()))
func mondayStageUsesTheRunClipAndProjectsTheFinalPoseBeyondTheRightEdge() async throws {
    let performance = try await MondayPerformanceLoader().load(library: AssetLibrary(root: URL(fileURLWithPath: "data")))
    #expect(MondayStage.exitDuration == 0.5)
    #expect(stagePosesMatch(MondayStage.exitPose(performance: performance, time: 0),
                            performance.motion.pose(at: performance.motion.duration)))
    for time in [0.25, 0.35, 0.45] {
        #expect(stagePosesMatch(MondayStage.exitPose(performance: performance, time: time),
                                performance.exitMotion.pose(at: Float(time))))
    }
    #expect(!stagePosesMatch(MondayStage.exitPose(performance: performance, time: 0.3),
                            MondayStage.exitPose(performance: performance, time: 0.3 + 1 / 60)))
    for aspect: Float in [9 / 16, 16 / 9] {
        let turning = MondayStage.exitCamera(bounds: performance.bounds, exitBounds: performance.exitBounds,
                                             aspect: aspect, time: 0.15)
        #expect(abs(turning.yaw + .pi / 2) < 0.001)
        #expect(turning.presentationOffset.x > 0)
        let midway = MondayStage.exitCamera(bounds: performance.bounds, exitBounds: performance.exitBounds,
                                            aspect: aspect, time: MondayStage.exitDuration / 2)
        let camera = MondayStage.exitCamera(bounds: performance.bounds, exitBounds: performance.exitBounds,
                                            aspect: aspect, time: MondayStage.exitDuration)
        #expect(midway.presentationOffset.x > camera.presentationOffset.x * 0.4)
        #expect(camera.yaw < -Float.pi * 0.49)
        let projection = camera.matrix(aspect: aspect)
        var minimumX = Float.infinity
        for x in [performance.exitBounds.minimum.x, performance.exitBounds.maximum.x] {
            for y in [performance.exitBounds.minimum.y, performance.exitBounds.maximum.y] {
                for z in [performance.exitBounds.minimum.z, performance.exitBounds.maximum.z] {
                    minimumX = min(minimumX, projection.point(Vector3(x, y, z)).x)
                }
            }
        }
        #expect(minimumX > 1)
    }
}

@Test(.enabled(if: mondayStageAssetsAreAvailable())) @MainActor
func mondaySignLeavesTheAnimatedMouthVisibleDuringHopsAndCloseups() async throws {
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    let renderer = try stageRenderer(performance: performance, library: library)
    for time in [0.0, 1.18, 3.3, 8.1] {
        renderer.camera = MondayStage.camera(bounds: performance.bounds, aspect: 9 / 16, time: time)
        renderer.rig.pose = performance.motion.pose(at: Float(time))
        renderer.mouthIndex = 0
        let closed = try renderer.snapshot(width: 270, height: 480)
        for mouth in MondayMouth.allCases where mouth != .rest {
            renderer.mouthIndex = mouth.rawValue
            let open = try renderer.snapshot(width: 270, height: 480)
            #expect(zip(closed, open).filter { $0 != $1 }.count > 40)
        }
    }
}

@Test(.enabled(if: mondayStageAssetsAreAvailable())) @MainActor
func mondayStageFinalExitRasterIsEmptyWithTheSignAttached() async throws {
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    let renderer = try stageRenderer(performance: performance, library: library)
    for (width, height) in [(270, 480), (640, 360)] {
        renderer.camera = MondayStage.exitCamera(bounds: performance.bounds, exitBounds: performance.exitBounds,
                                                 aspect: Float(width) / Float(height), time: MondayStage.exitDuration)
        renderer.rig.pose = MondayStage.exitPose(performance: performance, time: MondayStage.exitDuration)
        renderer.mouthIndex = 0
        renderer.faceWeights = [:]
        let pixels = try renderer.snapshot(width: width, height: height)
        #expect(pixels.enumerated().allSatisfy { $0.offset % 4 != 3 || $0.element == 0 })
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MONDAY_CHAN_EXPORT_MONDAY"] == "1" && mondayStageAssetsAreAvailable())) @MainActor
func exportIntegratedMondayStageContactSheet() async throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let library = try AssetLibrary(root: root.appendingPathComponent("data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    let renderer = try stageRenderer(performance: performance, library: library)
    let output = root.appendingPathComponent(".build/monday")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    var frames: [Data] = []
    let width = 360
    let height = 640
    for time in [0.0, 1.18, 3.3, 4.8, 8.1, 10.7] {
        renderer.camera = MondayStage.camera(bounds: performance.bounds, aspect: Float(width) / Float(height), time: time)
        renderer.rig.pose = performance.motion.pose(at: Float(time))
        renderer.mouthIndex = performance.mouth(at: time)
        renderer.faceWeights = MondayChoreography.faceWeights(at: time)
        frames.append(try renderer.snapshot(width: width, height: height))
    }
    for fraction in [0.0, 0.15, 0.4, 0.7, 1.0] {
        let time = MondayStage.exitDuration * fraction
        renderer.camera = MondayStage.exitCamera(bounds: performance.bounds, exitBounds: performance.exitBounds,
                                                 aspect: Float(width) / Float(height), time: time)
        renderer.rig.pose = MondayStage.exitPose(performance: performance, time: time)
        renderer.mouthIndex = 0
        renderer.faceWeights = [:]
        frames.append(try renderer.snapshot(width: width, height: height))
    }
    try saveStageContactSheet(frames, frameWidth: width, frameHeight: height,
                              to: output.appendingPathComponent("stage-contact-sheet.png"))
}

@MainActor private func stageRenderer(performance: MondayPerformance, library: AssetLibrary) throws -> CharacterRenderer {
    let renderer = try CharacterRenderer(model: performance.model)
    try renderer.loadMouths(library: library, character: performance.character, conformToFace: true)
    try renderer.attachBoard(textureData: MondaySignArtwork.textureData(), attachment: MondaySignArtwork.attachment)
    return renderer
}

private func mondayStageAssetsAreAvailable() -> Bool {
    let root = URL(fileURLWithPath: "data", isDirectory: true)
    return ["characters.json", "models/06002.glb", "motions/idle01_typ000_lp_bdy00.json",
            "motions/run00_typ000_lp_bdy00.json", "events/monday/kanade.m4a"]
        .allSatisfy { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
}

private func stagePosesMatch(_ lhs: [Transform], _ rhs: [Transform], tolerance: Float = 0.00001) -> Bool {
    zip(lhs, rhs).allSatisfy {
        simd_distance($0.translation, $1.translation) <= tolerance
            && simd_distance($0.scale, $1.scale) <= tolerance
            && abs(simd_dot($0.rotation.vector, $1.rotation.vector)) >= 1 - tolerance
    }
}

@MainActor private func saveStageContactSheet(_ frames: [Data], frameWidth: Int, frameHeight: Int, to url: URL) throws {
    let columns = 4
    let rows = Int(ceil(Double(frames.count) / Double(columns)))
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: frameWidth * columns,
                                              pixelsHigh: frameHeight * rows, bitsPerSample: 8, samplesPerPixel: 4,
                                              hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                              bitmapFormat: [.alphaNonpremultiplied], bytesPerRow: frameWidth * columns * 4,
                                              bitsPerPixel: 32))
    bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    for (frameIndex, frame) in frames.enumerated() {
        let column = frameIndex % columns
        let row = frameIndex / columns
        frame.withUnsafeBytes { raw in
            let source = raw.bindMemory(to: UInt8.self)
            for y in 0..<frameHeight {
                for x in 0..<frameWidth {
                    let sourceIndex = (y * frameWidth + x) * 4
                    let targetIndex = ((row * frameHeight + y) * frameWidth * columns + column * frameWidth + x) * 4
                    bitmap.bitmapData![targetIndex] = source[sourceIndex + 2]
                    bitmap.bitmapData![targetIndex + 1] = source[sourceIndex + 1]
                    bitmap.bitmapData![targetIndex + 2] = source[sourceIndex]
                    bitmap.bitmapData![targetIndex + 3] = source[sourceIndex + 3]
                }
            }
        }
    }
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url, options: .atomic)
}
