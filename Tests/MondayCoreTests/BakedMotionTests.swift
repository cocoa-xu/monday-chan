import Testing
import Foundation
import simd
@testable import MondayCore

@Test func compactMotionPreservesEverySampleBitAndConstantTrackInterpolation() {
    let constant = Transform(translation: Vector3(0.1, -0.7, 0.3),
                             rotation: Quaternion(vector: SIMD4(0.11, -0.3, 0.21, 0.93)), scale: Vector3(0.7, 1.1, 0.9))
    let frames = (0..<7).map { frame in
        [constant,
         Transform(translation: Vector3(Float(frame) / 3, 0, 0), rotation: Quaternion(angle: Float(frame) * 0.4, axis: Vector3(0, 1, 0))),
         Transform(translation: Vector3(frame % 2 == 0 ? Float.zero : -Float.zero, 0, 0))]
    }
    for loop in [false, true] {
        let motion = BakedMotion(id: "test", duration: 2, loop: loop, frames: frames)
        #expect(motion.storedTransformCount == 15)
        #expect(motion.frameCount == frames.count)
        #expect(motion.frames.map { $0.map(bits) } == frames.map { $0.map(bits) })
        let times: [Float] = [-1, 0, 0.000001, 1.0 / 3, 0.5, 1, 1.999999, 2, 2.7, 8.1]
        for time in times {
            let sample = MotionTime(time: time, duration: 2, frameCount: frames.count, loop: loop)
            let reference = zip(frames[sample.first], frames[sample.second]).map { Transform.blend($0, $1, fraction: sample.fraction) }
            #expect(motion.pose(at: time).map(bits) == reference.map(bits))
        }
    }
}

private func bits(_ transform: Transform) -> [UInt32] {
    (0..<3).map { transform.translation[$0].bitPattern }
        + (0..<4).map { transform.rotation.vector[$0].bitPattern }
        + (0..<3).map { transform.scale[$0].bitPattern }
}


@Test func inPlaceSamplingReusesStorageAndPreservesRetainedPoses() {
    let frames = (0..<5).map { frame in
        [Transform(translation: Vector3(Float(frame), 0, 0)),
         Transform(rotation: Quaternion(angle: Float(frame) * 0.3, axis: Vector3(0, 1, 0)))]
    }
    let motion = BakedMotion(id: "sample", duration: 2, loop: true, frames: frames)
    var pose: [Transform] = []
    motion.sample(at: 0, into: &pose)
    let address = pose.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
    for time: Float in [-0.5, 0.25, 0.6, 1.3, 1.999, 2.0, 2.3] {
        motion.sample(at: time, into: &pose)
        #expect(pose.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) } == address)
        let sample = MotionTime(time: time, duration: 2, frameCount: frames.count, loop: true)
        let expected = zip(frames[sample.first], frames[sample.second]).map { Transform.blend($0, $1, fraction: sample.fraction) }
        #expect(pose.map(bits) == expected.map(bits))
    }
    let retained = pose
    let retainedBits = retained.map(bits)
    motion.sample(at: 1.25, into: &pose)
    #expect(retained.map(bits) == retainedBits)
    #expect(pose.map(bits) != retainedBits)
    pose = [Transform()]
    motion.sample(at: 0.3, into: &pose)
    #expect(pose.count == 2)
    #expect(pose.map(bits) == motion.pose(at: 0.3).map(bits))
}
