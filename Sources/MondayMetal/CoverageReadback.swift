import Foundation
import MondayCore
import Metal

private struct SharedBuffer: @unchecked Sendable {
    let value: MTLBuffer
}

struct CoverageReadback: Sendable {
    fileprivate let storage: SharedBuffer
    let mask: CoverageMask
    var buffer: MTLBuffer { storage.value }
}

final class CoverageReadbackPool: @unchecked Sendable {
    private let device: MTLDevice
    private let lock = NSLock()
    private var available: [MTLBuffer] = []
    private var byteCount = 0

    init(device: MTLDevice) { self.device = device }

    func acquire(width: Int, height: Int) -> CoverageReadback {
        let count = width * height
        let buffer = lock.withLock {
            if count != byteCount {
                available.removeAll()
                byteCount = count
            }
            return available.popLast() ?? device.makeBuffer(length: count, options: .storageModeShared)!
        }
        let storage = SharedBuffer(value: buffer)
        let pixels = Data(bytesNoCopy: buffer.contents(), count: count, deallocator: .custom { [self, storage] _, _ in
            lock.withLock {
                if storage.value.length == byteCount, available.count < 3 { available.append(storage.value) }
            }
        })
        return CoverageReadback(storage: storage, mask: CoverageMask(width: width, height: height, alpha: pixels))
    }
}
