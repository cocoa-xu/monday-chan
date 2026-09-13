import Metal
import Testing
@testable import MondayMetal

@Test func identicalUploadsShareBuffersWhileDistinctBitsRemainIndependent() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var cache: ImmutableBufferCache? = ImmutableBufferCache(device: device)
    let first = try #require(cache?.buffer([SIMD4<Float>(1, 2, 3, 0)]))
    #expect(first === cache?.buffer([SIMD4<Float>(1, 2, 3, 0)]))
    #expect(first !== cache?.buffer([SIMD4<Float>(1, 2, 3, -Float.zero)]))
    #expect(first !== cache?.buffer([SIMD4<Float>(1, 2, 3, 0), .zero]))
    cache = nil
    #expect(first.contents().load(as: SIMD4<Float>.self) == SIMD4(1, 2, 3, 0))
}
