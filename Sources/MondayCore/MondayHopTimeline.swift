import Foundation

public enum MondayHopPhase: Equatable, Sendable {
    case settled
    case anticipation
    case airborne
    case landing
}

public struct MondayHopSample: Sendable {
    public let horizontal: Float
    public let lift: Float
    public let crouch: Float
    public let phase: MondayHopPhase
    public let side: Float
    public let leftFootLift: Float
    public let rightFootLift: Float
}

public enum MondayHopTimeline {
    public static let duration: Float = 10.78

    private static let takeoffs: [Float] = [1, 2.15, 3.3, 4.45, 5.6, 6.75, 7.9, 9.05]
    private static let anticipation: Float = 0.12
    private static let flight: Float = 0.36
    private static let landing: Float = 0.16
    private static let distance: Float = 0.16

    public static func sample(at time: Float) -> MondayHopSample {
        let time = min(max(time, 0), duration)
        var position: Float = 0
        for (index, takeoff) in takeoffs.enumerated() {
            let side: Float = index.isMultiple(of: 2) ? 1 : -1
            let destination: Float = index == takeoffs.count - 1 ? 0 : side * distance
            if time < takeoff - anticipation {
                return sample(horizontal: position, phase: .settled, side: side)
            }
            if time < takeoff {
                let progress = smooth((time - (takeoff - anticipation)) / anticipation)
                return sample(horizontal: position, crouch: 0.065 * progress, phase: .anticipation, side: side)
            }
            if time < takeoff + flight {
                let progress = (time - takeoff) / flight
                let arc = sin(.pi * progress)
                let horizontal = position + (destination - position) * smooth(progress)
                let alternatingKick = sin(.pi * progress) * 0.025
                let crouchRelease = 0.065 * (1 - smooth(min(progress / 0.25, 1)))
                return sample(horizontal: horizontal, lift: arc * 0.12, crouch: crouchRelease, phase: .airborne, side: side,
                              leftFootLift: arc * 0.17 + (side < 0 ? alternatingKick : 0),
                              rightFootLift: arc * 0.17 + (side > 0 ? alternatingKick : 0))
            }
            position = destination
            if time < takeoff + flight + landing {
                let progress = (time - takeoff - flight) / landing
                return sample(horizontal: position, crouch: sin(.pi * progress) * 0.08, phase: .landing, side: side)
            }
        }
        return sample(horizontal: 0, phase: .settled, side: 0)
    }

    private static func sample(horizontal: Float, lift: Float = 0, crouch: Float = 0,
                               phase: MondayHopPhase, side: Float,
                               leftFootLift: Float = 0, rightFootLift: Float = 0) -> MondayHopSample {
        MondayHopSample(horizontal: horizontal, lift: lift, crouch: crouch, phase: phase, side: side,
                        leftFootLift: leftFootLift, rightFootLift: rightFootLift)
    }

    private static func smooth(_ value: Float) -> Float {
        let value = min(max(value, 0), 1)
        return value * value * (3 - 2 * value)
    }
}
