import AVFAudio
import MondayCore
import QuartzCore

@MainActor
final class MondayPlayback: NSObject, AVAudioPlayerDelegate {
    let audioStartTime: Double
    private(set) var entranceStartedAt: CFTimeInterval?
    private(set) var exitStartedAt: CFTimeInterval?
    private(set) var error: Error?
    private(set) var isPlaying = false
    var time: Double { isPlaying ? player?.currentTime ?? audioStartTime : audioStartTime }
    private var player: AVAudioPlayer?
    private let participantCount: Int
    private var firstFrames: Set<UUID> = []
    private var entranceFrames: Set<UUID> = []
    private var prepared = false
    private var stopped = false

    init(performance: MondayPerformance, volume: Float, participantCount: Int = 1) throws {
        precondition(participantCount > 0)
        self.participantCount = participantCount
        audioStartTime = performance.audioStartTime
        player = try AVAudioPlayer(contentsOf: performance.audioURL)
        super.init()
        player?.delegate = self
        player?.currentTime = audioStartTime
        setVolume(volume)
    }

    func prepare() throws {
        guard !prepared else { return }
        guard player?.prepareToPlay() == true else { throw AssetError.invalid("Monday audio playback") }
        prepared = true
    }

    func firstFrameRendered(by participant: UUID) {
        guard !stopped, entranceStartedAt == nil else { return }
        firstFrames.insert(participant)
        if firstFrames.count == participantCount { entranceStartedAt = CACurrentMediaTime() }
    }

    func entranceRendered(by participant: UUID) {
        guard !stopped, !isPlaying, error == nil, exitStartedAt == nil else { return }
        entranceFrames.insert(participant)
        guard entranceFrames.count == participantCount else { return }
        guard player?.play() == true else {
            error = AssetError.invalid("Monday audio playback")
            return
        }
        isPlaying = true
    }

    func setVolume(_ volume: Float) { player?.volume = min(max(volume, 0), 1) }

    func stop() {
        stopped = true
        isPlaying = false
        player?.stop()
        player?.delegate = nil
        player = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped, self.isPlaying else { return }
            self.isPlaying = false
            if flag { self.exitStartedAt = CACurrentMediaTime() }
            else { self.error = AssetError.invalid("Monday audio playback") }
            self.player?.delegate = nil
            self.player = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor [weak self] in self?.error = error ?? AssetError.invalid("Monday audio decoding") }
    }
}
