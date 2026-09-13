import Foundation

struct GLBDocument: Decodable {
    struct Buffer: Decodable { let byteLength: Int; let uri: String? }
    struct BufferView: Decodable { let buffer: Int; let byteOffset: Int?; let byteLength: Int; let byteStride: Int? }
    struct Accessor: Decodable {
        let bufferView: Int?
        let byteOffset: Int?
        let componentType: Int
        let count: Int
        let type: String
        let normalized: Bool?
    }
    struct Node: Decodable {
        let name: String?
        let children: [Int]?
        let translation: [Float]?
        let rotation: [Float]?
        let scale: [Float]?
        let matrix: [Float]?
        let mesh: Int?
        let skin: Int?
    }
    struct Mesh: Decodable {
        struct Extras: Decodable { let targetNames: [String]? }
        struct Primitive: Decodable {
            let attributes: [String: Int]
            let indices: Int?
            let material: Int?
            let targets: [[String: Int]]?
            let mode: Int?
        }
        let name: String?
        let primitives: [Primitive]
        let extras: Extras?
    }
    struct Skin: Decodable { let joints: [Int]; let inverseBindMatrices: Int? }
    struct Image: Decodable { let bufferView: Int?; let uri: String? }
    struct Texture: Decodable { let source: Int? }
    struct Material: Decodable {
        struct PBR: Decodable {
            struct TextureInfo: Decodable { let index: Int }
            let baseColorTexture: TextureInfo?
            let baseColorFactor: [Float]?
        }
        let name: String?
        let pbrMetallicRoughness: PBR?
        let alphaMode: MaterialAlphaMode?
        let alphaCutoff: Float?
    }
    struct Scene: Decodable { let nodes: [Int] }
    let buffers: [Buffer]
    let bufferViews: [BufferView]
    let accessors: [Accessor]
    let nodes: [Node]
    let meshes: [Mesh]
    let skins: [Skin]?
    let images: [Image]?
    let textures: [Texture]?
    let materials: [Material]?
    let scenes: [Scene]
    let scene: Int?
}

struct GLBContainer {
    let document: GLBDocument
    let binary: Data

    init(data: Data) throws {
        guard data.count >= 20, data.word(at: 0) == 0x46546C67, data.word(at: 4) == 2,
              data.word(at: 8) == data.count else { throw AssetError.invalid("GLB header") }
        var offset = 12
        var json: Data?
        var bin: Data?
        while offset + 8 <= data.count {
            let length = Int(data.word(at: offset))
            let kind = data.word(at: offset + 4)
            offset += 8
            guard length % 4 == 0, length <= data.count - offset else { throw AssetError.invalid("GLB chunk length") }
            let chunk = data.subdata(in: offset..<offset + length)
            if kind == 0x4E4F534A { json = chunk }
            if kind == 0x004E4942 { bin = chunk }
            offset += length
        }
        guard offset == data.count, let json, let bin else { throw AssetError.invalid("GLB chunks") }
        document = try JSONDecoder().decode(GLBDocument.self, from: json)
        guard document.buffers.count == 1, document.buffers[0].uri == nil,
              document.buffers[0].byteLength >= 0,
              document.buffers[0].byteLength <= bin.count else { throw AssetError.invalid("embedded GLB buffer") }
        binary = bin
    }

    func view(_ index: Int) throws -> Data {
        guard document.bufferViews.indices.contains(index) else { throw AssetError.invalid("buffer view index") }
        let view = document.bufferViews[index]
        let offset = view.byteOffset ?? 0
        guard view.buffer == 0, offset >= 0, view.byteLength >= 0,
              offset <= binary.count, view.byteLength <= binary.count - offset else { throw AssetError.invalid("buffer view bounds") }
        return binary.subdata(in: offset..<offset + view.byteLength)
    }

    func values(_ index: Int, components expected: Int) throws -> [Float] {
        guard document.accessors.indices.contains(index) else { throw AssetError.invalid("accessor index") }
        let accessor = document.accessors[index]
        let dimensions = ["SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16]
        guard dimensions[accessor.type] == expected, let viewIndex = accessor.bufferView,
              accessor.count >= 0, accessor.count < 10_000_000 else { throw AssetError.invalid("accessor shape") }
        let bytes = try view(viewIndex)
        guard let size = [5121: 1, 5123: 2, 5125: 4, 5126: 4][accessor.componentType] else {
            throw AssetError.invalid("unsupported accessor component type")
        }
        let packedSize = size * expected
        let stride = document.bufferViews[viewIndex].byteStride ?? packedSize
        let start = accessor.byteOffset ?? 0
        guard stride >= packedSize, stride <= bytes.count || accessor.count == 0, start >= 0, start <= bytes.count,
              accessor.count == 0 || (bytes.count - start >= packedSize
                  && accessor.count - 1 <= (bytes.count - start - packedSize) / stride) else {
            throw AssetError.invalid("accessor bounds")
        }
        return try bytes.withUnsafeBytes { raw in
            var values = [Float]()
            values.reserveCapacity(accessor.count * expected)
            for element in 0..<accessor.count {
                for component in 0..<expected {
                    let offset = start + element * stride + component * size
                    var value: Float
                    switch accessor.componentType {
                    case 5121: value = Float(raw.loadUnaligned(fromByteOffset: offset, as: UInt8.self))
                    case 5123: value = Float(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self)))
                    case 5125: value = Float(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
                    default: value = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
                    }
                    if accessor.normalized == true {
                        if accessor.componentType == 5121 { value /= 255 }
                        if accessor.componentType == 5123 { value /= 65535 }
                    }
                    guard value.isFinite else { throw AssetError.invalid("non-finite accessor value") }
                    values.append(value)
                }
            }
            return values
        }
    }
}

extension Data {
    func word(at offset: Int) -> UInt32 {
        withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }
}
