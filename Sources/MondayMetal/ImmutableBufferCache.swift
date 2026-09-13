import Metal

final class ImmutableBufferCache {
    private let device: MTLDevice
    private var entries: [Int: [MTLBuffer]] = [:]

    init(device: MTLDevice) { self.device = device }

    func buffer<Element>(_ values: [Element]) -> MTLBuffer {
        values.withUnsafeBytes { bytes in
            var hasher = Hasher()
            hasher.combine(bytes: bytes)
            let key = hasher.finalize()
            if let existing = entries[key]?.first(where: { UnsafeRawBufferPointer(start: $0.contents(), count: $0.length).elementsEqual(bytes) }) { return existing }
            let buffer = device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)!
            entries[key, default: []].append(buffer)
            return buffer
        }
    }
}
