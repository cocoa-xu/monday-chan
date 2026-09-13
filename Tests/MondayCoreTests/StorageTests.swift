import Foundation
import Testing
@testable import MondayCore

@Test func identicalMeshArraysShareStorageWithoutMergingDifferentBits() {
    var cache = ArrayStorageCache<SIMD4<Float>>()
    let first = cache.share([SIMD4(1, 2, 3, 0)])
    var second = cache.share([SIMD4(1, 2, 3, 0)])
    let different = cache.share([SIMD4(1, 2, 3, -Float.zero)])
    first.withUnsafeBufferPointer { a in
        second.withUnsafeBufferPointer { b in #expect(a.baseAddress == b.baseAddress) }
        different.withUnsafeBufferPointer { b in #expect(a.baseAddress != b.baseAddress) }
    }
    second[0].x = 4
    #expect(first[0].x == 1)
    #expect(second[0].x == 4)
}

