import AppKit
import AVFAudio
import MondayCore
import simd
import Testing
@testable import MondayChan

private let mondayRuntimeEnabled = ProcessInfo.processInfo.environment["MONDAY_CHAN_TEST_MONDAY_OVERLAY"] == "1"
    && FileManager.default.fileExists(atPath: "data/events/monday/kanade.m4a")

@Test(.enabled(if: mondayRuntimeEnabled), .timeLimit(.minutes(1))) @MainActor
func mondayOverlayCompletesEntranceAudioAndRunExitExactlyOnce() async throws {
    _ = NSApplication.shared
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    let display = try #require(MondayDisplay.connected.last)
    var completions = 0
    let overlay = try MondayOverlay(performance: performance, library: library, display: display, volume: 0) {
        completions += 1
    }

    try overlay.start()
    try await waitUntil(timeout: 1) { overlay.renderer.completedFrames > 0 }
    let entranceStarted = ContinuousClock.now
    #expect(!overlay.isPlayingAudio)
    #expect(overlay.playbackTime == performance.audioStartTime)
    try await waitUntil(timeout: 0.95) { overlay.isPlayingAudio }
    #expect(entranceStarted.duration(to: .now) >= .seconds(MondayEntrance.duration - 0.08))
    #expect(overlay.renderer.camera.presentationOffset.y == 0)
    try await waitUntil(timeout: 0.25) { overlay.playbackTime > performance.audioStartTime + 0.05 }

    let sampledTime = overlay.playbackTime
    let renderedPose = overlay.renderer.rig.pose
    let expectedPose = performance.motion.pose(at: Float(sampledTime))
    #expect(posesAreClose(renderedPose, expectedPose, tolerance: 0.002))

    try await waitUntil(timeout: performance.audioDuration + 1) { overlay.isExiting }
    let exitStarted = ContinuousClock.now
    #expect(completions == 0)
    #expect(!overlay.isPlayingAudio)
    #expect(overlay.window.isVisible)
    try await waitUntil(timeout: 1) { overlay.renderer.camera.presentationOffset.x > 0.1 }
    #expect(overlay.window.frame == display.frame)
    try await waitUntil(timeout: MondayStage.exitDuration + 1) { completions == 1 }
    #expect(exitStarted.duration(to: .now) < .seconds(0.7))
    #expect(overlay.renderer.coverage?.alpha.allSatisfy { $0 == 0 } == true)
    #expect(!overlay.isPlayingAudio)
    #expect(!overlay.window.isVisible)
    #expect(overlay.view.isPaused)
    #expect(overlay.view.delegate == nil)
    overlay.stop()
    #expect(completions == 1)
}

@Test(.enabled(if: mondayRuntimeEnabled), .timeLimit(.minutes(1))) @MainActor
func mondayOverlayCanStopDuringRunExitWithoutCompleting() async throws {
    _ = NSApplication.shared
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    let display = try #require(MondayDisplay.connected.last)
    var completions = 0
    let overlay = try MondayOverlay(performance: performance, library: library, display: display, volume: 0) {
        completions += 1
    }
    try overlay.start()
    try await waitUntil(timeout: 4) { overlay.isPlayingAudio }
    let player = try AVAudioPlayer(contentsOf: performance.audioURL)
    overlay.audioPlayerDidFinishPlaying(player, successfully: true)
    try await waitUntil(timeout: 1) { overlay.isExiting }
    overlay.stop()
    overlay.stop()
    try await Task.sleep(for: .milliseconds(100))
    #expect(completions == 0)
    #expect(!overlay.window.isVisible)
    #expect(overlay.view.isPaused)
    #expect(overlay.view.delegate == nil)
}

@Test(.enabled(if: mondayRuntimeEnabled), .timeLimit(.minutes(1))) @MainActor
func mondayOverlayRightClickCompletionCleansUpExactlyOnce() async throws {
    _ = NSApplication.shared
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    let display = try #require(MondayDisplay.connected.last)
    var completions = 0
    let overlay = try MondayOverlay(performance: performance, library: library, display: display, volume: 0) {
        completions += 1
    }

    try overlay.start()
    try await waitUntil(timeout: 1) { overlay.renderer.completedFrames > 0 }
    overlay.view.dismiss?()
    overlay.view.dismiss?()

    #expect(completions == 1)
    #expect(!overlay.isPlayingAudio)
    #expect(!overlay.window.isVisible)
    #expect(overlay.view.isPaused)
    #expect(overlay.view.delegate == nil)
}

@Test(.enabled(if: mondayRuntimeEnabled), .timeLimit(.minutes(1))) @MainActor
func automaticMondayPlaybackIsRecordedBeforeRestartAndDoesNotLaunchTwice() async throws {
    _ = NSApplication.shared
    let display = try #require(MondayDisplay.connected.last)
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    let suite = "MondayChanTests.MondayLifecycle.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(display.id, forKey: "monday.displayID")
    defaults.set(MondayTrigger.morning.rawValue, forKey: "monday.trigger")
    defaults.set(0.0, forKey: "monday.volume")
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 10)))
    let loads = MondayLoadCounter()
    let load: @Sendable (AssetLibrary) async throws -> MondayPerformance = { _ in
        await loads.increment()
        return performance
    }

    var controller: MondayController? = MondayController(library: library, defaults: defaults, loadPerformance: load,
                                                          displays: { [display] }, now: { monday },
                                                          timeZone: { zone })
    try await waitUntil(timeout: 2) { controller?.state == .playing }
    #expect(defaults.stringArray(forKey: "monday.completedDays") == ["2026-09-14"])
    controller?.close()
    controller = nil

    let restored = MondayController(library: library, defaults: defaults, loadPerformance: load,
                                    displays: { [display] }, now: { monday },
                                    timeZone: { zone })
    defer { restored.close() }
    try await Task.sleep(for: .milliseconds(100))
    #expect(restored.state == .idle)
    let loadCount = await loads.value
    #expect(loadCount == 1)
}

@MainActor
private func waitUntil(timeout: Double, condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(timeout)
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(16))
    }
    try #require(condition())
}

private func posesAreClose(_ lhs: [Transform], _ rhs: [Transform], tolerance: Float) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).allSatisfy { left, right in
        let translation = simd_length(left.translation - right.translation)
        let scale = simd_length(left.scale - right.scale)
        let rotation = abs(simd_dot(left.rotation.vector, right.rotation.vector))
        return translation <= tolerance && scale <= tolerance && rotation >= 1 - tolerance
    }
}

private extension MondayPerformance {
    var audioDuration: Double { Double(motion.duration) }
}

private actor MondayLoadCounter {
    private var count = 0
    var value: Int { count }
    func increment() { count += 1 }
}
