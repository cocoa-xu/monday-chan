import Foundation
import Testing
@testable import MondayChan

@Test func resourceRemovalPreservesSourceFilesAndUnrelatedData() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("data")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root.deletingLastPathComponent()) }
    for path in ImportedResourceRemoval.paths + ["source/game.bundle", "source/video.mov", "notes.txt"] {
        let file = root.appendingPathComponent(path)
        try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(path.utf8).write(to: file)
    }
    let trash = try #require(try await ImportedResourceRemoval().remove(from: root))
    defer { try? manager.removeItem(at: trash) }
    for path in ImportedResourceRemoval.paths {
        #expect(!manager.fileExists(atPath: root.appendingPathComponent(path).path))
        #expect(try Data(contentsOf: trash.appendingPathComponent(path)) == Data(path.utf8))
    }
    for path in ["source/game.bundle", "source/video.mov", "notes.txt"] {
        #expect(try Data(contentsOf: root.appendingPathComponent(path)) == Data(path.utf8))
    }
    #expect(try await ImportedResourceRemoval().remove(from: root) == nil)
}

@Test func resourceRemovalRejectsSymlinkParentsBeforeMovingAnyFiles() async throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let data = root.appendingPathComponent("data")
    let source = root.appendingPathComponent("source")
    try manager.createDirectory(at: data, withIntermediateDirectories: true)
    try manager.createDirectory(at: source, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    try Data("catalog".utf8).write(to: data.appendingPathComponent("characters.json"))
    try Data("original".utf8).write(to: source.appendingPathComponent("06002.glb"))
    try manager.createSymbolicLink(at: data.appendingPathComponent("models"), withDestinationURL: source)
    await #expect(throws: MondayImportError.self) { try await ImportedResourceRemoval().remove(from: data) }
    #expect(try Data(contentsOf: data.appendingPathComponent("characters.json")) == Data("catalog".utf8))
    #expect(try Data(contentsOf: source.appendingPathComponent("06002.glb")) == Data("original".utf8))
}
