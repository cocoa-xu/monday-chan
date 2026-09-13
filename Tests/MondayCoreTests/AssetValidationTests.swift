import Foundation
import Testing
@testable import MondayCore

@Test func assetPathsCannotEscapeThroughTraversalOrSymlinks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let data = root.appendingPathComponent("data")
    try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
    try Data([1]).write(to: root.appendingPathComponent("outside"))
    try FileManager.default.createSymbolicLink(at: data.appendingPathComponent("linked"), withDestinationURL: root)
    let library = try AssetLibrary(root: data)
    for path in ["../outside", "linked/outside"] {
        #expect(throws: AssetError.invalid("path leaves the data directory")) { try library.url(for: path) }
    }
}

@Test func catalogRejectsOtherCharactersAndDuplicateEntries() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for ids in [["unrelated"], ["06002", "06002"]] {
        let characters = ids.map { ["id": $0, "name": "Character", "group": "", "outfit": "", "model": "model.glb", "mouths": "expressions/"] }
        try JSONSerialization.data(withJSONObject: ["characters": characters]).write(to: root.appendingPathComponent("characters.json"))
        #expect(throws: AssetError.invalid("Monday-chan requires character 06002")) { try AssetLibrary(root: root) }
    }
}

@Test func invalidNodeTransformsAndRepeatedSkinJointsAreRejected() throws {
    let nodes: [[String: Any]] = [
        ["rotation": [0, 0, 0, 0]],
        ["matrix": Array(repeating: 0, count: 16)]
    ]
    for node in nodes {
        #expect(throws: AssetError.self) { try CharacterModel(data: fixture(nodes: [node])) }
    }
    #expect(throws: AssetError.invalid("skin joint index")) {
        try CharacterModel(data: fixture(nodes: [["name": "Head"]], skins: [["joints": [0, 0]]]))
    }
}

@Test func malformedGLBChunksFailWithoutReadingBeyondTheBuffer() throws {
    let valid = try fixture(nodes: [["name": "Root"]])
    for count in [0, 4, 19, valid.count - 1] {
        #expect(throws: AssetError.self) { try CharacterModel(data: Data(valid.prefix(count))) }
    }
    var invalid = valid
    invalid.replaceSubrange(12..<16, with: [252, 255, 255, 255])
    #expect(throws: AssetError.invalid("GLB chunk length")) { try CharacterModel(data: invalid) }
}

@Test func coverageMapsAppKitCoordinatesWithoutStretching() {
    let mask = CoverageMask(width: 2, height: 4, alpha: Data([255, 0, 0, 0, 0, 0, 0, 255]))
    #expect(mask.contains(point: CGPoint(x: 75, y: 175), in: CGSize(width: 200, height: 200)))
    #expect(mask.contains(point: CGPoint(x: 125, y: 25), in: CGSize(width: 200, height: 200)))
    #expect(!mask.contains(point: CGPoint(x: 25, y: 175), in: CGSize(width: 200, height: 200)))
    #expect(!mask.contains(point: CGPoint(x: 75, y: 175), in: .zero))
}

private func fixture(nodes: [[String: Any]], skins: [[String: Any]] = []) throws -> Data {
    let document: [String: Any] = [
        "buffers": [["byteLength": 0]], "bufferViews": [], "accessors": [],
        "nodes": nodes, "meshes": [], "skins": skins, "scenes": [["nodes": [0]]]
    ]
    var json = try JSONSerialization.data(withJSONObject: document)
    while json.count % 4 != 0 { json.append(32) }
    var data = Data()
    func word(_ value: UInt32) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
    word(0x46546c67)
    word(2)
    word(UInt32(28 + json.count))
    word(UInt32(json.count))
    word(0x4e4f534a)
    data.append(json)
    word(0)
    word(0x004e4942)
    return data
}
