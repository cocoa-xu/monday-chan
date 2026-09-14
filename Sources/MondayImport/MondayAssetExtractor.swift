import Foundation
import MondayCore

public enum MondayAssetExtractionPhase: Sendable {
    case model, motions, mouths
}

public enum MondayAssetExtractor {
    static let mouthCells = [0, 7, 17, 35]
    static let expressionPath = "characters/06002/expressions/"
    public static let preparedFiles = ["characters.json", "models/06002.glb", "motions/idle01_typ000_lp_bdy00.json",
                                "motions/run00_typ000_lp_bdy00.json", expressionPath + "index.json"]
        + mouthCells.map { expressionPath + String(format: "mouth_%02d.png", $0) }

    public static func extract(from source: URL, to destination: URL,
                               progress: @Sendable (MondayAssetExtractionPhase) -> Void = { _ in }) throws {
        try Task.checkCancellation()
        let source = source.standardizedFileURL.resolvingSymlinksInPath()
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard source != destination, !destination.path.hasPrefix(source.path + "/"),
              !source.path.hasPrefix(destination.path + "/"),
              !FileManager.default.fileExists(atPath: destination.path) else { throw AssetError.invalid("import destination") }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            if try copyPrepared(from: source, to: destination) { return }
            let files = try MondayBundleFiles.locate(in: source)
            _ = try files.gameRelease()
            progress(.model)
            let body = try files.load(.body)
            let hair = try files.load(.hair)
            let decoder = try UnityTextureDecoder()
            let model = try MondayGLBExporter.export(body: body, hair: hair) { bundle, texture in
                try Task.checkCancellation()
                return try decoder.decode(texture: texture, bundle: bundle).png()
            }
            try write(model, path: "models/06002.glb", to: destination)
            progress(.motions)
            for (kind, identifier) in [(MondayBundleKind.idle, "idle01_typ000_lp_bdy00"), (.run, "run00_typ000_lp_bdy00")] {
                try Task.checkCancellation()
                let motion = try MondayMotionExporter.export(bundle: files.load(kind), identifier: identifier)
                try write(motion, path: "motions/" + identifier + ".json", to: destination)
            }
            progress(.mouths)
            let faces = try body.assets.objects.filter { $0.className == "Texture2D" }.map { try body.assets.value(for: $0) }
                .filter { $0["m_Name"]?.string?.hasSuffix("_fdc_col") == true }
            guard faces.count == 1 else { throw AssetError.invalid("face atlas") }
            let atlas = try decoder.decode(texture: faces[0], bundle: body)
            guard atlas.width == 1024, atlas.height == 1024 else { throw AssetError.invalid("face atlas dimensions") }
            for index in mouthCells {
                try Task.checkCancellation()
                let mouth = try atlas.cropped(x: index % 5 * 192, y: index / 5 * 128, width: 189, height: 128)
                try write(mouth.png(), path: expressionPath + String(format: "mouth_%02d.png", index), to: destination)
            }
            try writeMouthCatalog(size: ["x": 0.15889662504196167, "y": 0.1066666692495346, "z": 0.16632884740829468], to: destination)
            try writeCharacterCatalog(to: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    static func safeFile(_ path: String, in root: URL) -> URL? {
        var current = root
        for component in path.split(separator: "/") {
            guard component != "..", component != "." else { return nil }
            current.appendPathComponent(String(component))
            guard let values = try? current.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == false else { return nil }
        }
        guard (try? current.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
        return current
    }

    private static func copyPrepared(from source: URL, to destination: URL) throws -> Bool {
        let files = preparedFiles.compactMap { safeFile($0, in: source) }
        guard files.count == preparedFiles.count else { return false }
        let catalog = try JSONDecoder().decode(CharacterCatalog.self, from: Data(contentsOf: files[0]))
        guard catalog.characters.contains(where: { $0.id == "06002" }) else { throw AssetError.missing("character 06002") }
        let mouths = try JSONDecoder().decode(MouthCatalog.self, from: Data(contentsOf: files[4]))
        guard mouthCells.allSatisfy({ mouths.cells[String(format: "mouth_%02d", $0)] == $0 }) else { throw AssetError.invalid("mouth cells") }
        let size = mouths.projector_size
        guard [size.x, size.y, size.z].allSatisfy({ $0.isFinite && $0 > 0 }) else { throw AssetError.invalid("mouth projector") }
        for (path, file) in zip(preparedFiles, files) where path != "characters.json" && !path.hasSuffix("index.json") {
            try Task.checkCancellation()
            let target = destination.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: file, to: target)
        }
        try writeMouthCatalog(size: ["x": Double(size.x), "y": Double(size.y), "z": Double(size.z)], to: destination)
        try writeCharacterCatalog(to: destination)
        return true
    }

    private static func writeCharacterCatalog(to destination: URL) throws {
        let character = ["id": "06002", "name": "Otonose Kanade", "group": "ReGLOSS", "outfit": "nrml-0058",
                         "model": "./models/06002.glb", "mouths": "./" + expressionPath]
        try write(JSONSerialization.data(withJSONObject: ["characters": [character]], options: [.sortedKeys]), path: "characters.json", to: destination)
    }

    private static func writeMouthCatalog(size: [String: Double], to destination: URL) throws {
        let cells = Dictionary(uniqueKeysWithValues: mouthCells.map { (String(format: "mouth_%02d", $0), $0) })
        let data = try JSONSerialization.data(withJSONObject: ["cells": cells, "projector_size": size], options: [.sortedKeys])
        try write(data, path: expressionPath + "index.json", to: destination)
    }

    private static func write(_ data: Data, path: String, to destination: URL) throws {
        let url = destination.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
