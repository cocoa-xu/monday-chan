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
final class MondayOverlay: NSObject, MTKViewDelegate, AVAudioPlayerDelegate {
    let window: MondayOverlayWindow
    let view: MondayOverlayView
    let renderer: CharacterRenderer
    private(set) var playbackTime: Double = 0
    var isPlayingAudio: Bool { state == .playing && audioPlayer?.isPlaying == true }
    var isExiting: Bool {
        if case .exiting = state { return true }
        return state == .waitingForExitFrame
    }

    private enum State: Equatable {
        case idle
        case waitingForFirstFrame
        case entrance(startedAt: CFTimeInterval)
        case waitingForAudio
        case playing
        case exiting(startedAt: CFTimeInterval)
        case waitingForExitFrame
        case stopped
    }

    private let performance: MondayPerformance
    private let audioStartTime: Double
    private let onFinished: () -> Void
    private let onError: (Error) -> Void
    private var audioPlayer: AVAudioPlayer?
    private var state = State.idle
    private var didFinish = false

    init(performance: MondayPerformance, library: AssetLibrary, display: MondayDisplay, volume: Float,
         onError: @escaping (Error) -> Void = { _ in },
         onFinished: @escaping () -> Void) throws {
        self.performance = performance
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

        let player = try AVAudioPlayer(contentsOf: performance.audioURL)
        player.volume = min(max(volume, 0), 1)
        player.currentTime = audioStartTime
        audioPlayer = player
        window = MondayOverlayWindow(contentRect: display.frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        view = MondayOverlayView(frame: NSRect(origin: .zero, size: display.frame.size), device: renderer.device)
        super.init()
        player.delegate = self
        configureWindow(display: display)
        configureView(display: display)
        renderer.rig.pose = performance.motion.pose(at: Float(audioStartTime))
        renderer.mouthIndex = performance.mouth(at: audioStartTime)
        renderer.faceWeights = MondayChoreography.faceWeights(at: audioStartTime)
        renderer.coverageUpdated = { [weak self] in self?.renderingCompleted() }
        view.dismiss = { [weak self] in self?.finish() }
    }

    func start() throws {
        guard state == .idle else { return }
        guard audioPlayer?.prepareToPlay() == true else { throw AssetError.invalid("Monday audio playback") }
        state = .waitingForFirstFrame
        view.isPaused = false
        window.orderFrontRegardless()
    }

    func stop() {
        guard state != .stopped else { return }
        state = .stopped
        audioPlayer?.stop()
        audioPlayer?.delegate = nil
        audioPlayer = nil
        renderer.coverageUpdated = nil
        view.delegate = nil
        view.isPaused = true
        window.orderOut(nil)
        window.close()
    }

    func setVolume(_ volume: Float) {
        audioPlayer?.volume = min(max(volume, 0), 1)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard state != .stopped else { return }
        let aspect = Float(view.drawableSize.width / max(view.drawableSize.height, 1))
        if isExiting {
            let elapsed: Double
            if case .exiting(let startedAt) = state {
                elapsed = min(CACurrentMediaTime() - startedAt, MondayStage.exitDuration)
            } else {
                elapsed = MondayStage.exitDuration
            }
            renderer.camera = MondayStage.exitCamera(bounds: performance.bounds, exitBounds: performance.exitBounds,
                                                      aspect: aspect, time: elapsed)
            renderer.rig.pose = MondayStage.exitPose(performance: performance, time: elapsed)
            renderer.mouthIndex = 0
            renderer.faceWeights = [:]
            if elapsed >= MondayStage.exitDuration {
                state = .waitingForExitFrame
                renderer.draw(in: view) { [weak self] in self?.finishExit() }
            } else {
                renderer.draw(in: view)
            }
            updateHitTesting()
            return
        }
        let time: Double
        if case .entrance(let startedAt) = state {
            let duration = Double(MondayEntrance.duration)
            let elapsed = min(CACurrentMediaTime() - startedAt, duration)
            renderer.camera.presentationOffset.y = MondayEntrance.offset(at: elapsed)
            if elapsed >= duration { state = .waitingForAudio }
            time = audioStartTime
        } else {
            time = state == .playing ? audioPlayer?.currentTime ?? audioStartTime : audioStartTime
            if state == .playing {
                renderer.camera = MondayStage.camera(bounds: performance.bounds, aspect: aspect, time: time)
            }
        }
        renderer.rig.pose = performance.motion.pose(at: Float(time))
        playbackTime = time
        renderer.mouthIndex = performance.mouth(at: time)
        renderer.faceWeights = MondayChoreography.faceWeights(at: time)
        if state == .waitingForAudio {
            renderer.draw(in: view) { [weak self] in self?.startAudioAfterEntrance() }
        } else {
            renderer.draw(in: view)
        }
        updateHitTesting()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.state == .playing else { return }
            if flag {
                self.audioPlayer?.stop()
                self.audioPlayer?.delegate = nil
                self.audioPlayer = nil
                self.state = .exiting(startedAt: CACurrentMediaTime())
            } else {
                self.finish(error: AssetError.invalid("Monday audio playback"))
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor [weak self] in self?.finish(error: error ?? AssetError.invalid("Monday audio decoding")) }
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
        switch state {
        case .waitingForFirstFrame:
            state = .entrance(startedAt: CACurrentMediaTime())
        default:
            break
        }
    }

    private func startAudioAfterEntrance() {
        guard state == .waitingForAudio else { return }
        guard audioPlayer?.play() == true else {
            finish(error: AssetError.invalid("Monday audio playback"))
            return
        }
        state = .playing
    }

    private func finishExit() {
        guard state == .waitingForExitFrame else { return }
        finish()
    }

    private func updateHitTesting() {
        let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let ignores = !(renderer.coverage?.contains(point: point, in: view.bounds.size) ?? false)
        if window.ignoresMouseEvents != ignores { window.ignoresMouseEvents = ignores }
    }

    private func finish(error: Error? = nil) {
        guard state != .stopped, !didFinish else { return }
        didFinish = true
        stop()
        if let error { onError(error) }
        onFinished()
    }
}
