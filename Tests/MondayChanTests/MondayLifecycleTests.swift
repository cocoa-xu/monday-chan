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
    overlay.playback.audioPlayerDidFinishPlaying(player, successfully: true)
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
    defaults.set(MondayTrigger.sunday2350.rawValue, forKey: "monday.trigger")
    defaults.set(0.0, forKey: "monday.volume")
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 23, minute: 50)))
    let loads = MondayLoadCounter()
    let load: @Sendable (AssetLibrary) async throws -> MondayPerformance = { _ in
        await loads.increment()
        return performance
    }

    var controller: MondayController? = MondayController(library: library, defaults: defaults, loadPerformance: load,
                                                          displays: { [display] }, now: { monday },
                                                          timeZone: { zone }, focus: { false })
    try await waitUntil(timeout: 2) { controller?.state == .playing }
    #expect(defaults.stringArray(forKey: "monday.completedDays") == ["2026-09-13"])
    controller?.close()
    controller = nil

    let restored = MondayController(library: library, defaults: defaults, loadPerformance: load,
                                    displays: { [display] }, now: { monday },
                                    timeZone: { zone }, focus: { false })
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

@Test(.enabled(if: FileManager.default.fileExists(atPath: "data/events/monday/kanade.m4a"))) @MainActor
func multipleDisplaysShareOneAudioClockAndWaitForEveryEntranceFrame() async throws {
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    let playback = try MondayPlayback(performance: performance, volume: 0, participantCount: 2)
    defer { playback.stop() }
    let first = UUID(), second = UUID()
    try playback.prepare()
    playback.firstFrameRendered(by: first)
    playback.firstFrameRendered(by: first)
    #expect(playback.entranceStartedAt == nil)
    playback.firstFrameRendered(by: second)
    #expect(playback.entranceStartedAt != nil)
    playback.entranceRendered(by: first)
    #expect(!playback.isPlaying)
    playback.entranceRendered(by: second)
    #expect(playback.isPlaying)
    let start = playback.time
    try await Task.sleep(for: .milliseconds(80))
    playback.entranceRendered(by: first)
    #expect(playback.time > start)
    var overlays: [MondayOverlay] = []
    defer { overlays.forEach { $0.stop() } }
    for (index, frame) in [CGRect(x: 0, y: 0, width: 640, height: 360), CGRect(x: 640, y: 0, width: 360, height: 640)].enumerated() {
        let overlay = try MondayOverlay(performance: performance, library: library,
                                        display: .init(id: "\(index)", name: "Display", frame: frame, refreshRate: 120),
                                        volume: 0, playback: playback) {}
        overlays.append(overlay)
        #expect(overlay.playback === playback)
        #expect(overlay.view.sampleCount == 4)
        #expect(overlay.window.frame == frame)
        #expect(overlay.view.preferredFramesPerSecond == 120)
    }
    overlays[0].stop()
    #expect(playback.isPlaying)
}

@Test(.enabled(if: FileManager.default.fileExists(atPath: "data/events/monday/kanade.m4a"))) @MainActor
func automaticLoadIsDiscardedIfFocusStartsOrSundayEndsBeforePresentation() async throws {
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    for focusChanges in [true, false] {
        let suite = "MondayBoundaryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["one"], forKey: "monday.displayIDs")
        defaults.set(MondayTrigger.sunday2345.rawValue, forKey: "monday.trigger")
        let sunday = ISO8601DateFormatter().date(from: "2026-09-13T23:59:59Z")!
        var current = sunday
        var focused = false
        let controller = MondayController(library: library, defaults: defaults,
                                          loadPerformance: { _ in try await Task.sleep(for: .milliseconds(50)); return performance },
                                          displays: { [.init(id: "one", name: "One", frame: CGRect(x: 0, y: 0, width: 400, height: 300), refreshRate: 60)] },
                                          now: { current }, timeZone: { TimeZone(secondsFromGMT: 0)! }, focus: { focused })
        defer { controller.close() }
        #expect(controller.state == .loading)
        if focusChanges { focused = true }
        else { current = sunday.addingTimeInterval(1) }
        try await waitUntil(timeout: 2) { controller.state == .idle }
        #expect(defaults.stringArray(forKey: "monday.completedDays") == nil)
    }
}
