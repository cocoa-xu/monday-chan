import AVFAudio
import Foundation
import ImageIO
import MondayImport
import MondayCore

struct MondayImportProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case locating
        case extractingModel
        case extractingMotions
        case extractingMouths
        case convertingMedia
        case validating
        case installing
    }

    let phase: Phase
    let fraction: Double

    init(phase: Phase, fraction: Double) {
        self.phase = phase
        self.fraction = min(max(fraction, 0), 1)
    }
}

struct MondayImportedAssets: Equatable, Sendable {
    let root: URL
    let model: URL
    let idleMotion: URL
    let runMotion: URL
    let mouthsDirectory: URL
    let audio: URL
}

enum MondayImportError: LocalizedError, Equatable {
    case invalidGameFolder
    case invalidMedia
    case unexpectedAudioDuration
    case extractionFailed(String)
    case unsafeDestination
    case incomplete(String)

    var errorDescription: String? {
        switch self {
        case .invalidGameFolder: "The selected folder does not contain the required game assets."
        case .invalidMedia: "The selected media file does not contain usable audio."
        case .unexpectedAudioDuration: "This does not look like the Monday video. Choose the original clip or its audio and try again."
        case .extractionFailed(let message): message.isEmpty ? "Asset extraction failed." : message
        case .unsafeDestination: "The import destination is unsafe."
        case .incomplete(let path): "The imported assets are incomplete: \(path)"
        }
    }
}

actor MondayImporter {
    typealias Extract = @Sendable (URL, URL, @escaping @Sendable (MondayAssetExtractionPhase) -> Void) async throws -> Void
    private let extract: Extract
    private let fileManager: FileManager

    init(extract: @escaping Extract = { source, destination, progress in
        try MondayAssetExtractor.extract(from: source, to: destination, progress: progress)
    }, fileManager: FileManager = .default) {
        self.extract = extract
        self.fileManager = fileManager
    }

    func importAssets(gameFolder: URL, mediaFile: URL, destination: URL,
                             progress: @escaping @Sendable (MondayImportProgress) -> Void = { _ in }) async throws -> MondayImportedAssets {
        let source = gameFolder.standardizedFileURL.resolvingSymlinksInPath()
        let media = mediaFile.standardizedFileURL.resolvingSymlinksInPath()
        let target = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard source.hasDirectoryPath || (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw MondayImportError.invalidGameFolder
        }
        guard fileManager.fileExists(atPath: media.path) else { throw MondayImportError.invalidMedia }
        try validateDestination(target)
        guard !overlaps(source, target), !media.path.hasPrefix(target.path + "/"),
              media != target else { throw MondayImportError.unsafeDestination }
        try Task.checkCancellation()
        progress(MondayImportProgress(phase: .locating, fraction: 0))

        let parent = target.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let workspace = parent.appendingPathComponent(".monday-import-\(UUID().uuidString)", isDirectory: true)
        let staging = workspace.appendingPathComponent("data", isDirectory: true)
        let backup = parent.appendingPathComponent(".monday-backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: workspace)
        }

        progress(MondayImportProgress(phase: .extractingModel, fraction: 0.1))
        do {
            try await extract(source, staging) { phase in
                switch phase {
                case .model: progress(MondayImportProgress(phase: .extractingModel, fraction: 0.1))
                case .motions: progress(MondayImportProgress(phase: .extractingMotions, fraction: 0.55))
                case .mouths: progress(MondayImportProgress(phase: .extractingMouths, fraction: 0.68))
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MondayImportError.extractionFailed(error.localizedDescription)
        }
        try Task.checkCancellation()
        progress(MondayImportProgress(phase: .convertingMedia, fraction: 0.75))
        let audio = staging.appendingPathComponent("events/monday/kanade.m4a")
        try fileManager.createDirectory(at: audio.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await convertMedia(media, to: audio)
        try Task.checkCancellation()
        progress(MondayImportProgress(phase: .validating, fraction: 0.9))
        _ = try validate(destination: staging)
        progress(MondayImportProgress(phase: .installing, fraction: 0.97))

        try Task.checkCancellation()
        var movedOriginal = false
        let installed: MondayImportedAssets
        do {
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.moveItem(at: target, to: backup)
                movedOriginal = true
            }
            try fileManager.moveItem(at: staging, to: target)
            installed = try validate(destination: target)
        } catch {
            if movedOriginal {
                if fileManager.fileExists(atPath: target.path) { try? fileManager.removeItem(at: target) }
                if !fileManager.fileExists(atPath: target.path) { try? fileManager.moveItem(at: backup, to: target) }
            }
            throw error
        }
        if movedOriginal { try? fileManager.removeItem(at: backup) }
        progress(MondayImportProgress(phase: .installing, fraction: 1))
        return installed
    }

    func validate(destination: URL) throws -> MondayImportedAssets {
        let library = try AssetLibrary(root: destination)
        let character = try library.character("06002")
        guard character.model.replacingOccurrences(of: "./", with: "") == "models/06002.glb",
              character.mouths.replacingOccurrences(of: "./", with: "") == "characters/06002/expressions/" else {
            throw MondayImportError.incomplete("character paths")
        }
        let model = try library.url(for: "models/06002.glb")
        let idle = try library.url(for: "motions/idle01_typ000_lp_bdy00.json")
        let run = try library.url(for: "motions/run00_typ000_lp_bdy00.json")
        let audio = try library.url(for: "events/monday/kanade.m4a")
        let mouths = try library.mouths(for: character)
        for name in mouths.cells.keys {
            let url = try library.url(for: character.mouths + name + ".png")
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                throw MondayImportError.incomplete(name)
            }
        }
        let loaded = try CharacterModel(url: model)
        guard !loaded.primitives.isEmpty, !loaded.images.isEmpty else { throw MondayImportError.incomplete("model") }
        _ = try MondayChoreography(model: loaded)
        _ = try MotionClip(url: idle)
        _ = try MotionClip(url: run)
        let file = try AVAudioFile(forReading: audio)
        guard file.length > 0, file.length <= AVAudioFramePosition(file.processingFormat.sampleRate * 60),
              file.processingFormat.channelCount <= 2 else { throw MondayImportError.invalidMedia }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard abs(duration - MondayAudioImporter.performanceDuration) <= MondayAudioImporter.durationTolerance else {
            throw MondayImportError.unexpectedAudioDuration
        }
        return MondayImportedAssets(root: library.root, model: model, idleMotion: idle, runMotion: run,
                                    mouthsDirectory: library.root.appendingPathComponent(character.mouths), audio: audio)
    }

    private func overlaps(_ first: URL, _ second: URL) -> Bool {
        first == second || first.path.hasPrefix(second.path + "/") || second.path.hasPrefix(first.path + "/")
    }

    private func validateDestination(_ destination: URL) throws {
        let path = destination.path
        guard destination.isFileURL, path != "/", path != FileManager.default.homeDirectoryForCurrentUser.path,
              !path.isEmpty, destination.lastPathComponent != ".", destination.lastPathComponent != ".." else {
            throw MondayImportError.unsafeDestination
        }
    }

    private func convertMedia(_ source: URL, to destination: URL) async throws {
        try await MondayAudioImporter.extractMonday(from: source, to: destination)
    }
}
