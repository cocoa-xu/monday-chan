import Foundation

public struct MotionClip: Decodable, Sendable {
    public let id: String
    public let duration: Float
    public let loop: Bool
    public let fps: Float
    public let frames: [[Float]]

    public init(url: URL) throws {
        self = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard duration > 0, duration.isFinite, fps > 0, fps.isFinite, frames.count >= 2,
              frames.allSatisfy({ $0.count == 130 && $0.allSatisfy(\.isFinite) }) else {
            throw AssetError.invalid("Humanoid motion channels")
        }
    }
}

public struct MotionTime: Equatable, Sendable {
    public let first: Int
    public let second: Int
    public let fraction: Float

    public init(time: Float, duration: Float, frameCount: Int, loop: Bool) {
        let duration = max(duration, 0.000001)
        let elapsed = max(0, time)
        let position = loop ? elapsed.truncatingRemainder(dividingBy: duration) : min(elapsed, duration)
        let frame = position / duration * Float(max(0, frameCount - 1))
        first = min(Int(frame), max(0, frameCount - 1))
        second = min(first + 1, max(0, frameCount - 1))
        fraction = frame - Float(first)
    }
}
