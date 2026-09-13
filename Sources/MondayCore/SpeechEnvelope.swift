import Foundation

public struct SpeechEnvelope: Sendable {
    public let levels: [Float]
    public let interval: Double

    public var firstSoundTime: Double? {
        levels.firstIndex { $0 >= 0.002 }.map { Double($0) * interval }
    }

    public init(samples: [Float], sampleRate: Double, interval: Double = 0.02) {
        self.interval = max(interval, 0.001)
        let count = max(1, Int(max(sampleRate, 1) * self.interval))
        levels = stride(from: 0, to: samples.count, by: count).map { start in
            let end = min(start + count, samples.count)
            let energy = samples[start..<end].reduce(Float.zero) { $0 + $1 * $1 }
            return sqrt(energy / Float(end - start))
        }
    }

    public func level(at time: Double) -> Float {
        guard time.isFinite, time >= 0, time < Double(levels.count) * interval else { return 0 }
        let index = Int(time / interval)
        var level = levels[index]
        let releaseDuration = 0.06
        let releaseFrames = Int(ceil(releaseDuration / interval))
        for previous in max(0, index - releaseFrames)..<index {
            let decay = max(0, 1 - Float(index - previous) * Float(interval / releaseDuration))
            level = max(level, levels[previous] * decay)
        }
        return level
    }
}
