import AppKit
import Testing

@Test func appIconLayersRemainVectorAndShareLettering() throws {
    let assets = iconRepository.appendingPathComponent("packaging/AppIcon.icon/Assets")
    for file in try FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil) {
        #expect(file.pathExtension == "svg")
        let document = try XMLDocument(contentsOf: file)
        #expect(try document.nodes(forXPath: "//*[local-name()='image' or local-name()='text' or local-name()='clipPath']").isEmpty)
        #expect(document.rootElement()?.attribute(forName: "viewBox")?.stringValue == "0 0 1024 1024")
    }
    let color = try XMLDocument(contentsOf: assets.appendingPathComponent("03-Month.svg"))
    let monochrome = try XMLDocument(contentsOf: assets.appendingPathComponent("03-Month-Mono.svg"))
    let colorGroup = try #require(color.nodes(forXPath: "/*[local-name()='svg']/*[local-name()='g']").first as? XMLElement)
    let monochromeGroup = try #require(monochrome.nodes(forXPath: "/*[local-name()='svg']/*[local-name()='g']").first as? XMLElement)
    #expect(colorGroup.attribute(forName: "transform")?.stringValue == monochromeGroup.attribute(forName: "transform")?.stringValue)
    let colorShape = try #require(color.nodes(forXPath: "//*[local-name()='path' and @fill != 'none']").first as? XMLElement)
    let monochromeShape = try #require(monochrome.nodes(forXPath: "//*[local-name()='path' and @fill != 'none']").first as? XMLElement)
    #expect(colorShape.attribute(forName: "d")?.stringValue == monochromeShape.attribute(forName: "d")?.stringValue)
}

@Test @MainActor func nativeAppIconPreservesLetteringAndProducesCompatibleAssets() throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("Monday Icon Tests \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: output) }
    try runIconTool("/bin/bash", arguments: [iconRepository.appendingPathComponent("scripts/compile-icon.sh").path, output.path], output: output)
    let compiled = try iconPropertyList(output.appendingPathComponent("partial.plist"))
    let bundle = try iconPropertyList(iconRepository.appendingPathComponent("packaging/Info.plist"))
    for key in ["CFBundleIconName", "CFBundleIconFile"] {
        #expect(compiled[key] as? String == "AppIcon")
        #expect(bundle[key] as? String == compiled[key] as? String)
    }
    #expect(try Data(contentsOf: output.appendingPathComponent("Assets.car")).count > 0)
    let image = try #require(NSImage(contentsOf: output.appendingPathComponent("AppIcon.icns")))
    let sizes = Set(image.representations.map(\.pixelsWide))
    #expect(Set([16, 32, 64, 128, 256, 512, 1024]).isSubset(of: sizes))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] != "true"))
@MainActor func iconComposerRendersReadableLetteringInEveryAppearance() throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("Monday Icon Tests \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: output) }
    let developer = try runIconTool("/usr/bin/xcode-select", arguments: ["-p"], output: output).trimmingCharacters(in: .whitespacesAndNewlines)
    let renderer = URL(fileURLWithPath: developer).deletingLastPathComponent()
        .appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool")
    let strokes: [(Double, Double)] = [(0.46, 0.285), (0.46, 0.42), (0.46, 0.562), (0.675, 0.683)]
    for appearance in ["Default", "ClearLight", "ClearDark"] {
        for size in [64, 256] {
            let rendered = output.appendingPathComponent("\(appearance)-\(size).png")
            try runIconTool(renderer.path, arguments: [
                iconRepository.appendingPathComponent("packaging/AppIcon.icon").path,
                "--export-image", "--output-file", rendered.path, "--platform", "macOS",
                "--rendition", appearance, "--width", String(size), "--height", String(size), "--scale", "1"
            ], output: output)
            let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: rendered)))
            #expect(bitmap.pixelsWide == size && bitmap.pixelsHigh == size)
            #expect(try iconColor(bitmap, at: (0, 0)).alphaComponent < 0.01)
            let background = try iconBrightness(iconColor(bitmap, at: (0.08, 0.5)))
            let colors = try strokes.map { try iconColor(bitmap, at: $0) }
            let brightness = colors.map(iconBrightness)
            if appearance == "Default" {
                #expect(colors.allSatisfy { $0.redComponent > $0.greenComponent && $0.greenComponent > $0.blueComponent })
                #expect(brightness.allSatisfy { background - $0 > 0.15 })
            } else {
                #expect(brightness.allSatisfy { $0 - background > 0.18 })
                #expect(try #require(brightness.max()) - #require(brightness.min()) < 0.12)
            }
        }
    }
}

private var iconRepository: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

@discardableResult private func runIconTool(_ executable: String, arguments: [String], output: URL) throws -> String {
    let log = output.appendingPathComponent("tool.log")
    FileManager.default.createFile(atPath: log.path, contents: nil)
    let handle = try FileHandle(forWritingTo: log)
    defer { try? handle.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = iconRepository
    process.standardOutput = handle
    process.standardError = handle
    try process.run()
    process.waitUntilExit()
    let result = try String(contentsOf: log, encoding: .utf8)
    try #require(process.terminationStatus == 0, "\(executable): \(result)")
    return result
}

private func iconPropertyList(_ url: URL) throws -> [String: Any] {
    try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
}

private func iconColor(_ bitmap: NSBitmapImageRep, at point: (Double, Double)) throws -> NSColor {
    try #require(bitmap.colorAt(x: Int(point.0 * Double(bitmap.pixelsWide)),
                               y: Int(point.1 * Double(bitmap.pixelsHigh)))?.usingColorSpace(.sRGB))
}

private func iconBrightness(_ color: NSColor) -> Double {
    0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
}
