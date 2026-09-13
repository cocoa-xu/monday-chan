import AVFAudio
import Foundation
import Testing
@testable import MondayChan

@Test func audioImportPreservesSamplesChannelsAndTimingInLosslessStorage() async throws {
    let root = try importTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("speech.wav")
    let destination = root.appendingPathComponent("speech.m4a")
    let frames = 24_000
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
    let input = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
    input.frameLength = AVAudioFrameCount(frames)
    for frame in 0..<frames {
        input.floatChannelData?[0][frame] = Float(frame % 128 - 64) / 128
        input.floatChannelData?[1][frame] = Float(frame % 64 - 32) / 128
    }
    do {
        let file = try AVAudioFile(forWriting: source, settings: format.settings)
        try file.write(from: input)
    }
    let original = try Data(contentsOf: source)
    try await MondayAudioImporter.extract(from: source, to: destination)
    #expect(try Data(contentsOf: source) == original)
    let output = try AVAudioFile(forReading: destination)
    #expect(output.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatAppleLossless)
    #expect(output.processingFormat.sampleRate == 48_000)
    #expect(output.processingFormat.channelCount == 2)
    #expect(output.length == frames)
    let decoded = try #require(AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: AVAudioFrameCount(frames)))
    try output.read(into: decoded)
    for channel in 0..<2 {
        let expected = try #require(input.floatChannelData?[channel])
        let actual = try #require(decoded.floatChannelData?[channel])
        #expect((0..<frames).allSatisfy { abs(expected[$0] - actual[$0]) < 0.0000001 })
    }
}

@Test func failedExtractionLeavesExistingDataAndSourceUntouched() async throws {
    let root = try importTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source", isDirectory: true)
    let target = root.appendingPathComponent("installed", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let media = source.appendingPathComponent("clip.mp4")
    try Data([1, 2, 3]).write(to: media)
    let marker = target.appendingPathComponent("keep")
    try Data([9]).write(to: marker)
    let importer = MondayImporter()
    await #expect(throws: MondayImportError.self) {
        try await importer.importAssets(gameFolder: source, mediaFile: media, destination: target)
    }
    #expect(try Data(contentsOf: marker) == Data([9]))
    #expect(try Data(contentsOf: media) == Data([1, 2, 3]))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["installed", "source"])
}

@Test func importRejectsDestinationsThatOverlapUserFiles() async throws {
    let root = try importTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let media = source.appendingPathComponent("clip.mp4")
    try Data([1]).write(to: media)
    let importer = MondayImporter()
    for target in [root, source, source.appendingPathComponent("nested")] {
        await #expect(throws: MondayImportError.unsafeDestination) {
            try await importer.importAssets(gameFolder: source, mediaFile: media, destination: target)
        }
    }
}

@Test func cancellingExtractionStopsWorkAndKeepsInstalledData() async throws {
    let root = try importTestDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source", isDirectory: true)
    let target = root.appendingPathComponent("installed", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let media = source.appendingPathComponent("clip.mp4")
    try Data([1]).write(to: media)
    let marker = root.appendingPathComponent("started")
    let importer = MondayImporter { _, staging, _ in
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data([1]).write(to: marker)
        try await Task.sleep(for: .seconds(30))
    }
    let task = Task { try await importer.importAssets(gameFolder: source, mediaFile: media, destination: target) }
    for _ in 0..<100 where !FileManager.default.fileExists(atPath: marker.path) {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(FileManager.default.fileExists(atPath: marker.path))
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(FileManager.default.fileExists(atPath: target.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".monday-") })
}

private func importTestDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MondayChan-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
