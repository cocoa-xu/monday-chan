import AVFAudio
import MondayCore

struct MondayPerformance: Sendable {
    static let characterID = "06002"
    let model: CharacterModel
    let character: CharacterDescriptor
    let motion: BakedMotion
    let exitMotion: BakedMotion
    let bounds: Bounds3
    let exitBounds: Bounds3
    let envelope: SpeechEnvelope
    let audioURL: URL

    var audioStartTime: Double { max(0, (envelope.firstSoundTime ?? 0) - 0.04) }

    func mouth(at time: Double) -> Int {
        MondayMouth.speaking(level: envelope.level(at: time)).rawValue
    }
}

enum MondayMouth: Int, CaseIterable {
    case rest = 0
    case smallRounded = 7
    case rounded = 17
    case smallSmile = 35

    static func speaking(level: Float) -> Self {
        if level < 0.01 { return .rest }
        if level < 0.035 { return .smallRounded }
        return level < 0.08 ? .rounded : .smallSmile
    }
}

actor MondayPerformanceLoader {
    func load(library: AssetLibrary) throws -> MondayPerformance {
        try autoreleasepool {
            try Task.checkCancellation()
            let currentLibrary = try AssetLibrary(root: library.root)
            let audioURL = try currentLibrary.url(for: "events/monday/kanade.m4a")
            let audio = try AVAudioFile(forReading: audioURL)
            guard audio.length > 0, audio.length <= AVAudioFramePosition(audio.processingFormat.sampleRate * 60) else {
                throw AssetError.invalid("Monday audio duration")
            }
            let character = try currentLibrary.character(MondayPerformance.characterID)
            let model = try CharacterModel(url: currentLibrary.url(for: character.model))
            let clip = try MotionClip(url: currentLibrary.url(for: "motions/idle01_typ000_lp_bdy00.json"))
            let retargeter = try HumanoidRetargeter(model: model, reference: clip)
            let idle = retargeter.bake(clip)
            let run = try MotionClip(url: currentLibrary.url(for: "motions/run00_typ000_lp_bdy00.json"))
            let exitMotion = retargeter.bake(run)
            let motion = try MondayChoreography(model: model).bake(over: idle, duration: Float(Double(audio.length) / audio.processingFormat.sampleRate))
            let rig = try CharacterRig(model: model)
            var bounds = Bounds3()
            for frame in 0...motion.frameCount {
                try Task.checkCancellation()
                rig.pose = motion.pose(at: Float(frame) / Float(motion.frameCount) * motion.duration)
                rig.updateWorld()
                let poseBounds = rig.bounds()
                bounds.include(poseBounds.minimum)
                bounds.include(poseBounds.maximum)
            }
            var exitBounds = bounds
            for frame in 0...exitMotion.frameCount {
                try Task.checkCancellation()
                rig.pose = exitMotion.pose(at: Float(frame) / Float(exitMotion.frameCount) * exitMotion.duration)
                rig.updateWorld()
                let poseBounds = rig.bounds()
                exitBounds.include(poseBounds.minimum)
                exitBounds.include(poseBounds.maximum)
            }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)) else {
                throw AssetError.invalid("Monday audio duration")
            }
            try audio.read(into: buffer)
            guard let channels = buffer.floatChannelData else { throw AssetError.invalid("Monday audio format") }
            let samples = (0..<Int(buffer.frameLength)).map { frame in
                (0..<Int(buffer.format.channelCount)).reduce(Float.zero) { max($0, abs(channels[$1][frame])) }
            }
            return MondayPerformance(model: model, character: character, motion: motion, exitMotion: exitMotion,
                                     bounds: bounds, exitBounds: exitBounds,
                                     envelope: SpeechEnvelope(samples: samples, sampleRate: buffer.format.sampleRate), audioURL: audioURL)
        }
    }
}
