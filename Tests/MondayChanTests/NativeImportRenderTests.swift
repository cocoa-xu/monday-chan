import AppKit
import MondayCore
import MondayImport
import MondayMetal
import Testing
@testable import MondayChan

@Test(.enabled(if: FileManager.default.fileExists(atPath: "data/source/A33921"))) @MainActor
func nativeImportPreservesRenderedGeometryLightingAndExpressions() async throws {
    let output = URL(fileURLWithPath: ".build/native-render-data")
    try? FileManager.default.removeItem(at: output)
    try await Task.detached {
        try MondayAssetExtractor.extract(from: URL(fileURLWithPath: "data/source"), to: output)
    }.value
    let referenceLibrary = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let nativeLibrary = try AssetLibrary(root: output)
    let character = try referenceLibrary.character("06002")
    let reference = try CharacterRenderer(model: CharacterModel(url: referenceLibrary.url(for: character.model)))
    let native = try CharacterRenderer(model: CharacterModel(url: nativeLibrary.url(for: character.model)))
    try reference.loadMouths(library: referenceLibrary, character: character, conformToFace: true)
    try native.loadMouths(library: nativeLibrary, character: character, conformToFace: true)
    for yaw: Float in [0, 0.7, .pi] {
        native.camera = reference.camera
        native.camera.yaw = yaw
        reference.camera.yaw = yaw
        for mouth in [0, 7, 17, 35] {
            native.mouthIndex = mouth
            reference.mouthIndex = mouth
            native.faceWeights = ["b_eye.eye_005": 0.5]
            reference.faceWeights = native.faceWeights
            let expected = try reference.snapshot(width: 480, height: 640)
            let actual = try native.snapshot(width: 480, height: 640)
            let changed = zip(expected, actual).count { $0 != $1 }
            #expect(changed == 0, "Yaw \(yaw), mouth \(mouth): \(changed) different channels")
        }
    }
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 480, pixelsHigh: 640,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                              colorSpaceName: .deviceRGB, bitmapFormat: [.alphaNonpremultiplied],
                                              bytesPerRow: 480 * 4, bitsPerPixel: 32))
    native.camera.yaw = 0
    let frame = try native.snapshot(width: 480, height: 640)
    for index in stride(from: 0, to: frame.count, by: 4) {
        bitmap.bitmapData?[index] = frame[index + 2]
        bitmap.bitmapData?[index + 1] = frame[index + 1]
        bitmap.bitmapData?[index + 2] = frame[index]
        bitmap.bitmapData?[index + 3] = frame[index + 3]
    }
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("../native-import-render.png"))
}
