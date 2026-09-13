import Foundation
import simd

public final class MondayChoreography {
    private let rig: CharacterRig
    private let hips: Int
    private let spine: Int
    private let head: Int
    private let arms: [(side: Float, shoulder: Int, elbow: Int, hand: Int, tip: Int)]
    private let legs: [(side: Float, thigh: Int, knee: Int, foot: Int)]

    public init(model: CharacterModel) throws {
        let rig = try CharacterRig(model: model)
        func node(_ name: String) throws -> Int {
            guard let index = rig.node(name) else { throw AssetError.missing(name) }
            return index
        }
        self.rig = rig
        hips = try node("jnt_C_hips00_00")
        spine = try node("jnt_C_spine00_01")
        head = try node("jnt_C_head00_00")
        arms = try [("L", Float(1)), ("R", Float(-1))].map { name, side in
            (side, try node("jnt_\(name)_upperArm00_00"), try node("jnt_\(name)_foreArm00_00"),
             try node("jnt_\(name)_hand00_00"), try node("ign_\(name)_hand00_01_end"))
        }
        legs = try [("L", Float(1)), ("R", Float(-1))].map { name, side in
            (side, try node("jnt_\(name)_thigh00_00"), try node("jnt_\(name)_leg00_00"),
             try node("jnt_\(name)_foot00_00"))
        }
    }

    public func bake(over idle: BakedMotion, duration: Float) -> BakedMotion {
        let frameCount = max(2, Int(ceil(duration * 60)) + 1)
        let frames = (0..<frameCount).map { frame in
            let time = Float(frame) / Float(frameCount - 1) * duration
            return pose(over: idle.pose(at: time), time: time)
        }
        return BakedMotion(id: "kanade-monday", duration: duration, loop: false, frames: frames)
    }

    public static func faceWeights(at time: Double) -> [String: Float] {
        let smile = pulse(Float(time), from: 0.5, to: 2.3) * 0.9
            + pulse(Float(time), from: 6.5, to: 7.7) * 0.9
            + pulse(Float(time), from: 9.5, to: 10.78) * 0.9
        if smile > 0 { return ["b_eye.eye_006": smile] }
        let phase = Float(time).truncatingRemainder(dividingBy: 3.3)
        let blink = max(0, 1 - abs(phase - 0.12) / 0.09)
        return blink > 0 ? ["b_eye.eye_005": blink] : [:]
    }

    private func pose(over base: [Transform], time: Float) -> [Transform] {
        rig.pose = base
        rig.updateWorld()
        let hop = MondayHopTimeline.sample(at: time)
        let footWorld = legs.map { rig.world[$0.foot] }
        translateHips(by: Vector3(hop.horizontal, hop.lift - hop.crouch, 0))
        for (index, leg) in legs.enumerated() {
            var target = footWorld[index].position
            target.x += hop.horizontal
            if hop.phase == .airborne {
                target.y += leg.side > 0 ? hop.leftFootLift : hop.rightFootLift
            }
            let root = rig.world[leg.thigh].position
            let knee = TwoBoneIK.elbow(root: root, target: target, pole: Vector3(leg.side * 0.08, 0, 1),
                                      upperLength: simd_distance(root, rig.world[leg.knee].position),
                                      lowerLength: simd_distance(rig.world[leg.knee].position, rig.world[leg.foot].position))
            aim(leg.thigh, child: leg.knee, at: knee)
            aim(leg.knee, child: leg.foot, at: target)
            setWorldRotation(leg.foot, to: footWorld[index])
        }
        let entrance = Self.smooth(time / 0.5)
        let beat = sin(time * .pi * 2 / 1.15)
        let pointing = Self.pulse(time, from: 2.7, to: 5.7) + Self.pulse(time, from: 7.7, to: 9.4)
        let tilt = (0.13 * beat + 0.10 * sin(time * 1.2)) * entrance
        rotate(spine, by: Quaternion(angle: -tilt * 0.4, axis: Vector3(0, 0, 1)))
        rotate(spine, by: Quaternion(angle: 0.05 * beat * entrance, axis: Vector3(0, 1, 0)))
        rotate(head, by: Quaternion(angle: tilt, axis: Vector3(0, 0, 1)))
        rotate(head, by: Quaternion(angle: (-0.045 + 0.055 * cos(time * 5.5)) * entrance, axis: Vector3(1, 0, 0)))
        let center = rig.world[hips].position
        for arm in arms {
            let gesture = arm.side < 0 ? pointing : 0
            let onHip = center + Vector3(arm.side * 0.24, 0.14, 0.05)
            let raised = center + Vector3(arm.side * (0.23 + beat * 0.025), 0.34 + beat * 0.015, 0.18)
            let airborne = min(hop.lift / 0.12, 1)
            let leading = arm.side == hop.side ? Float(1) : 0.65
            let open = center + Vector3(arm.side * (0.33 + 0.04 * leading), 0.28 + 0.11 * leading, 0.1)
            let flourish = simd_mix(onHip, open, Vector3(repeating: airborne))
            let desired = simd_mix(flourish, raised, Vector3(repeating: gesture))
            let target = simd_mix(rig.world[arm.hand].position, desired, Vector3(repeating: entrance))
            let root = rig.world[arm.shoulder].position
            let elbow = TwoBoneIK.elbow(root: root, target: target, pole: Vector3(arm.side * 0.5, -0.1, -0.3),
                                       upperLength: simd_distance(root, rig.world[arm.elbow].position),
                                       lowerLength: simd_distance(rig.world[arm.elbow].position, rig.world[arm.hand].position))
            aim(arm.shoulder, child: arm.elbow, at: elbow)
            aim(arm.elbow, child: arm.hand, at: target)
            let restingDirection = Vector3(arm.side * -0.6, -0.8, 0.05)
            let pointingDirection = Vector3(beat * 0.22, 1, 0.5)
            let direction = simd_mix(restingDirection, pointingDirection, Vector3(repeating: gesture))
            let originalDirection = simd_normalize(rig.world[arm.tip].position - rig.world[arm.hand].position)
            let blended = simd_mix(originalDirection, direction, Vector3(repeating: entrance))
            aim(arm.hand, child: arm.tip, at: rig.world[arm.hand].position + blended)
            if arm.side < 0 { curlPointingFingers(amount: gesture * entrance) }
        }
        return rig.pose
    }

    private func translateHips(by offset: Vector3) {
        let parent = rig.parents[hips].map { rig.world[$0] } ?? matrix_identity_float4x4
        rig.pose[hips].translation += simd_inverse(parent).direction(offset)
        rig.updateWorld()
    }

    private func setWorldRotation(_ node: Int, to world: Matrix4) {
        let parent = rig.parents[node].map { rig.world[$0] } ?? matrix_identity_float4x4
        rig.pose[node].rotation = Transform(matrix: simd_inverse(parent) * world).rotation
        rig.updateWorld()
    }

    private func curlPointingFingers(amount: Float) {
        for finger in ["Middle", "Ring", "Pinky"] {
            for segment in 0...2 {
                guard let node = rig.node(String(format: "jnt_R_finger%@00_%02d", finger, segment)) else { continue }
                rig.pose[node].rotation *= Quaternion(angle: -0.9 * amount, axis: Vector3(0, 0, 1))
            }
        }
        rig.updateWorld()
    }

    private func rotate(_ node: Int, by rotation: Quaternion) {
        let parent = rig.parents[node].map { rig.world[$0] } ?? matrix_identity_float4x4
        rig.pose[node].rotation = Transform(matrix: simd_inverse(parent) * Matrix4(rotation) * rig.world[node]).rotation
        rig.updateWorld()
    }

    private func aim(_ node: Int, child: Int, at target: Vector3) {
        let parent = rig.parents[node].map { rig.world[$0] } ?? matrix_identity_float4x4
        let inverse = simd_inverse(parent)
        let from = inverse.direction(rig.world[child].position - rig.world[node].position)
        let to = inverse.direction(target - rig.world[node].position)
        guard simd_length(from) > 0.00001, simd_length(to) > 0.00001 else { return }
        rig.pose[node].rotation = simd_normalize(Quaternion(from: simd_normalize(from), to: simd_normalize(to)) * rig.pose[node].rotation)
        rig.updateWorld()
    }

    private static func smooth(_ value: Float) -> Float {
        let value = min(max(value, 0), 1)
        return value * value * (3 - 2 * value)
    }

    private static func pulse(_ time: Float, from start: Float, to end: Float) -> Float {
        smooth((time - start) / 0.4) * smooth((end - time) / 0.4)
    }
}
