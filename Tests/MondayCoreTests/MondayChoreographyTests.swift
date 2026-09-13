import Foundation
import MondayCore
import simd
import Testing

@Test func mondayHopTimelineAlternatesAirborneTravelAndSettlesAtCenter() {
    #expect(MondayHopTimeline.sample(at: 0).phase == .settled)
    #expect(MondayHopTimeline.sample(at: 0.94).phase == .anticipation)
    let firstApex = MondayHopTimeline.sample(at: 1.18)
    #expect(firstApex.phase == .airborne)
    #expect(firstApex.lift > 0.11)
    #expect(firstApex.leftFootLift > 0.16)
    #expect(firstApex.rightFootLift > 0.16)
    #expect(MondayHopTimeline.sample(at: 1.42).phase == .landing)

    let airborneSides = [1.27, 2.42, 3.57, 4.72, 5.87, 7.02, 8.17]
        .map { MondayHopTimeline.sample(at: Float($0)).horizontal }
    #expect(zip(airborneSides, airborneSides.dropFirst()).allSatisfy { $0 * $1 < 0 })
    #expect(airborneSides.allSatisfy { abs($0) > 0.07 })
    #expect(abs(MondayHopTimeline.sample(at: 9.41).horizontal) < 0.00001)
    let final = MondayHopTimeline.sample(at: MondayHopTimeline.duration)
    #expect(final.phase == .settled)
    #expect(abs(final.horizontal) < 0.00001)
    #expect(final.lift == 0)
    #expect(final.crouch == 0)
}

@Test func mondayHopTimelineIsContinuousAtProductionFrameRate() {
    var previous = MondayHopTimeline.sample(at: 0)
    for frame in 1...Int(MondayHopTimeline.duration * 60) {
        let current = MondayHopTimeline.sample(at: Float(frame) / 60)
        #expect(abs(current.horizontal - previous.horizontal) < 0.025)
        #expect(abs(current.lift - previous.lift) < 0.025)
        #expect(abs(current.crouch - previous.crouch) < 0.03)
        previous = current
    }
}

@Test(.enabled(if: localAssetsAvailable))
func mondayChoreographyUsesLegIKWithoutDistortingTheRig() throws {
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let character = try library.character("06002")
    let model = try CharacterModel(url: library.url(for: character.model))
    let clip = try MotionClip(url: library.url(for: "motions/idle01_typ000_lp_bdy00.json"))
    let idle = try HumanoidRetargeter(model: model, reference: clip).bake(clip)
    let motion = try MondayChoreography(model: model).bake(over: idle, duration: 10.78)
    #expect(!motion.loop)
    #expect(motion.duration == 10.78)
    let original = try CharacterRig(model: model)
    let performed = try CharacterRig(model: model)
    let hips = try #require(original.node("jnt_C_hips00_00"))
    let legs = try [("jnt_L_thigh00_00", "jnt_L_leg00_00", "jnt_L_foot00_00"),
                    ("jnt_R_thigh00_00", "jnt_R_leg00_00", "jnt_R_foot00_00")].map {
        (try #require(original.node($0.0)), try #require(original.node($0.1)), try #require(original.node($0.2)))
    }
    let referenceLengths = legs.map { leg in
        (simd_distance(original.world[leg.0].position, original.world[leg.1].position),
         simd_distance(original.world[leg.1].position, original.world[leg.2].position))
    }
    var changedHeadFrames = 0
    let head = try #require(original.node("jnt_C_head00_00"))
    var horizontalExtremes: ClosedRange<Float> = 0...0
    var previousFeet: [Vector3]?
    var kneeBendObserved = false
    for frame in 0..<motion.frameCount {
        let time = Float(frame) / Float(motion.frameCount - 1) * motion.duration
        let hop = MondayHopTimeline.sample(at: time)
        original.pose = idle.pose(at: time)
        performed.pose = motion.pose(at: time)
        original.updateWorld()
        performed.updateWorld()
        for (index, pair) in zip(original.pose, performed.pose).enumerated() {
            let (before, after) = pair
            if index != hips { #expect(simd_distance(before.translation, after.translation) < 0.00001) }
            #expect(simd_distance(before.scale, after.scale) < 0.00001)
            #expect(abs(simd_length(after.rotation.vector) - 1) < 0.0001)
            #expect(after.rotation.vector.x.isFinite && after.rotation.vector.y.isFinite
                    && after.rotation.vector.z.isFinite && after.rotation.vector.w.isFinite)
        }
        let performedFeet = legs.map { performed.world[$0.2].position }
        for (index, leg) in legs.enumerated() {
            #expect(abs(simd_distance(performed.world[leg.0].position, performed.world[leg.1].position) - referenceLengths[index].0) < 0.0001)
            #expect(abs(simd_distance(performed.world[leg.1].position, performed.world[leg.2].position) - referenceLengths[index].1) < 0.0001)
            let expectedY = original.world[leg.2].position.y
            if hop.phase == .airborne {
                #expect(performedFeet[index].y > expectedY + 0.01)
            } else {
                #expect(abs(performedFeet[index].y - expectedY) < 0.006)
                #expect(abs(performedFeet[index].x - original.world[leg.2].position.x - hop.horizontal) < 0.006)
            }
            if let previousFeet { #expect(simd_distance(performedFeet[index], previousFeet[index]) < 0.035) }
        }
        previousFeet = performedFeet
        let horizontal = performed.world[hips].position.x - original.world[hips].position.x
        horizontalExtremes = min(horizontalExtremes.lowerBound, horizontal)...max(horizontalExtremes.upperBound, horizontal)
        if hop.phase == .anticipation {
            kneeBendObserved = kneeBendObserved || legs.contains {
                abs(simd_dot(original.pose[$0.1].rotation.vector, performed.pose[$0.1].rotation.vector)) < 0.999
            }
        }
        if abs(simd_dot(original.pose[head].rotation.vector, performed.pose[head].rotation.vector)) < 0.9999 { changedHeadFrames += 1 }
    }
    #expect(horizontalExtremes.lowerBound < -0.14)
    #expect(horizontalExtremes.upperBound > 0.14)
    #expect(kneeBendObserved)
    #expect(changedHeadFrames > motion.frameCount / 2)
    performed.pose = motion.pose(at: 4)
    performed.updateWorld()
    let hand = try #require(performed.node("jnt_R_hand00_00"))
    #expect(performed.world[hand].position.y > performed.world[hips].position.y + 0.28)
}

@Test func mondayEntrancePeeksBrieflyThenSpringsUpInUnderSixTenthsOfASecond() {
    #expect(MondayEntrance.duration < 0.6)
    #expect(MondayEntrance.offset(at: -1) < -2)
    #expect(MondayEntrance.offset(at: 0.12) == -1.15)
    #expect(MondayEntrance.offset(at: 0.16) == MondayEntrance.offset(at: 0.12))
    #expect(MondayEntrance.offset(at: 0.22) < MondayEntrance.offset(at: 0.17))
    #expect(MondayEntrance.offset(at: 0.42) > 0)
    #expect(MondayEntrance.offset(at: MondayEntrance.duration) == 0)
    #expect(MondayEntrance.offset(at: 20) == 0)
    for time in stride(from: 0.0, through: MondayEntrance.duration, by: 0.001) {
        let before = MondayEntrance.offset(at: time - 0.000001)
        let after = MondayEntrance.offset(at: time + 0.000001)
        #expect(abs(after - before) < 0.00005)
    }
}

@Test func speechOnsetIgnoresBackgroundNoiseAndPreservesImmediateSpeech() {
    let quiet = Array(repeating: Float(0.0001), count: 30)
    let speech: [Float] = [0.01, -0.01, 0.08, -0.08]
    let delayed = SpeechEnvelope(samples: quiet + speech, sampleRate: 100)
    #expect(delayed.firstSoundTime == 0.3)
    #expect(SpeechEnvelope(samples: speech, sampleRate: 100).firstSoundTime == 0)
    #expect(SpeechEnvelope(samples: quiet, sampleRate: 100).firstSoundTime == nil)
}

@Test func speechEnvelopeFollowsSpeechAndIsSilentOutsidePlayback() {
    let envelope = SpeechEnvelope(samples: [0, 0, 0.04, -0.04, 0.2, -0.2, 0, 0], sampleRate: 100)
    #expect(envelope.level(at: 0) == 0)
    #expect(abs(envelope.level(at: 0.02) - 0.04) < 0.0001)
    #expect(abs(envelope.level(at: 0.04) - 0.2) < 0.0001)
    #expect(envelope.level(at: 0.06) < envelope.level(at: 0.04))
    #expect(envelope.level(at: 0.08) == 0)
    #expect(envelope.level(at: -1) == 0)
    #expect(envelope.level(at: .nan) == 0)
    #expect(envelope.level(at: .infinity) == 0)
}

@Test func speechEnvelopeBridgesBriefConsonantGapsButReleasesWithinSixtyMilliseconds() {
    let samples: [Float] = [0, 0, 0.1, -0.1] + Array(repeating: 0, count: 16)
    let envelope = SpeechEnvelope(samples: samples, sampleRate: 100)
    #expect(envelope.level(at: 0.019) == 0)
    #expect(envelope.level(at: 0.04) > 0.05)
    #expect(envelope.level(at: 0.06) > 0.02)
    #expect(envelope.level(at: 0.08) < 0.001)
    #expect(envelope.level(at: 0.14) == 0)
}
