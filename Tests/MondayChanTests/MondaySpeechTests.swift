import AppKit
import MondayCore
import Testing
@testable import MondayChan

@Test func mondaySpeechUsesSmallOpenMouthsEvenForQuietSpeechAndCapsLoudSpeech() {
    #expect(MondayMouth.speaking(level: 0) == .rest)
    #expect(MondayMouth.speaking(level: 0.004) == .rest)
    #expect(MondayMouth.speaking(level: 0.02) == .smallRounded)
    #expect(MondayMouth.speaking(level: 0.05) == .rounded)
    #expect(MondayMouth.speaking(level: 0.1) == .smallSmile)
    #expect(MondayMouth.speaking(level: 1) == .smallSmile)
}

@Test(.enabled(if: FileManager.default.fileExists(atPath: "data/events/monday/kanade.m4a")))
func mondayClipUsesEverySmallMouthAndClosesDuringThePause() async throws {
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let performance = try await MondayPerformanceLoader().load(library: library)
    let onset = try #require(performance.envelope.firstSoundTime)
    #expect(performance.audioStartTime > 0.4)
    #expect(onset > performance.audioStartTime)
    #expect(onset - performance.audioStartTime <= 0.041)
    #expect(MondayEntrance.duration + onset - performance.audioStartTime < 0.65)
    let mouths = Set(stride(from: 0.0, to: Double(performance.motion.duration), by: 1 / 120).map {
        performance.mouth(at: $0)
    })
    #expect(mouths == Set(MondayMouth.allCases.map(\.rawValue)))
    #expect(performance.mouth(at: 0.2) == MondayMouth.rest.rawValue)
    #expect(performance.mouth(at: 4.5) == MondayMouth.rest.rawValue)
    #expect(performance.mouth(at: Double(performance.motion.duration) + 0.1) == MondayMouth.rest.rawValue)
    for time in [5.5, 6.6, 10.6] {
        #expect(performance.mouth(at: time) != MondayMouth.rest.rawValue)
    }
}

