import Foundation
import MondayCore
import Testing
@testable import MondayChan

@Test(.enabled(if: mondayPerformanceAssetsAreAvailable()))
func mondayLoaderRefreshesAStaleCharacterCatalog() async throws {
    let source = URL(fileURLWithPath: "data", isDirectory: true)
    let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("MondayChanMonday-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: fixture) }
    try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    try copy("models/06002.glb", from: source, to: fixture)
    try copy("motions/idle01_typ000_lp_bdy00.json", from: source, to: fixture)
    try copy("motions/run00_typ000_lp_bdy00.json", from: source, to: fixture)
    try copy("events/monday/kanade.m4a", from: source, to: fixture)
    let staleLibrary = try AssetLibrary(root: fixture)
    #expect(throws: AssetError.missing("character 06002")) { try staleLibrary.character("06002") }

    let catalogData = try Data(contentsOf: source.appendingPathComponent("characters.json"))
    let catalog = try #require(JSONSerialization.jsonObject(with: catalogData) as? [String: Any])
    let characters = try #require(catalog["characters"] as? [[String: Any]])
    let kanade = try #require(characters.first { $0["id"] as? String == "06002" })
    let refreshedCatalog = try JSONSerialization.data(withJSONObject: ["characters": [kanade]], options: [.prettyPrinted, .sortedKeys])
    try refreshedCatalog.write(to: fixture.appendingPathComponent("characters.json"), options: .atomic)

    let performance = try await MondayPerformanceLoader().load(library: staleLibrary)
    #expect(performance.character.id == "06002")
    #expect(performance.audioURL.standardizedFileURL == fixture.appendingPathComponent("events/monday/kanade.m4a").standardizedFileURL)
}

private func mondayPerformanceAssetsAreAvailable() -> Bool {
    let root = URL(fileURLWithPath: "data", isDirectory: true)
    return ["characters.json", "models/06002.glb", "motions/idle01_typ000_lp_bdy00.json",
            "motions/run00_typ000_lp_bdy00.json", "events/monday/kanade.m4a"]
        .allSatisfy { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
}

private func copy(_ path: String, from source: URL, to destination: URL) throws {
    let target = destination.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: source.appendingPathComponent(path), to: target)
}
