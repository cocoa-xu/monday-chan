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

