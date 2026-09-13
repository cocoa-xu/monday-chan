import Foundation

enum LZ4 {
    static func decode(_ source: Data, size: Int) throws -> Data {
        guard size >= 0, size <= 128 * 1024 * 1024 else { throw UnityImportError.invalidFormat("Invalid LZ4 size") }
        var input = 0
        var output = [UInt8]()
        output.reserveCapacity(size)
        let bytes = [UInt8](source)
        while input < bytes.count {
            let token = bytes[input]
            input += 1
            var literals = Int(token >> 4)
            if literals == 15 { literals += try extensionLength(bytes, &input) }
            guard literals <= bytes.count - input, literals <= size - output.count else { throw UnityImportError.invalidFormat("Invalid LZ4 literals") }
            output.append(contentsOf: bytes[input..<(input + literals)])
            input += literals
            if input == bytes.count { break }
            guard input + 2 <= bytes.count else { throw UnityImportError.invalidFormat("Invalid LZ4 offset") }
            let distance = Int(bytes[input]) | Int(bytes[input + 1]) << 8
            input += 2
            guard distance > 0, distance <= output.count else { throw UnityImportError.invalidFormat("Invalid LZ4 distance") }
            var length = Int(token & 15) + 4
            if token & 15 == 15 { length += try extensionLength(bytes, &input) }
            guard length <= size - output.count else { throw UnityImportError.invalidFormat("Invalid LZ4 match") }
            for _ in 0..<length { output.append(output[output.count - distance]) }
        }
        guard output.count == size else { throw UnityImportError.invalidFormat("LZ4 size mismatch") }
        return Data(output)
    }

    static func extensionLength(_ input: [UInt8], _ offset: inout Int) throws -> Int {
        var length = 0
        while true {
            guard offset < input.count else { throw UnityImportError.invalidFormat("Invalid LZ4 length") }
            let value = Int(input[offset])
            offset += 1
            let result = length.addingReportingOverflow(value)
            guard !result.overflow else { throw UnityImportError.invalidFormat("Invalid LZ4 length") }
            length = result.partialValue
            if value != 255 { return length }
        }
    }
}
