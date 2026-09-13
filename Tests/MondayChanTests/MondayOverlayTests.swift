import AppKit
import AVFAudio
import MondayCore
import MondayMetal
import simd
import Testing
@testable import MondayChan

@Test(.enabled(if: FileManager.default.fileExists(atPath: "data/events/monday/kanade.m4a"))) @MainActor
func mondayOverlayConfiguresAFullResolutionTransparentSurfaceAndRendersAFrame() async throws {
    _ = NSApplication.shared
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    let display = MondayDisplay(id: "portrait", name: "Portrait",
                                frame: CGRect(x: -1080, y: -120, width: 1080, height: 1920), refreshRate: 120)
    let overlay = try MondayOverlay(performance: performance, library: library, display: display, volume: 0.5) {}
    defer { overlay.stop() }

    #expect(overlay.window.frame == display.frame)
    #expect(overlay.window.styleMask.contains(.nonactivatingPanel))
    #expect(overlay.window.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(overlay.window.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(overlay.window.ignoresMouseEvents)
    #expect(!overlay.window.isOpaque)
    #expect(overlay.view.sampleCount == 4)
    #expect(overlay.view.preferredFramesPerSecond == 120)
    #expect(overlay.view.autoResizeDrawable)
    #expect(try overlay.renderer.snapshot(width: 180, height: 320).count == 180 * 320 * 4)
}

@Test(.enabled(if: FileManager.default.fileExists(atPath: "data/events/monday/kanade.m4a"))) @MainActor
func mondayChoreographyStaysInsidePortraitAndLandscapeFrames() async throws {
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    let renderer = try CharacterRenderer(model: performance.model)
    try renderer.loadMouths(library: library, character: performance.character, conformToFace: true)
    let times: [Float] = [0, 0.94, 1.18, 1.42, 2.33, 5.78, 8.17, 9.41, performance.motion.duration]

    for (width, height) in [(270, 480), (640, 360)] {
        renderer.camera = RenderCamera(bounds: performance.bounds)
        renderer.camera.fit(aspect: Float(width) / Float(height))
        for time in times {
            renderer.rig.pose = performance.motion.pose(at: time)
            renderer.faceWeights = MondayChoreography.faceWeights(at: Double(time))
            renderer.mouthIndex = performance.mouth(at: Double(time))
            let pixels = try renderer.snapshot(width: width, height: height)
            let occupied = try alphaBounds(pixels, width: width, height: height)
            #expect(occupied.minX > 0)
            #expect(occupied.minY > 0)
            #expect(occupied.maxX < width - 1)
            #expect(occupied.maxY < height - 1)
            #expect(pixels[3] == 0)
            #expect(pixels[pixels.count - 1] == 0)
        }
    }
}

@Test(.enabled(if: FileManager.default.fileExists(atPath: "data/events/monday/kanade.m4a"))) @MainActor
func mondayMotionClampsToItsFinalPoseAtTheAudioBoundary() async throws {
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    let audio = try AVAudioPlayer(contentsOf: performance.audioURL)
    #expect(!performance.motion.loop)
    #expect(abs(Double(performance.motion.duration) - audio.duration) < 0.05)
    let final = performance.motion.pose(at: performance.motion.duration)
    let afterAudio = performance.motion.pose(at: Float(audio.duration + 1))
    #expect(posesMatch(final, afterAudio))
    #expect(!posesMatch(performance.motion.pose(at: 1), final))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MONDAY_CHAN_EXPORT_MONDAY"] == "1"
               && FileManager.default.fileExists(atPath: "data/events/monday/kanade.m4a"))) @MainActor
func exportMondayChoreographyAndExpressionFrames() async throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let library = try AssetLibrary(root: root.appendingPathComponent("data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    let renderer = try CharacterRenderer(model: performance.model)
    try renderer.loadMouths(library: library, character: performance.character, conformToFace: true)
    renderer.camera = RenderCamera(bounds: performance.bounds)
    renderer.camera.fit(aspect: 9 / 16)
    let output = root.appendingPathComponent(".build/monday")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    let contactTimes = [0.94, 1.18, 1.42, 2.33, 5.78, 8.17, 9.41]
    var contactFrames: [URL] = []
    for time in contactTimes {
        renderer.rig.pose = performance.motion.pose(at: Float(time))
        renderer.faceWeights = MondayChoreography.faceWeights(at: time)
        renderer.mouthIndex = performance.mouth(at: time)
        let url = output.appendingPathComponent(String(format: "hop-%04.2f.png", time))
        try saveMondayPNG(try renderer.snapshot(width: 720, height: 1280), width: 720, height: 1280,
                          to: url)
        contactFrames.append(url)
    }
    try saveMondayContactSheet(contactFrames, to: output.appendingPathComponent("hop-contact-sheet.png"))
    renderer.rig.pose = performance.motion.pose(at: 5)
    for (name, weights) in [("neutral", [String: Float]()), ("blink", ["b_eye.eye_005": 1]),
                            ("happy", ["b_eye.eye_006": 1])] {
        renderer.faceWeights = weights
        renderer.mouthIndex = 0
        try saveMondayPNG(try renderer.snapshot(width: 720, height: 1280), width: 720, height: 1280,
                          to: output.appendingPathComponent("eyes-\(name).png"))
    }
    renderer.faceWeights = [:]
    renderer.camera = MondayStage.camera(bounds: performance.bounds, aspect: 9 / 16, time: 3.2)
    var mouthFrames: [URL] = []
    for mouth in MondayMouth.allCases {
        renderer.mouthIndex = mouth.rawValue
        let url = output.appendingPathComponent("speech-mouth-\(mouth.rawValue).png")
        try saveMondayPNG(try renderer.snapshot(width: 720, height: 1280), width: 720, height: 1280,
                          to: url)
        mouthFrames.append(url)
    }
    try saveMondayContactSheet(mouthFrames, to: output.appendingPathComponent("speech-mouth-contact.png"))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MONDAY_CHAN_TEST_MONDAY_OVERLAY"] == "1"
               && FileManager.default.fileExists(atPath: "data/events/monday/kanade.m4a"))) @MainActor
func mondayOverlayCanStartAndStopIdempotentlyWithoutReportingNaturalCompletion() async throws {
    _ = NSApplication.shared
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    let display = try #require(MondayDisplay.connected.first)
    var completions = 0
    let overlay = try MondayOverlay(performance: performance, library: library, display: display, volume: 0) {
        completions += 1
    }

    try overlay.start()
    let deadline = ContinuousClock.now + .seconds(1)
    while overlay.renderer.camera.presentationOffset.y == MondayEntrance.offset(at: 0), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(16))
    }
    #expect(overlay.renderer.camera.presentationOffset.y > MondayEntrance.offset(at: 0))
    #expect(overlay.renderer.camera.presentationOffset.y < 0)
    overlay.stop()
    overlay.stop()

    #expect(!overlay.window.isVisible)
    #expect(overlay.view.isPaused)
    #expect(completions == 0)
}

private func alphaBounds(_ pixels: Data, width: Int, height: Int) throws -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
    var result = (minX: width, minY: height, maxX: -1, maxY: -1)
    pixels.withUnsafeBytes { raw in
        let bytes = raw.bindMemory(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 8 {
                result.minX = min(result.minX, x)
                result.minY = min(result.minY, y)
                result.maxX = max(result.maxX, x)
                result.maxY = max(result.maxY, y)
            }
        }
    }
    try #require(result.maxX >= result.minX && result.maxY >= result.minY)
    return result
}

private func posesMatch(_ lhs: [Transform], _ rhs: [Transform], tolerance: Float = 0.00001) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).allSatisfy { left, right in
        let translationMatches = simd_length(left.translation - right.translation) <= tolerance
        let scaleMatches = simd_length(left.scale - right.scale) <= tolerance
        let rotationMatches = abs(simd_dot(left.rotation.vector, right.rotation.vector)) >= 1 - tolerance
        return translationMatches && scaleMatches && rotationMatches
    }
}

private func saveMondayPNG(_ pixels: Data, width: Int, height: Int, to url: URL) throws {
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                              colorSpaceName: .deviceRGB, bitmapFormat: [.alphaNonpremultiplied],
                                              bytesPerRow: width * 4, bitsPerPixel: 32))
    pixels.withUnsafeBytes { source in
        let bytes = source.bindMemory(to: UInt8.self)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            bitmap.bitmapData![index] = bytes[index + 2]
            bitmap.bitmapData![index + 1] = bytes[index + 1]
            bitmap.bitmapData![index + 2] = bytes[index]
            bitmap.bitmapData![index + 3] = bytes[index + 3]
        }
    }
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url, options: .atomic)
}

@MainActor private func saveMondayContactSheet(_ frames: [URL], to url: URL) throws {
    let cellWidth = 270
    let cellHeight = 480
    let columns = 4
    let rows = Int(ceil(Double(frames.count) / Double(columns)))
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cellWidth * columns,
                                              pixelsHigh: cellHeight * rows, bitsPerSample: 8, samplesPerPixel: 4,
                                              hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                              bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSColor.black.setFill()
    NSRect(x: 0, y: 0, width: cellWidth * columns, height: cellHeight * rows).fill()
    for (index, frame) in frames.enumerated() {
        let source = try #require(NSImage(contentsOf: frame))
        let column = index % columns
        let row = rows - 1 - index / columns
        source.draw(in: NSRect(x: column * cellWidth, y: row * cellHeight, width: cellWidth, height: cellHeight))
    }
    context.flushGraphics()
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url, options: .atomic)
}
