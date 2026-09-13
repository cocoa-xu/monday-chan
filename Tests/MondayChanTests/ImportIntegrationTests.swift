import AVFAudio
import Foundation
import MondayCore
import Testing
@testable import MondayChan

private let importEnvironment = ProcessInfo.processInfo.environment

@Test(.enabled(if: importEnvironment["MONDAY_CHAN_GAME_FILES"] != nil
               && importEnvironment["MONDAY_CHAN_VIDEO"] != nil))
func importedGameFilesAndVideoProduceACompletePlayablePerformance() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MondayChan-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let importer = MondayImporter()
    let source = URL(fileURLWithPath: try #require(importEnvironment["MONDAY_CHAN_GAME_FILES"]), isDirectory: true)
    let media = URL(fileURLWithPath: try #require(importEnvironment["MONDAY_CHAN_VIDEO"]))
    let imported = try await importer.importAssets(gameFolder: source, mediaFile: media, destination: root)
    let performance = try await MondayPerformanceLoader().load(library: AssetLibrary(root: imported.root))
    #expect(performance.character.id == "06002")
    #expect((9.5...12).contains(Double(performance.motion.duration)))
    #expect((0.3...0.7).contains(performance.audioStartTime))
    let audio = try AVAudioFile(forReading: imported.audio)
    #expect(audio.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatAppleLossless)
    #expect(audio.processingFormat.sampleRate == 48_000)
    #expect(audio.processingFormat.channelCount == 2)
    let files = try #require(FileManager.default.enumerator(atPath: imported.root.path))
    let relativePaths = try files.compactMap { entry -> String? in
        guard let path = entry as? String,
              try imported.root.appendingPathComponent(path).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return nil }
        return path
    }
    #expect(Set(relativePaths) == Set([
        "characters.json", "models/06002.glb", "events/monday/kanade.m4a",
        "motions/idle01_typ000_lp_bdy00.json", "motions/run00_typ000_lp_bdy00.json",
        "characters/06002/expressions/index.json",
        "characters/06002/expressions/mouth_00.png", "characters/06002/expressions/mouth_07.png",
        "characters/06002/expressions/mouth_17.png", "characters/06002/expressions/mouth_35.png"
    ]))
}
