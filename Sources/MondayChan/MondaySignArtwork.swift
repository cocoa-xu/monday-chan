import AppKit
import Foundation
import MondayMetal

@MainActor
enum MondaySignArtwork {
    static let attachment = BoardAttachment(anchorNode: "jnt_C_spine00_01", size: SIMD2(0.65, 0.325),
                                             offset: SIMD3(0, 0.63, 0.22))

    private static let texture = Result { try renderTexture() }

    static func textureData() throws -> Data { try texture.get() }

    private static func renderTexture() throws -> Data {
        guard let url = AppResources.bundle.url(forResource: "monday-sign", withExtension: "svg", subdirectory: "Assets"),
              let source = NSImage(contentsOf: url) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 512, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        source.draw(in: CGRect(x: 0, y: 0, width: 1024, height: 512), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}
