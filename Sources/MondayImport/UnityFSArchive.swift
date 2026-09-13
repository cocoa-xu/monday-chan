import Foundation

public struct UnityFSArchive: Sendable {
    public struct Entry: Sendable, Equatable {
        public let name: String
        public let offset: Int
        public let size: Int
    }

    public let entries: [Entry]
    private let content: Data

    public init(data: Data, headerKey: String? = nil) throws {
        let data = try Self.decoded(data, headerKey: headerKey)
        var reader = BinaryReader(data)
        guard try reader.cString() == "UnityFS" else { throw UnityImportError.invalidFormat("Not a UnityFS archive") }
        let format = try reader.uint32()
        _ = try reader.cString()
        _ = try reader.cString()
        _ = try reader.uint64()
        let compressedInfoSize = Int(try reader.uint32())
        let infoSize = Int(try reader.uint32())
        let flags = try reader.uint32()
        guard format >= 6 else { throw UnityImportError.unsupported("UnityFS version") }
        guard compressedInfoSize <= 64 * 1024 * 1024, infoSize <= 64 * 1024 * 1024 else {
            throw UnityImportError.invalidFormat("Invalid block metadata size")
        }
        if format >= 7 { try reader.align(16) }
        let blockStart = reader.offset
        let infoData: Data
        if flags & 0x80 != 0 {
            try reader.seek(data.count - compressedInfoSize)
            infoData = try reader.bytes(compressedInfoSize)
            try reader.seek(blockStart)
        } else {
            infoData = try reader.bytes(compressedInfoSize)
        }
        let decodedInfo = try Self.decompress(infoData, size: infoSize, flags: UInt16(flags & 0x3f))
        var info = BinaryReader(decodedInfo)
        _ = try info.bytes(16)
        let blockCount = Int(try info.int32())
        guard blockCount >= 0, blockCount <= 100_000 else { throw UnityImportError.invalidFormat("Invalid block count") }
        var blocks: [(Int, Int, UInt16)] = []
        var totalSize = 0
        for _ in 0..<blockCount {
            let uncompressed = Int(try info.uint32())
            let compressed = Int(try info.uint32())
            guard uncompressed <= 128 * 1024 * 1024 - totalSize else { throw UnityImportError.invalidFormat("Archive is too large") }
            totalSize += uncompressed
            blocks.append((uncompressed, compressed, try info.uint16()))
        }
        let entryCount = Int(try info.int32())
        guard entryCount >= 0, entryCount <= 1_024 else { throw UnityImportError.invalidFormat("Invalid entry count") }
        var entries: [Entry] = []
        var entryNames = Set<String>()
        for _ in 0..<entryCount {
            let offset = try Self.int(try info.int64())
            let size = try Self.int(try info.int64())
            _ = try info.uint32()
            let name = try info.cString()
            guard Self.validEntryName(name), entryNames.insert(name).inserted else {
                throw UnityImportError.invalidFormat("Invalid entry name")
            }
            entries.append(Entry(name: name, offset: offset, size: size))
        }
        if flags & 0x200 != 0 { try reader.align(16) }
        var content = Data()
        content.reserveCapacity(totalSize)
        for block in blocks {
            content.append(try Self.decompress(try reader.bytes(block.1), size: block.0, flags: block.2))
        }
        guard entries.allSatisfy({ $0.offset >= 0 && $0.size >= 0 && $0.offset <= content.count - $0.size }) else {
            throw UnityImportError.invalidFormat("Invalid entry range")
        }
        let ranges = entries.sorted { $0.offset < $1.offset }
        if ranges.count > 1 {
            for index in 1..<ranges.count where ranges[index - 1].offset + ranges[index - 1].size > ranges[index].offset {
                throw UnityImportError.invalidFormat("Overlapping entries")
            }
        }
        self.entries = entries
        self.content = content
    }

    public func data(for entry: Entry) throws -> Data {
        guard entries.contains(entry) else { throw UnityImportError.invalidFormat("Unknown entry") }
        return content.subdata(in: entry.offset..<(entry.offset + entry.size))
    }

    public func data(named name: String) throws -> Data {
        guard let entry = entries.first(where: { $0.name == name }) else { throw UnityImportError.invalidFormat("Missing entry") }
        return try data(for: entry)
    }

    static func decompress(_ data: Data, size: Int, flags: UInt16) throws -> Data {
        switch flags & 0x3f {
        case 0:
            guard data.count == size else { throw UnityImportError.invalidFormat("Block size mismatch") }
            return data
        case 2, 3:
            return try LZ4.decode(data, size: size)
        default:
            throw UnityImportError.unsupported("UnityFS compression")
        }
    }

    static func validEntryName(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 4_096, !name.hasPrefix("/"), !name.contains("\\") else { return false }
        return name.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { $0 != "." && $0 != ".." && !$0.isEmpty }
    }

    static func decoded(_ data: Data, headerKey: String?) throws -> Data {
        if data.starts(with: Data("UnityFS".utf8)) { return data }
        guard let headerKey, !headerKey.isEmpty else { throw UnityImportError.invalidFormat("Not a UnityFS archive") }
        let source = [UInt8](headerKey.utf8)
        var mixed = [UInt8](repeating: 0, count: source.count * 2)
        for (index, byte) in source.enumerated() {
            mixed[index * 2] = byte
            mixed[mixed.count - 1 - index * 2] = ~byte
        }
        var hash: UInt8 = 0x7c
        for byte in mixed { hash = (hash >> 1 | hash << 7) ^ byte }
        let mask = mixed.map { $0 ^ hash }
        var output = [UInt8](data)
        for index in 0..<min(256, output.count) { output[index] ^= mask[index % mask.count] }
        let decoded = Data(output)
        guard decoded.starts(with: Data("UnityFS".utf8)) else { throw UnityImportError.invalidFormat("Invalid header key") }
        return decoded
    }

    static func int(_ value: Int64) throws -> Int {
        guard value >= 0, value <= Int64(Int.max) else { throw UnityImportError.outOfBounds }
        return Int(value)
    }
}

public struct UnityAssetBundle: Sendable {
    public let archive: UnityFSArchive
    public let assets: UnitySerializedFile

    public init(data: Data, headerKey: String? = nil) throws {
        let archive = try UnityFSArchive(data: data, headerKey: headerKey)
        guard let entry = archive.entries.first(where: { !$0.name.hasSuffix(".resS") }) else {
            throw UnityImportError.invalidFormat("Missing serialized asset")
        }
        self.archive = archive
        self.assets = try UnitySerializedFile(data: archive.data(for: entry))
    }

    public func externalResourceData(named name: String) throws -> Data {
        guard let entry = archive.entries.first(where: { ($0.name as NSString).lastPathComponent == name }) else {
            throw UnityImportError.invalidFormat("Missing external resource")
        }
        return try archive.data(for: entry)
    }
}
