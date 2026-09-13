import Foundation

enum UnityExportError: LocalizedError {
    case missing(String)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .missing(let detail): "Missing model data: \(detail)"
        case .invalid(let detail): "Invalid model data: \(detail)"
        }
    }
}

extension UnityValue {
    func required(_ key: String) throws -> UnityValue {
        guard let value = self[key] else { throw UnityExportError.missing(key) }
        return value
    }

    func requiredNumber(_ key: String) throws -> Double {
        guard let value = self[key]?.number, value.isFinite else { throw UnityExportError.invalid(key) }
        return value
    }

    func requiredInt(_ key: String) throws -> Int {
        let value = try requiredNumber(key)
        guard value.rounded() == value, let result = Int(exactly: value) else {
            throw UnityExportError.invalid(key)
        }
        return result
    }

    func requiredInt64(_ key: String) throws -> Int64 {
        if let value = self[key]?.signed { return value }
        if let value = self[key]?.unsigned, value <= UInt64(Int64.max) { return Int64(value) }
        throw UnityExportError.invalid(key)
    }

    func requiredString(_ key: String) throws -> String {
        guard let value = self[key]?.string else { throw UnityExportError.invalid(key) }
        return value
    }

    func requiredArray(_ key: String) throws -> [UnityValue] {
        guard let value = self[key]?.array else { throw UnityExportError.invalid(key) }
        return value
    }

    func requiredBytes(_ key: String) throws -> Data {
        if let value = self[key]?.bytes { return value }
        if let values = self[key]?.array {
            return try Data(values.map {
                guard let value = $0.unsigned, value <= UInt8.max else { throw UnityExportError.invalid(key) }
                return UInt8(value)
            })
        }
        throw UnityExportError.invalid(key)
    }

    func pathID() throws -> Int64 {
        return try requiredInt64("m_PathID")
    }
}

extension Data {
    func uint16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, count >= 2, offset <= count - 2 else { throw UnityExportError.invalid("binary range") }
        return withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) }
    }

    func uint32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, count >= 4, offset <= count - 4 else { throw UnityExportError.invalid("binary range") }
        return withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }

    func float32(at offset: Int) throws -> Float { Float(bitPattern: try uint32(at: offset)) }
}
