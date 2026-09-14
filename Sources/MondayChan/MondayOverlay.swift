import AppKit
import AVFAudio
import MondayCore
import MondayMetal
import MetalKit

@MainActor
final class MondayOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class MondayOverlayView: MTKView {
    override var isOpaque: Bool { false }
    var dismiss: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func rightMouseDown(with event: NSEvent) { dismiss?() }
}

@MainActor
final class MondayOverlay: NSObject, MTKViewDelegate {
    let window: MondayOverlayWindow
    let view: MondayOverlayView
    let renderer: CharacterRenderer
    private(set) var playbackTime: Double = 0
    let playback: MondayPlayback
    var isPlayingAudio: Bool { !isStopped && playback.isPlaying }
    var isExiting: Bool { playback.exitStartedAt != nil }
    private let participant = UUID()
    private let ownsPlayback: Bool
    private var isStopped = false
    private var isStarted = false

    private let performance: MondayPerformance
    private let audioStartTime: Double
    private let onFinished: () -> Void
    private let onError: (Error) -> Void
    private var didFinish = false

    init(performance: MondayPerformance, library: AssetLibrary, display: MondayDisplay, volume: Float, playback: MondayPlayback? = nil,
         onDismiss: (() -> Void)? = nil, onError: @escaping (Error) -> Void = { _ in },
         onFinished: @escaping () -> Void) throws {
        self.performance = performance
        ownsPlayback = playback == nil
        self.playback = try playback ?? MondayPlayback(performance: performance, volume: volume)
        audioStartTime = performance.audioStartTime
        playbackTime = performance.audioStartTime
        self.onFinished = onFinished
        self.onError = onError
        renderer = try CharacterRenderer(model: performance.model)
        try renderer.loadMouths(library: library, character: performance.character, conformToFace: true)
        try renderer.attachBoard(textureData: MondaySignArtwork.textureData(), attachment: MondaySignArtwork.attachment)
        var camera = RenderCamera(bounds: performance.bounds)
        camera.fit(aspect: Float(display.frame.width / max(display.frame.height, 1)))
        camera.presentationOffset.y = MondayEntrance.offset(at: 0)
        renderer.camera = camera

        window = MondayOverlayWindow(contentRect: display.frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        view = MondayOverlayView(frame: NSRect(origin: .zero, size: display.frame.size), device: renderer.device)
        super.init()
        configureWindow(display: display)
        configureView(display: display)
        renderer.rig.pose = performance.motion.pose(at: Float(audioStartTime))
        renderer.mouthIndex = performance.mouth(at: audioStartTime)
        renderer.faceWeights = MondayChoreography.faceWeights(at: audioStartTime)
        renderer.coverageUpdated = { [weak self] in self?.renderingCompleted() }
        view.dismiss = onDismiss ?? { [weak self] in self?.finish() }
    }

    func start() throws {
        guard !isStarted, !isStopped else { return }
        try playback.prepare()
        isStarted = true
        view.isPaused = false
        window.orderFrontRegardless()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        if ownsPlayback { playback.stop() }
        renderer.coverageUpdated = nil
        view.delegate = nil
        view.isPaused = true
        window.orderOut(nil)
        window.close()
    }

    func setVolume(_ volume: Float) { playback.setVolume(volume) }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard !isStopped else { return }
        if let error = playback.error { finish(error: error); return }
        let aspect = Float(view.drawableSize.width / max(view.drawableSize.height, 1))
        if isExiting {
            let elapsed = min(CACurrentMediaTime() - (playback.exitStartedAt ?? CACurrentMediaTime()), MondayStage.exitDuration)
            renderer.camera = MondayStage.exitCamera(bounds: performance.bounds, exitBounds: performance.exitBounds,
                                                      aspect: aspect, time: elapsed)
            renderer.rig.pose = MondayStage.exitPose(performance: performance, time: elapsed)
            renderer.mouthIndex = 0
            renderer.faceWeights = [:]
            if elapsed >= MondayStage.exitDuration {
                renderer.draw(in: view) { [weak self] in self?.finish() }
            } else {
                renderer.draw(in: view)
            }
            updateHitTesting()
            return
        }
        let time = playback.time
        let entranceElapsed = playback.entranceStartedAt.map { CACurrentMediaTime() - $0 } ?? 0
        if playback.isPlaying {
            renderer.camera = MondayStage.camera(bounds: performance.bounds, aspect: aspect, time: time)
        } else {
            renderer.camera.presentationOffset.y = MondayEntrance.offset(at: min(entranceElapsed, Double(MondayEntrance.duration)))
        }
        performance.motion.sample(at: Float(time), into: &renderer.rig.pose)
        playbackTime = time
        renderer.mouthIndex = performance.mouth(at: time)
        renderer.faceWeights = MondayChoreography.faceWeights(at: time)
        if !playback.isPlaying && entranceElapsed >= Double(MondayEntrance.duration) {
            renderer.draw(in: view) { [weak self] in self?.entranceRendered() }
        } else {
            renderer.draw(in: view)
        }
        updateHitTesting()
    }

    private func configureWindow(display: MondayDisplay) {
        window.setFrame(display.frame, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = true
    }

    private func configureView(display: MondayDisplay) {
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = CharacterRenderer.sampleCount
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.framebufferOnly = false
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.autoResizeDrawable = true
        view.layer?.isOpaque = false
        view.autoresizingMask = [.width, .height]
        view.preferredFramesPerSecond = max(60, display.refreshRate)
        view.delegate = self
        window.contentView = view
    }

    private func renderingCompleted() {
        updateHitTesting()
        playback.firstFrameRendered(by: participant)
    }

    private func entranceRendered() {
        guard !isStopped else { return }
        playback.entranceRendered(by: participant)
    }

    private func updateHitTesting() {
        let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let ignores = !(renderer.coverage?.contains(point: point, in: view.bounds.size) ?? false)
        if window.ignoresMouseEvents != ignores { window.ignoresMouseEvents = ignores }
    }

    private func finish(error: Error? = nil) {
        guard !isStopped, !didFinish else { return }
        didFinish = true
        stop()
        if let error { onError(error) }
        onFinished()
    }
}
