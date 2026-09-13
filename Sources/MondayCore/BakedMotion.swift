import simd

public struct BakedMotion: Sendable {
    private enum Track: Sendable {
        case constant(Transform)
        case samples([Transform])

        func value(at frame: Int) -> Transform {
            switch self {
            case .constant(let value): value
            case .samples(let values): values[frame]
            }
        }

        var storedCount: Int {
            switch self {
            case .constant: 1
            case .samples(let values): values.count
            }
        }
    }

    public let id: String
    public let duration: Float
    public let loop: Bool
    public let frameCount: Int
    private let tracks: [Track]

    public var frames: [[Transform]] { (0..<frameCount).map { frame in tracks.map { $0.value(at: frame) } } }
    var storedTransformCount: Int { tracks.reduce(0) { $0 + $1.storedCount } }

    init(id: String, duration: Float, loop: Bool, frames: [[Transform]]) {
        precondition(duration.isFinite && duration > 0 && !frames.isEmpty
                     && frames.allSatisfy { $0.count == frames[0].count }, "Motion frames must have matching node counts and a positive duration")
        self.id = id
        self.duration = duration
        self.loop = loop
        frameCount = frames.count
        tracks = (frames.first ?? []).indices.map { node in
            let first = frames[0][node]
            if frames.dropFirst().allSatisfy({ first.hasSameBits(as: $0[node]) }) { return .constant(first) }
            return .samples(frames.map { $0[node] })
        }
    }

    public func pose(at time: Float) -> [Transform] {
        let sample = MotionTime(time: time, duration: duration, frameCount: frameCount, loop: loop)
        return tracks.map { Transform.blend($0.value(at: sample.first), $0.value(at: sample.second), fraction: sample.fraction) }
    }
}

private extension Transform {
    func hasSameBits(as other: Transform) -> Bool {
        for axis in 0..<3 {
            if translation[axis].bitPattern != other.translation[axis].bitPattern || scale[axis].bitPattern != other.scale[axis].bitPattern { return false }
        }
        for axis in 0..<4 where rotation.vector[axis].bitPattern != other.rotation.vector[axis].bitPattern { return false }
        return true
    }
}
