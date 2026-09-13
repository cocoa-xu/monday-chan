import simd

public final class HumanoidRetargeter {
    private struct Limb {
        let root: Int
        let middle: Int
        let end: Int
        let channel: Int
        let pole: Vector3
        let correction: Vector3
    }

    private let rig: CharacterRig
    private let reference: [Float]
    private let referenceWorld: [Matrix4]
    private let hips: Int
    private let scale: Float
    private let limbs: [Limb]

    public init(model: CharacterModel, reference: MotionClip) throws {
        let rig = try CharacterRig(model: model)
        guard let hips = rig.node("jnt_C_hips00_00"), let foot = rig.node("jnt_L_foot00_00") else {
            throw AssetError.missing("Humanoid hips or foot")
        }
        self.rig = rig
        self.hips = hips
        self.reference = reference.frames[0]
        referenceWorld = rig.world
        let frame = reference.frames[0]
        let scale = (rig.world[hips].position.y - rig.world[foot].position.y) / max(frame[1], 0.1)
        self.scale = scale
        var limbs: [Limb] = []
        for (side, channel, leg) in [("L", 7, true), ("R", 14, true), ("L", 21, false), ("R", 28, false)] {
            let parts = leg ? ["thigh", "leg", "foot"] : ["upperArm", "foreArm", "hand"]
            let nodes = parts.compactMap { rig.node("jnt_\(side)_\($0)00_00") }
            guard nodes.count == 3 else { throw AssetError.missing("\(side) limb chain") }
            let sourceGoal = Self.mirror(Self.quaternion(frame, 3).act(Self.vector(frame, channel))) * scale + rig.world[hips].position
            let correction = leg ? rig.world[nodes[2]].position - sourceGoal : Vector3.zero
            limbs.append(Limb(root: nodes[0], middle: nodes[1], end: nodes[2], channel: channel,
                              pole: leg ? Vector3(0, 0, 1) : Vector3(side == "L" ? 0.3 : -0.3, -0.25, -1), correction: correction))
        }
        self.limbs = limbs
    }

    public func bake(_ clip: MotionClip) -> BakedMotion {
        let frames = clip.frames.map(retarget)
        rig.reset()
        return BakedMotion(id: clip.id, duration: clip.duration, loop: clip.loop, frames: frames)
    }

    private func retarget(_ values: [Float]) -> [Transform] {
        rig.reset()
        rig.pose[hips].translation.y += (values[1] - reference[1]) * scale
        rig.updateWorld()
        let bodyRotation = Self.quaternion(values, 3)
        let bodyDelta = Self.reflected(bodyRotation * Self.quaternion(reference, 3).inverse)
        rotateWorld(hips, by: bodyDelta)
        for (name, offset, strength) in [("jnt_C_spine00_00", 35, Float(0.5)), ("jnt_C_spine00_01", 38, 0.4),
                                        ("jnt_C_neck00_00", 44, 0.3), ("jnt_C_head00_00", 47, 0.4)] {
            guard let node = rig.node(name) else { continue }
            let delta = Self.vector(values, offset) - Self.vector(reference, offset)
            let q = Quaternion(angle: delta.x * strength, axis: Vector3(1, 0, 0))
                * Quaternion(angle: -delta.y * strength, axis: Vector3(0, 0, 1))
                * Quaternion(angle: -delta.z * strength, axis: Vector3(0, 1, 0))
            rotateWorld(node, by: q)
        }
        for limb in limbs {
            let target = rig.world[hips].position + Self.mirror(bodyRotation.act(Self.vector(values, limb.channel))) * scale + limb.correction
            let root = rig.world[limb.root].position
            let middle = rig.world[limb.middle].position
            let end = rig.world[limb.end].position
            let elbow = TwoBoneIK.elbow(root: root, target: target, pole: limb.pole,
                                       upperLength: simd_distance(root, middle), lowerLength: simd_distance(middle, end))
            aim(limb.root, child: limb.middle, at: elbow)
            aim(limb.middle, child: limb.end, at: target)
            let rotation = Self.reflected(Self.quaternion(values, limb.channel + 3) * Self.quaternion(reference, limb.channel + 3).inverse)
            let reference = limb.channel < 21 ? referenceWorld[limb.end] : rig.world[limb.end]
            var desired = Matrix4(rotation) * reference
            desired.columns.3 = rig.world[limb.end].columns.3
            setWorldRotation(limb.end, matrix: desired)
        }
        return rig.pose
    }

    private func aim(_ node: Int, child: Int, at target: Vector3) {
        guard let parent = rig.parents[node] else { return }
        let inverse = simd_inverse(rig.world[parent])
        let from = inverse.direction(rig.world[child].position - rig.world[node].position)
        let to = inverse.direction(target - rig.world[node].position)
        guard simd_length(from) > 0.000001, simd_length(to) > 0.000001 else { return }
        rig.pose[node].rotation = simd_normalize(Quaternion(from: simd_normalize(from), to: simd_normalize(to)) * rig.pose[node].rotation)
        rig.updateWorld()
    }

    private func rotateWorld(_ node: Int, by rotation: Quaternion) {
        setWorldRotation(node, matrix: Matrix4(rotation) * rig.world[node])
    }

    private func setWorldRotation(_ node: Int, matrix: Matrix4) {
        let parent = rig.parents[node].map { rig.world[$0] } ?? matrix_identity_float4x4
        rig.pose[node].rotation = Transform(matrix: simd_inverse(parent) * matrix).rotation
        rig.updateWorld()
    }

    private static func vector(_ values: [Float], _ index: Int) -> Vector3 { Vector3(values[index], values[index + 1], values[index + 2]) }
    private static func quaternion(_ values: [Float], _ index: Int) -> Quaternion {
        let q = SIMD4(values[index], values[index + 1], values[index + 2], values[index + 3])
        return simd_length(q) > 0.0001 ? simd_normalize(Quaternion(vector: q)) : Quaternion(angle: 0, axis: Vector3(0, 1, 0))
    }
    private static func mirror(_ value: Vector3) -> Vector3 { Vector3(-value.x, value.y, value.z) }
    private static func reflected(_ q: Quaternion) -> Quaternion { Quaternion(vector: SIMD4(q.imag.x, -q.imag.y, -q.imag.z, q.real)) }
}
