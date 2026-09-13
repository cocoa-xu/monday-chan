import Foundation
import Testing
import MondayCore

@Test func coverageUsesPixelAlphaAndRejectsTransparentCorners() {
    let mask = CoverageMask(width: 3, height: 2, alpha: Data([0, 255, 0, 0, 0, 100]))
    #expect(mask.contains(normalizedX: 0.5, normalizedY: 0.1))
    #expect(mask.contains(normalizedX: 0.9, normalizedY: 0.9))
    #expect(!mask.contains(normalizedX: 0.1, normalizedY: 0.1))
    #expect(!mask.contains(normalizedX: 1, normalizedY: 0.5))
    #expect(!mask.contains(normalizedX: -.infinity, normalizedY: 0.5))
    #expect(!mask.contains(normalizedX: 0.5, normalizedY: .nan))
}
