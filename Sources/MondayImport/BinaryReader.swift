import Foundation

public enum UnityImportError: LocalizedError, Equatable {
    case invalidFormat(String)
    case outOfBounds
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let detail): "Invalid game resource: \(detail)"
        case .outOfBounds: "The game resource is truncated or contains an invalid range."
        case .unsupported(let detail): "Unsupported game resource: \(detail)"
        }
    }
}

enum ByteOrder {
    case little
    case big
}

struct BinaryReader {
    let data: Data
    var offset = 0
    var order: ByteOrder

    init(_ data: Data, order: ByteOrder = .big) {
        self.data = data
        self.order = order
    }

    var remaining: Int { data.count - offset }

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, offset >= 0, count <= remaining else { throw UnityImportError.outOfBounds }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func uint8() throws -> UInt8 { try bytes(1)[0] }
    mutating func int8() throws -> Int8 { Int8(bitPattern: try uint8()) }
    mutating func uint16() throws -> UInt16 { try integer(UInt16.self) }
    mutating func int16() throws -> Int16 { Int16(bitPattern: try uint16()) }
    mutating func uint32() throws -> UInt32 { try integer(UInt32.self) }
    mutating func int32() throws -> Int32 { Int32(bitPattern: try uint32()) }
    mutating func uint64() throws -> UInt64 { try integer(UInt64.self) }
    mutating func int64() throws -> Int64 { Int64(bitPattern: try uint64()) }
    mutating func float32() throws -> Float { Float(bitPattern: try uint32()) }
    mutating func float64() throws -> Double { Double(bitPattern: try uint64()) }

    mutating func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let raw = try bytes(MemoryLayout<T>.size)
        var value: T = 0
        switch order {
        case .big:
            for byte in raw { value = (value << 8) | T(byte) }
        case .little:
            for (index, byte) in raw.enumerated() { value |= T(byte) << T(index * 8) }
        }
        return value
    }

    mutating func cString() throws -> String {
        guard let end = data[offset..<min(data.count, offset + 4_096)].firstIndex(of: 0),
              let value = String(data: data.subdata(in: offset..<end), encoding: .utf8) else {
            throw UnityImportError.invalidFormat("Invalid string")
        }
        offset = end + 1
        return value
    }

    mutating func alignedString() throws -> String {
        let count = Int(try int32())
        guard count >= 0, let value = String(data: try bytes(count), encoding: .utf8) else {
            throw UnityImportError.invalidFormat("Invalid string")
        }
        try align(4)
        return value
    }

    mutating func align(_ alignment: Int) throws {
        let next = (offset + alignment - 1) / alignment * alignment
        guard next <= data.count else { throw UnityImportError.outOfBounds }
        offset = next
    }

    mutating func seek(_ position: Int) throws {
        guard position >= 0, position <= data.count else { throw UnityImportError.outOfBounds }
        offset = position
    }
}
