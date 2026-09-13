import CoreGraphics
import Foundation
import ImageIO
import MondayCore
import Testing
@testable import MondayImport

@Test func nativeASTCDecoderPreservesSolidColorAndAlpha() throws {
    let decoder = try UnityTextureDecoder()
    let block = Data([0xfc, 0xfd, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                      0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff])
    let image = try decoder.decode(width: 6, height: 6, format: 50, data: block)
    #expect(image.pixels == Data((0..<36).flatMap { _ in [UInt8(255), 0, 0, 255] }))
    #expect(throws: AssetError.self) { try decoder.decode(width: 7, height: 6, format: 50, data: block) }
}

@Test(arguments: [UInt16(0x00ff), 0x01ff, 0x7fff, 0xfe00, 0xffff])
func astcUNorm8UsesTheHighEightBitsWithoutChangingAlpha(_ value: UInt16) throws {
    let decoder = try UnityTextureDecoder()
    var block = Data([0xfc, 0xfd, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])
    for _ in 0..<4 { block.append(contentsOf: [UInt8(truncatingIfNeeded: value), UInt8(value >> 8)]) }
    let image = try decoder.decode(width: 6, height: 6, format: 50, data: block)
    #expect(image.pixels == Data(repeating: UInt8(value >> 8), count: 36 * 4))
}

@Test func textureRowsAndMouthCropsKeepTheirOrientation() throws {
    let decoder = try UnityTextureDecoder()
    let pixels = Data([255, 0, 0, 255, 0, 255, 0, 128, 0, 0, 255, 255, 255, 255, 255, 0])
    let image = try decoder.decode(width: 2, height: 2, format: 4, data: pixels)
    #expect(try image.cropped(x: 0, y: 0, width: 2, height: 1).pixels == pixels.suffix(8))
    #expect(try image.cropped(x: 0, y: 1, width: 2, height: 1).pixels == pixels.prefix(8))
    let png = try image.png()
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(decoded.width == 2 && decoded.height == 2)
    #expect(throws: AssetError.self) { try image.cropped(x: 2, y: 0, width: 1, height: 1) }
}

@Test(.enabled(if: FileManager.default.fileExists(atPath: "data/source/A33921")))
func nativeTexturePixelsMatchValidatedReference() throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("MondayTextures-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: output) }
    try MondayAssetExtractor.extract(from: URL(fileURLWithPath: "data/source"), to: output)
    let expected = try CharacterModel(url: URL(fileURLWithPath: "data/models/06002.glb"))
    let actual = try CharacterModel(url: output.appendingPathComponent("models/06002.glb"))
    #expect(expected.images.count == actual.images.count)
    for (reference, native) in zip(expected.images, actual.images) {
        #expect(try pngPixels(reference) == pngPixels(native))
    }
    for index in [0, 7, 17, 35] {
        let path = "characters/06002/expressions/" + String(format: "mouth_%02d.png", index)
        let reference = try Data(contentsOf: URL(fileURLWithPath: "data/" + path))
        let native = try Data(contentsOf: output.appendingPathComponent(path))
        #expect(try pngPixels(reference) == pngPixels(native))
    }
}

private func pngPixels(_ data: Data) throws -> Data {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    var pixels = Data(count: image.width * image.height * 4)
    try pixels.withUnsafeMutableBytes { bytes in
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try #require(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                             bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space, bitmapInfo: info))
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return pixels
}
