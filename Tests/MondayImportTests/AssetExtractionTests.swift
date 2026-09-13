import Foundation
import MondayCore
import Testing
@testable import MondayImport

@Test func bundleDiscoveryFindsOnlyRequiredNamedAndCachedAssets() throws {
    let root = try extractionDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    for (index, kind) in MondayBundleKind.allCases.enumerated() {
        let relative = index.isMultiple(of: 2) ? "nested/" + kind.identifier : "cache/" + kind.cacheDirectory + "/content-hash"
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([UInt8(index)]).write(to: url)
    }
    try Data([99]).write(to: root.appendingPathComponent("unrelated"))
    let files = try MondayBundleFiles.locate(in: root)
    #expect(files.urls.count == 4)
    for (index, kind) in MondayBundleKind.allCases.enumerated() {
        #expect(try Data(contentsOf: #require(files.urls[kind])) == Data([UInt8(index)]))
    }
}

@Test func bundleDiscoveryRejectsAmbiguousCachesAndSkipsSymlinks() throws {
    let root = try extractionDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = root.appendingPathComponent(MondayBundleKind.body.cacheDirectory)
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    try Data([1]).write(to: cache.appendingPathComponent("first"))
    try Data([2]).write(to: cache.appendingPathComponent("second"))
    #expect(throws: AssetError.self) { try MondayBundleFiles.locate(in: root) }
    let outside = try extractionDirectory()
    defer { try? FileManager.default.removeItem(at: outside) }
    let file = outside.appendingPathComponent("model")
    try Data([1]).write(to: file)
    let linked = root.appendingPathComponent("linked")
    try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
    #expect(MondayAssetExtractor.safeFile("linked/model", in: root) == nil)
    #expect(MondayAssetExtractor.safeFile("../model", in: root) == nil)
}

@Test func preparedImportKeepsOnlyRequiredCharacterAndMouths() throws {
    let root = try extractionDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let destination = root.appendingPathComponent("imported")
    for path in MondayAssetExtractor.preparedFiles {
        let url = source.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: url)
    }
    let characters = ["characters": ["06002", "unrelated"].map { ["id": $0, "name": "Name", "group": "Group", "outfit": "Outfit", "model": "wrong", "mouths": "wrong"] }]
    try JSONSerialization.data(withJSONObject: characters).write(to: source.appendingPathComponent("characters.json"))
    let catalog: [String: Any] = ["cells": ["mouth_00": 0, "mouth_07": 7, "mouth_17": 17, "mouth_35": 35, "mouth_99": 99],
                                "projector_size": ["x": 1, "y": 2, "z": 3]]
    try JSONSerialization.data(withJSONObject: catalog).write(to: source.appendingPathComponent(MondayAssetExtractor.expressionPath + "index.json"))
    try Data([99]).write(to: source.appendingPathComponent("unrelated.glb"))
    try MondayAssetExtractor.extract(from: source, to: destination)
    let library = try AssetLibrary(root: destination)
    let character = try library.character("06002")
    #expect(character.model == "./models/06002.glb")
    #expect(try library.mouths(for: character).cells.count == 4)
    #expect(try library.mouths(for: character).projector_size.z == 3)
    let entries = try #require(FileManager.default.enumerator(atPath: destination.path))
    let files = entries.compactMap { $0 as? String }.filter { MondayAssetExtractor.safeFile($0, in: destination) != nil }
    #expect(Set(files) == Set(MondayAssetExtractor.preparedFiles))
}

@Test func incompleteNativeExtractionCleansStagingWithoutChangingTheSource() throws {
    let root = try extractionDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let destination = root.appendingPathComponent("imported")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let marker = source.appendingPathComponent("keep")
    try Data([1, 2, 3]).write(to: marker)
    #expect(throws: AssetError.self) { try MondayAssetExtractor.extract(from: source, to: destination) }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    #expect(try Data(contentsOf: marker) == Data([1, 2, 3]))
    #expect(throws: AssetError.self) { try MondayAssetExtractor.extract(from: source, to: source.appendingPathComponent("nested")) }
}

private func extractionDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MondayImport-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func binaryReadsRejectOverflowingOffsets() {
    let bytes = Data([0, 0, 0, 0])
    #expect(throws: UnityExportError.self) { try bytes.uint16(at: Int.max) }
    #expect(throws: UnityExportError.self) { try bytes.uint32(at: Int.max) }
}
