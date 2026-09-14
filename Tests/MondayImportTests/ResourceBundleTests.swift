import Foundation
import Testing
@testable import MondayImport

@Test func packagedApplicationResolvesImportResources() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MondayImportResources-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }

    let application = root.appendingPathComponent("MondayChan.app")
    let resources = application.appendingPathComponent("Contents/Resources")
    let importBundle = resources.appendingPathComponent("MondayChan_MondayImport.bundle")
    try FileManager.default.createDirectory(at: importBundle, withIntermediateDirectories: true)
    try bundleInfo(identifier: "test.MondayChan", packageType: "APPL")
        .write(to: application.appendingPathComponent("Contents/Info.plist"))
    try bundleInfo(identifier: "test.MondayChan.MondayImport", packageType: "BNDL")
        .write(to: importBundle.appendingPathComponent("Info.plist"))

    let applicationBundle = try #require(Bundle(url: application))
    let resolved = try #require(MondayImportResources.resolve(in: applicationBundle))
    #expect(resolved.bundleURL.standardizedFileURL == importBundle.standardizedFileURL)
}

private func bundleInfo(identifier: String, packageType: String) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: [
        "CFBundleIdentifier": identifier,
        "CFBundlePackageType": packageType
    ], format: .xml, options: 0)
}
