import AppKit
import MondayCore
import Testing
@testable import MondayMetal

@Test @MainActor func materialAlphaModesControlCoverageWithoutMakingOpaqueTexturesTransparent() throws {
    for mode in ["OPAQUE", "MASK", "BLEND"] {
        for alpha in [UInt8(0), 110, 200, 255] {
            let renderer = try CharacterRenderer(model: alphaFixture(mode: mode, textureAlpha: alpha))
            let pixels = try renderer.snapshot(width: 64, height: 64, captureCoverage: true)
            let center = (32 * 64 + 32) * 4
            let expected: UInt8 = mode == "OPAQUE" ? 255 : mode == "MASK" ? (alpha >= 128 ? 255 : 0) : alpha
            #expect(pixels[center + 3] == expected, "\(mode), texture alpha \(alpha)")
            #expect(renderer.coverage?.alpha[32 * 64 + 32] == expected)
            if expected == 255 { #expect(pixels[center + 2] == 255) }
        }
    }
    let renderer = try CharacterRenderer(model: alphaFixture(mode: "OPAQUE", textureAlpha: 110, factorAlpha: 0))
    let pixels = try renderer.snapshot(width: 64, height: 64)
    #expect(pixels[(32 * 64 + 32) * 4 + 3] == 255)
}

@Test @MainActor func cutoutThresholdIncludesEqualityAndIgnoresCutoffForOtherModes() throws {
    for (mode, alpha, factor, cutoff, expected) in [
        ("MASK", UInt8(255), Float(0.5), Float(0.5), UInt8(255)),
        ("MASK", 255, 0.49, 0.5, 0),
        ("MASK", 0, 0, 0, 255),
        ("MASK", 255, 1, 1.1, 0),
        ("OPAQUE", 0, 0, 1.1, 255),
        ("BLEND", 110, 1, 1.1, 110)
    ] {
        let renderer = try CharacterRenderer(model: alphaFixture(mode: mode, textureAlpha: alpha, factorAlpha: factor, cutoff: cutoff))
        let pixels = try renderer.snapshot(width: 64, height: 64)
        #expect(pixels[(32 * 64 + 32) * 4 + 3] == expected, "\(mode), cutoff \(cutoff)")
    }
}

private func alphaFixture(mode: String, textureAlpha: UInt8, factorAlpha: Float = 1, cutoff: Float = 0.5) throws -> CharacterModel {
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bitmapFormat: .alphaNonpremultiplied, bytesPerRow: 4, bitsPerPixel: 32))
    for (index, byte) in [UInt8(255), 0, 0, textureAlpha].enumerated() { bitmap.bitmapData?[index] = byte }
    let image = try #require(bitmap.representation(using: .png, properties: [:]))
    let positions: [Float] = [-1, -1, 0, 1, -1, 0, 0, 1, 0]
    var binary = positions.withUnsafeBytes { Data($0) }
    let imageOffset = binary.count
    binary.append(image)
    while binary.count % 4 != 0 { binary.append(0) }
    let document: [String: Any] = [
        "asset": ["version": "2.0"], "buffers": [["byteLength": binary.count]],
        "bufferViews": [["buffer": 0, "byteLength": imageOffset], ["buffer": 0, "byteOffset": imageOffset, "byteLength": image.count]],
        "accessors": [["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"]],
        "nodes": [["mesh": 0]], "scenes": [["nodes": [0]]],
        "meshes": [["primitives": [["attributes": ["POSITION": 0], "material": 0]]]],
        "images": [["bufferView": 1, "mimeType": "image/png"]], "textures": [["source": 0]],
        "materials": [["alphaMode": mode, "alphaCutoff": cutoff,
                       "pbrMetallicRoughness": ["baseColorTexture": ["index": 0], "baseColorFactor": [1, 1, 1, factorAlpha]]]]
    ]
    return try CharacterModel(data: packagedGLB(document: document, binary: binary))
}

private func packagedGLB(document: [String: Any], binary: Data) throws -> Data {
    var json = try JSONSerialization.data(withJSONObject: document)
    while json.count % 4 != 0 { json.append(32) }
    var result = Data()
    func word(_ value: UInt32) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
    }
    word(0x46546c67); word(2); word(UInt32(28 + json.count + binary.count))
    word(UInt32(json.count)); word(0x4e4f534a); result.append(json)
    word(UInt32(binary.count)); word(0x004e4942); result.append(binary)
    return result
}
