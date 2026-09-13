import Foundation
import simd

public struct MeshVertex: Sendable {
    public var position: SIMD4<Float>
    public var uv: SIMD4<Float>
    public var joints: SIMD4<UInt32>
    public var weights: SIMD4<Float>

    public init(position: SIMD4<Float>, uv: SIMD4<Float>, joints: SIMD4<UInt32> = .zero, weights: SIMD4<Float> = SIMD4(1, 0, 0, 0)) {
        self.position = position
        self.uv = uv
        self.joints = joints
        self.weights = weights
    }
}

public struct CharacterPrimitive: Sendable {
    public let name: String
    public let node: Int
    public let skin: Int?
    public let material: Int?
    public let vertices: [MeshVertex]
    public let indices: [UInt32]
    public let morphNames: [String]
    public let morphDeltas: [SIMD4<Float>]
}

public struct CharacterMaterial: Sendable {
    public let name: String
    public let image: Int?
    public let color: SIMD4<Float>
    public let alphaCutoff: Float
    public let alphaMode: MaterialAlphaMode
    public var blended: Bool { alphaMode == .blend }
}

public struct CharacterSkin: Sendable {
    public let joints: [Int]
    public let inverseBindMatrices: [Matrix4]
}

public struct CharacterNode: Sendable {
    public let name: String
    public let children: [Int]
    public let transform: Transform
}

public struct CharacterModel: Sendable {
    public let nodes: [CharacterNode]
    public let roots: [Int]
    public let skins: [CharacterSkin]
    public let primitives: [CharacterPrimitive]
    public let images: [Data]
    public let materials: [CharacterMaterial]

    public init(url: URL) throws { try self.init(data: Data(contentsOf: url)) }

    public init(data: Data) throws {
        let file = try GLBContainer(data: data)
        let document = file.document
        guard document.scenes.indices.contains(document.scene ?? 0) else { throw AssetError.invalid("default scene") }
        roots = document.scenes[document.scene ?? 0].nodes
        nodes = try document.nodes.map { node in
            let transform: Transform
            if let matrix = node.matrix {
                guard matrix.count == 16, matrix.allSatisfy(\.isFinite),
                      abs(simd_determinant(Self.matrix(matrix))) > 0.000000001 else {
                    throw AssetError.invalid("node matrix")
                }
                transform = Transform(matrix: Self.matrix(matrix))
            } else {
                let p = node.translation ?? [0, 0, 0], q = node.rotation ?? [0, 0, 0, 1], s = node.scale ?? [1, 1, 1]
                guard p.count == 3, q.count == 4, s.count == 3, (p + q + s).allSatisfy(\.isFinite),
                      q.reduce(Float.zero, { $0 + $1 * $1 }) > 0.000000001,
                      s.allSatisfy({ abs($0) > 0.000001 }) else { throw AssetError.invalid("node transform") }
                transform = Transform(translation: Vector3(p[0], p[1], p[2]), rotation: simd_normalize(Quaternion(vector: SIMD4(q[0], q[1], q[2], q[3]))), scale: Vector3(s[0], s[1], s[2]))
            }
            return CharacterNode(name: node.name ?? "", children: node.children ?? [], transform: transform)
        }
        skins = try (document.skins ?? []).map { skin in
            guard !skin.joints.isEmpty, Set(skin.joints).count == skin.joints.count,
                  skin.joints.allSatisfy(document.nodes.indices.contains) else { throw AssetError.invalid("skin joint index") }
            let matrices: [Matrix4]
            if let index = skin.inverseBindMatrices {
                let values = try file.values(index, components: 16)
                guard values.count == skin.joints.count * 16 else { throw AssetError.invalid("inverse bind matrix count") }
                matrices = stride(from: 0, to: values.count, by: 16).map { Self.matrix(Array(values[$0..<$0 + 16])) }
            } else { matrices = Array(repeating: matrix_identity_float4x4, count: skin.joints.count) }
            return CharacterSkin(joints: skin.joints, inverseBindMatrices: matrices)
        }
        images = try (document.images ?? []).map { image in
            guard let view = image.bufferView, image.uri == nil else { throw AssetError.invalid("external image") }
            return try file.view(view)
        }
        materials = try (document.materials ?? []).map { material in
            var image: Int?
            if let texture = material.pbrMetallicRoughness?.baseColorTexture?.index {
                guard let textures = document.textures, textures.indices.contains(texture),
                      let source = textures[texture].source, (document.images ?? []).indices.contains(source) else {
                    throw AssetError.invalid("material texture")
                }
                image = source
            }
            let color = material.pbrMetallicRoughness?.baseColorFactor ?? [1, 1, 1, 1]
            guard color.count == 4 else { throw AssetError.invalid("material color") }
            return CharacterMaterial(name: material.name ?? "", image: image, color: SIMD4(color[0], color[1], color[2], color[3]),
                                     alphaCutoff: material.alphaCutoff ?? 0.5, alphaMode: material.alphaMode ?? .opaque)
        }
        let loadedSkins = skins
        let loadedMaterials = materials
        var primitives: [CharacterPrimitive] = []
        var vertexStorage = ArrayStorageCache<MeshVertex>()
        var indexStorage = ArrayStorageCache<UInt32>()
        var morphStorage = ArrayStorageCache<SIMD4<Float>>()
        for (nodeIndex, node) in document.nodes.enumerated() {
            guard let meshIndex = node.mesh else { continue }
            guard document.meshes.indices.contains(meshIndex), node.skin.map({ loadedSkins.indices.contains($0) }) ?? true else {
                throw AssetError.invalid("mesh or skin reference")
            }
            let mesh = document.meshes[meshIndex]
            for primitive in mesh.primitives {
                guard (primitive.mode ?? 4) == 4, let positionIndex = primitive.attributes["POSITION"],
                      primitive.material.map({ loadedMaterials.indices.contains($0) }) ?? true else { throw AssetError.invalid("mesh primitive") }
                let positions = try file.values(positionIndex, components: 3)
                let count = positions.count / 3
                let uv = try primitive.attributes["TEXCOORD_0"].map { try file.values($0, components: 2) } ?? Array(repeating: 0, count: count * 2)
                let joints = try primitive.attributes["JOINTS_0"].map { try file.values($0, components: 4) } ?? Array(repeating: 0, count: count * 4)
                let weights = try primitive.attributes["WEIGHTS_0"].map { try file.values($0, components: 4) } ?? (0..<count).flatMap { _ in [Float(1), 0, 0, 0] }
                guard uv.count == count * 2, joints.count == count * 4, weights.count == count * 4 else { throw AssetError.invalid("vertex attribute count") }
                guard joints.allSatisfy({ $0 >= 0 && $0 < Float(UInt32.max) && $0.rounded(.down) == $0 }) else {
                    throw AssetError.invalid("vertex joint index")
                }
                if let skin = node.skin, joints.contains(where: { $0 < 0 || $0 >= Float(loadedSkins[skin].joints.count) }) {
                    throw AssetError.invalid("vertex joint index")
                }
                let vertices = (0..<count).map { i in
                    MeshVertex(position: SIMD4(positions[i * 3], positions[i * 3 + 1], positions[i * 3 + 2], 1),
                               uv: SIMD4(uv[i * 2], uv[i * 2 + 1], 0, 0),
                               joints: SIMD4(UInt32(joints[i * 4]), UInt32(joints[i * 4 + 1]), UInt32(joints[i * 4 + 2]), UInt32(joints[i * 4 + 3])),
                               weights: SIMD4(weights[i * 4], weights[i * 4 + 1], weights[i * 4 + 2], weights[i * 4 + 3]))
                }
                let rawIndices = try primitive.indices.map { try file.values($0, components: 1) } ?? (0..<count).map(Float.init)
                guard rawIndices.count % 3 == 0, rawIndices.allSatisfy({ $0 >= 0 && $0 < Float(count) && $0.rounded(.down) == $0 }) else { throw AssetError.invalid("triangle indices") }
                let names = mesh.extras?.targetNames ?? []
                guard names.count == (primitive.targets?.count ?? 0) else { throw AssetError.invalid("morph target names") }
                var deltas: [SIMD4<Float>] = []
                for target in primitive.targets ?? [] {
                    let values = try target["POSITION"].map { try file.values($0, components: 3) } ?? Array(repeating: 0, count: count * 3)
                    guard values.count == count * 3 else { throw AssetError.invalid("morph vertex count") }
                    deltas += (0..<count).map { SIMD4(values[$0 * 3], values[$0 * 3 + 1], values[$0 * 3 + 2], 0) }
                }
                primitives.append(CharacterPrimitive(name: mesh.name ?? "", node: nodeIndex, skin: node.skin, material: primitive.material,
                                                     vertices: vertexStorage.share(vertices), indices: indexStorage.share(rawIndices.map(UInt32.init)),
                                                     morphNames: names, morphDeltas: morphStorage.share(deltas)))
            }
        }
        self.primitives = primitives
        _ = try CharacterRig(model: self)
    }

    private static func matrix(_ v: [Float]) -> Matrix4 {
        Matrix4(columns: (SIMD4(v[0], v[1], v[2], v[3]), SIMD4(v[4], v[5], v[6], v[7]),
                          SIMD4(v[8], v[9], v[10], v[11]), SIMD4(v[12], v[13], v[14], v[15])))
    }
}
