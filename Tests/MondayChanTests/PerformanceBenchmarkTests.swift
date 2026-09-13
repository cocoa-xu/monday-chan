import AppKit
import Darwin
import MondayCore
import MondayMetal
import Testing
@testable import MondayChan

@Test(.enabled(if: ProcessInfo.processInfo.environment["MONDAY_BENCHMARK_OUTPUT"] != nil)) @MainActor
func measureMondayPlaybackCosts() async throws {
    _ = NSApplication.shared
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let start = CACurrentMediaTime()
    let performance = try await MondayPerformanceLoader().load(library: library)
    let loadMilliseconds = (CACurrentMediaTime() - start) * 1000
    let display = try #require(MondayDisplay.connected.first)
    let prepareStart = CACurrentMediaTime()
    let overlay = try MondayOverlay(performance: performance, library: library, display: display, volume: 0) {}
    let prepareMilliseconds = (CACurrentMediaTime() - prepareStart) * 1000
    defer { overlay.stop() }
    try overlay.start()
    try await Task.sleep(for: .seconds(1))
    let cpuStart = processCPUSeconds()
    let frameStart = overlay.renderer.completedFrames
    let busyStart = overlay.renderer.busyFrames
    let gpuStart = overlay.renderer.totalGPUTime
    let playbackStart = CACurrentMediaTime()
    try await Task.sleep(for: .seconds(5))
    let elapsed = CACurrentMediaTime() - playbackStart
    let frames = overlay.renderer.completedFrames - frameStart
    let cpu = processCPUSeconds() - cpuStart
    let values: [String: Any] = [
        "load_ms": loadMilliseconds, "prepare_ms": prepareMilliseconds,
        "cpu_percent": cpu / elapsed * 100,
        "frames": frames, "frames_per_second": Double(frames) / elapsed,
        "busy_frames": overlay.renderer.busyFrames - busyStart,
        "gpu_ms_per_frame": (overlay.renderer.totalGPUTime - gpuStart) / Double(max(frames, 1)),
        "metal_bytes": overlay.renderer.device.currentAllocatedSize,
        "drawable_width": overlay.view.drawableSize.width, "drawable_height": overlay.view.drawableSize.height,
        "refresh_rate": overlay.view.preferredFramesPerSecond,
        "primitive_count": performance.model.primitives.count,
        "vertex_count": performance.model.primitives.reduce(0) { $0 + $1.vertices.count }
    ]
    let output = try #require(ProcessInfo.processInfo.environment["MONDAY_BENCHMARK_OUTPUT"])
    try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
        .write(to: URL(fileURLWithPath: output))
}

private func processCPUSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["MONDAY_PREPARATION_OUTPUT"] != nil)) @MainActor
func measureMondayPreparationCosts() async throws {
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    let start = CACurrentMediaTime()
    let renderer = try CharacterRenderer(model: performance.model)
    let rendererEnd = CACurrentMediaTime()
    try renderer.loadMouths(library: library, character: performance.character, conformToFace: true)
    let mouthsEnd = CACurrentMediaTime()
    let artwork = try MondaySignArtwork.textureData()
    let artworkEnd = CACurrentMediaTime()
    let cached = try MondaySignArtwork.textureData()
    let cachedEnd = CACurrentMediaTime()
    #expect(artwork == cached)
    try renderer.attachBoard(textureData: artwork, attachment: MondaySignArtwork.attachment)
    let boardEnd = CACurrentMediaTime()
    let values: [String: Double] = ["renderer_ms": (rendererEnd - start) * 1000, "mouths_ms": (mouthsEnd - rendererEnd) * 1000,
                                   "artwork_ms": (artworkEnd - mouthsEnd) * 1000, "board_ms": (boardEnd - cachedEnd) * 1000, "cached_artwork_ms": (cachedEnd - artworkEnd) * 1000]
    let output = try #require(ProcessInfo.processInfo.environment["MONDAY_PREPARATION_OUTPUT"])
    try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
}
