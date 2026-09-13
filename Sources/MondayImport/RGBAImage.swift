import CoreGraphics
import Foundation
import ImageIO
import MondayCore
import UniformTypeIdentifiers

struct RGBAImage {
    let width: Int
    let height: Int
    let pixels: Data

    init(width: Int, height: Int, pixels: Data) throws {
        guard width > 0, height > 0, width <= 16_384, height <= 16_384,
              pixels.count == width * height * 4 else { throw AssetError.invalid("RGBA image size") }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func cropped(x: Int, y: Int, width: Int, height: Int) throws -> RGBAImage {
        guard x >= 0, y >= 0, width > 0, height > 0,
              width <= self.width - x, height <= self.height - y else {
            throw AssetError.invalid("image crop")
        }
        var result = Data(capacity: width * height * 4)
        for row in y..<(y + height) {
            let offset = (row * self.width + x) * 4
            result.append(pixels[offset..<(offset + width * 4)])
        }
        return try RGBAImage(width: width, height: height, pixels: result)
    }

    func png() throws -> Data {
        guard let provider = CGDataProvider(data: pixels as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw AssetError.invalid("PNG image")
        }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else {
            throw AssetError.invalid("PNG destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw AssetError.invalid("PNG encoding") }
        return result as Data
    }
}
