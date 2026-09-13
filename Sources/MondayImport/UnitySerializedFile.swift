import Foundation

public indirect enum UnityValue: Sendable, Equatable {
    case signed(Int64)
    case unsigned(UInt64)
    case float(Double)
    case bool(Bool)
    case string(String)
    case bytes(Data)
    case array([UnityValue])
    case object([String: UnityValue])

    public var object: [String: UnityValue]? { if case let .object(value) = self { value } else { nil } }
    public var array: [UnityValue]? { if case let .array(value) = self { value } else { nil } }
    public var string: String? { if case let .string(value) = self { value } else { nil } }
    public var bytes: Data? { if case let .bytes(value) = self { value } else { nil } }
    public var signed: Int64? { if case let .signed(value) = self { value } else { nil } }
    public var unsigned: UInt64? { if case let .unsigned(value) = self { value } else { nil } }
    public var number: Double? {
        switch self {
        case let .float(value): value
        case let .signed(value): Double(value)
        case let .unsigned(value): Double(value)
        default: nil
        }
    }
    public subscript(_ key: String) -> UnityValue? { object?[key] }
    public subscript(_ index: Int) -> UnityValue? { array.flatMap { $0.indices.contains(index) ? $0[index] : nil } }
}

public struct UnityType: Sendable {
    public let classID: Int32
    let root: UnityTypeNode
}

public struct UnityObjectInfo: Sendable, Equatable {
    public let pathID: Int64
    public let classID: Int32
    public let className: String
    public let byteSize: Int
    let byteOffset: Int
    let typeIndex: Int
}

struct UnityTypeNode: Sendable {
    let type: String
    let name: String
    let size: Int32
    let flags: UInt32
    let children: [UnityTypeNode]
}

public struct UnitySerializedFile: Sendable {
    public let version: UInt32
    public let platform: Int32
    public let unityVersion: String
    public let objects: [UnityObjectInfo]
    public let types: [UnityType]
    private let data: Data
    private let order: ByteOrder

    public init(data: Data) throws {
        guard data.count <= 128 * 1024 * 1024 else { throw UnityImportError.invalidFormat("Serialized file is too large") }
        var reader = BinaryReader(data)
        _ = try reader.uint32()
        _ = try reader.uint32()
        let version = try reader.uint32()
        _ = try reader.uint32()
        guard version == 22 else { throw UnityImportError.unsupported("Serialized file version") }
        let endian = try reader.uint8()
        _ = try reader.bytes(3)
        _ = try reader.uint32()
        let fileSize = try reader.uint64()
        let dataOffset = try reader.uint64()
        _ = try reader.uint64()
        guard fileSize == data.count, dataOffset <= fileSize else { throw UnityImportError.invalidFormat("Invalid serialized header") }
        reader.order = endian == 0 ? .little : .big
        let unityVersion = try reader.cString()
        let platform = try reader.int32()
        guard try reader.uint8() != 0 else { throw UnityImportError.unsupported("Missing type tree") }
        let typeCount = Int(try reader.int32())
        guard typeCount >= 0, typeCount <= 1_024 else { throw UnityImportError.invalidFormat("Invalid type count") }
        var types: [UnityType] = []
        for _ in 0..<typeCount { types.append(try Self.readType(&reader)) }
        let objectCount = Int(try reader.int32())
        guard objectCount >= 0, objectCount <= 100_000 else { throw UnityImportError.invalidFormat("Invalid object count") }
        var objects: [UnityObjectInfo] = []
        var pathIDs = Set<Int64>()
        for _ in 0..<objectCount {
            try reader.align(4)
            let pathID = try reader.int64()
            let relativeOffset = try reader.int64()
            let byteSize = Int(try reader.uint32())
            let typeIndex = Int(try reader.int32())
            guard pathIDs.insert(pathID).inserted, typeIndex >= 0, typeIndex < types.count, relativeOffset >= 0,
                  UInt64(relativeOffset) <= fileSize - dataOffset,
                  byteSize <= Int(fileSize - dataOffset - UInt64(relativeOffset)) else {
                throw UnityImportError.invalidFormat("Invalid object range")
            }
            let classID = types[typeIndex].classID
            objects.append(UnityObjectInfo(pathID: pathID, classID: classID,
                                           className: Self.className(classID), byteSize: byteSize,
                                           byteOffset: Int(dataOffset) + Int(relativeOffset), typeIndex: typeIndex))
        }
        let orderedObjects = objects.sorted { $0.byteOffset < $1.byteOffset }
        if orderedObjects.count > 1 {
            for index in 1..<orderedObjects.count where orderedObjects[index - 1].byteOffset + orderedObjects[index - 1].byteSize > orderedObjects[index].byteOffset {
                throw UnityImportError.invalidFormat("Overlapping objects")
            }
        }
        self.version = version
        self.platform = platform
        self.unityVersion = unityVersion
        self.objects = objects
        self.types = types
        self.data = data
        self.order = reader.order
    }

    public func value(for object: UnityObjectInfo) throws -> UnityValue {
        guard let stored = objects.first(where: { $0.pathID == object.pathID }), stored == object else {
            throw UnityImportError.invalidFormat("Unknown object")
        }
        let range = stored.byteOffset..<(stored.byteOffset + stored.byteSize)
        var reader = BinaryReader(data.subdata(in: range), order: order)
        var budget = 2_000_000
        let value = try Self.readValue(types[stored.typeIndex].root, &reader, depth: 0, budget: &budget)
        guard reader.offset == stored.byteSize else { throw UnityImportError.invalidFormat("Object size mismatch") }
        return value
    }

    public func object(pathID: Int64) -> UnityObjectInfo? { objects.first { $0.pathID == pathID } }

    static func readType(_ reader: inout BinaryReader) throws -> UnityType {
        let classID = try reader.int32()
        _ = try reader.uint8()
        let scriptIndex = try reader.int16()
        if classID == 114 || scriptIndex >= 0 { _ = try reader.bytes(16) }
        _ = try reader.bytes(16)
        let count = Int(try reader.int32())
        let stringSize = Int(try reader.int32())
        guard count > 0, count <= 20_000, stringSize >= 0, stringSize <= 8 * 1024 * 1024 else { throw UnityImportError.invalidFormat("Invalid type tree") }
        struct Flat {
            let level: UInt8
            let typeOffset: UInt32
            let nameOffset: UInt32
            let size: Int32
            let flags: UInt32
        }
        var flat: [Flat] = []
        for _ in 0..<count {
            _ = try reader.uint16()
            let level = try reader.uint8()
            guard level <= 32 else { throw UnityImportError.invalidFormat("Type tree is too deep") }
            _ = try reader.uint8()
            let typeOffset = try reader.uint32()
            let nameOffset = try reader.uint32()
            let size = try reader.int32()
            _ = try reader.int32()
            let flags = try reader.uint32()
            _ = try reader.uint64()
            flat.append(Flat(level: level, typeOffset: typeOffset, nameOffset: nameOffset, size: size, flags: flags))
        }
        let strings = try reader.bytes(stringSize)
        func string(_ offset: UInt32) throws -> String {
            if offset & 0x80000000 != 0 {
                guard let value = unityCommonStrings[offset & 0x7fffffff] else { throw UnityImportError.invalidFormat("Unknown common string") }
                return value
            }
            var source = BinaryReader(strings, order: reader.order)
            try source.seek(Int(offset))
            return try source.cString()
        }
        func build(_ index: inout Int) throws -> UnityTypeNode {
            let item = flat[index]
            index += 1
            var children: [UnityTypeNode] = []
            while index < flat.count, flat[index].level > item.level {
                guard flat[index].level == item.level + 1 else { throw UnityImportError.invalidFormat("Invalid type tree level") }
                children.append(try build(&index))
            }
            return UnityTypeNode(type: try string(item.typeOffset), name: try string(item.nameOffset), size: item.size, flags: item.flags, children: children)
        }
        var index = 0
        let root = try build(&index)
        guard index == flat.count else { throw UnityImportError.invalidFormat("Incomplete type tree") }
        let dependencyCount = Int(try reader.int32())
        guard dependencyCount >= 0, dependencyCount <= reader.remaining / 4 else { throw UnityImportError.invalidFormat("Invalid dependencies") }
        _ = try reader.bytes(dependencyCount * 4)
        return UnityType(classID: classID, root: root)
    }

    static func readValue(_ node: UnityTypeNode, _ reader: inout BinaryReader, depth: Int, budget: inout Int) throws -> UnityValue {
        guard depth <= 32, budget > 0 else { throw UnityImportError.invalidFormat("Value is too complex") }
        budget -= 1
        let value: UnityValue
        switch node.type {
        case "SInt8": value = .signed(Int64(try reader.int8()))
        case "UInt8", "char": value = .unsigned(UInt64(try reader.uint8()))
        case "short", "SInt16": value = .signed(Int64(try reader.int16()))
        case "unsigned short", "UInt16": value = .unsigned(UInt64(try reader.uint16()))
        case "int", "SInt32": value = .signed(Int64(try reader.int32()))
        case "unsigned int", "UInt32", "Type*": value = .unsigned(UInt64(try reader.uint32()))
        case "long long", "SInt64": value = .signed(try reader.int64())
        case "unsigned long long", "UInt64", "FileSize": value = .unsigned(try reader.uint64())
        case "float": value = .float(Double(try reader.float32()))
        case "double": value = .float(try reader.float64())
        case "bool": value = .bool(try reader.uint8() != 0)
        case "string": value = .string(try reader.alignedString())
        case "TypelessData":
            let count = Int(try reader.int32())
            guard count >= 0, count <= 64 * 1024 * 1024 else { throw UnityImportError.invalidFormat("Invalid data size") }
            value = .bytes(try reader.bytes(count))
        default:
            if let array = node.children.first, array.type == "Array", array.children.count == 2 {
                let count = Int(try reader.int32())
                guard count >= 0, count <= budget else { throw UnityImportError.invalidFormat("Invalid array size") }
                var values: [UnityValue] = []
                values.reserveCapacity(count)
                for _ in 0..<count { values.append(try readValue(array.children[1], &reader, depth: depth + 1, budget: &budget)) }
                value = .array(values)
            } else {
                var fields: [String: UnityValue] = [:]
                for child in node.children {
                    guard fields[child.name] == nil else { throw UnityImportError.invalidFormat("Duplicate field") }
                    fields[child.name] = try readValue(child, &reader, depth: depth + 1, budget: &budget)
                }
                value = .object(fields)
            }
        }
        if node.flags & 0x4000 != 0 { try reader.align(4) }
        return value
    }

    static func className(_ id: Int32) -> String {
        [1: "GameObject", 4: "Transform", 21: "Material", 28: "Texture2D", 43: "Mesh",
         74: "AnimationClip", 114: "MonoBehaviour", 115: "MonoScript", 137: "SkinnedMeshRenderer",
         142: "AssetBundle", 205: "LODGroup"][id] ?? "Class\(id)"
    }
}
