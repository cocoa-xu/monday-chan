import simd

public final class CharacterRig {
    public let model: CharacterModel
    public let parents: [Int?]
    public let order: [Int]
    public private(set) var rest: [Transform]
    public var pose: [Transform]
    public private(set) var world: [Matrix4]
    private let names: [String: Int]

    public init(model: CharacterModel) throws {
        self.model = model
        var parents = [Int?](repeating: nil, count: model.nodes.count)
        for (index, node) in model.nodes.enumerated() {
            for child in node.children {
                guard model.nodes.indices.contains(child), parents[child] == nil else { throw AssetError.invalid("node hierarchy") }
                parents[child] = index
            }
        }
        var order: [Int] = [], visiting: Set<Int> = [], visited: Set<Int> = []
        func visit(_ index: Int) throws {
            guard model.nodes.indices.contains(index), !visiting.contains(index), !visited.contains(index) else {
                throw AssetError.invalid("cyclic or repeated scene node")
            }
            visiting.insert(index)
            order.append(index)
            for child in model.nodes[index].children { try visit(child) }
            visiting.remove(index)
            visited.insert(index)
        }
        for root in model.roots { try visit(root) }
        guard model.skins.allSatisfy({ $0.joints.allSatisfy(visited.contains) }) else { throw AssetError.invalid("unreachable skin joints") }
        self.parents = parents
        self.order = order
        names = Dictionary(model.nodes.enumerated().map { ($0.element.name, $0.offset) }, uniquingKeysWith: { first, _ in first })
        pose = model.nodes.map(\.transform)
        rest = pose
        world = Array(repeating: matrix_identity_float4x4, count: model.nodes.count)
        let hairSkins = Set(model.primitives.filter { $0.name.contains("Hair") }.compactMap(\.skin))
        for index in hairSkins {
            let skin = model.skins[index]
            let inverses = Dictionary(uniqueKeysWithValues: zip(skin.joints, skin.inverseBindMatrices))
            for (joint, inverse) in zip(skin.joints, skin.inverseBindMatrices) {
                if let parent = parents[joint], let parentInverse = inverses[parent] {
                    pose[joint] = Transform(matrix: parentInverse * simd_inverse(inverse))
                }
            }
        }
        rest = pose
        updateWorld()
    }

    public func node(_ name: String) -> Int? { names[name] }
    public func reset() { pose = rest; updateWorld() }

    public func updateWorld() {
        for index in order { world[index] = (parents[index].map { world[$0] } ?? matrix_identity_float4x4) * pose[index].matrix }
    }

    public func palette(for skin: Int) -> [Matrix4] {
        let skin = model.skins[skin]
        return zip(skin.joints, skin.inverseBindMatrices).map { world[$0.0] * $0.1 }
    }

    public func positions(for primitive: CharacterPrimitive) -> [Vector3] {
        guard let skin = primitive.skin else { return primitive.vertices.map { world[primitive.node].point($0.position.xyz) } }
        let matrices = palette(for: skin)
        return primitive.vertices.map { vertex in
            var p = SIMD4<Float>.zero
            for i in 0..<4 { p += matrices[Int(vertex.joints[i])] * vertex.position * vertex.weights[i] }
            return p.xyz
        }
    }

    public func bounds() -> Bounds3 {
        var bounds = Bounds3()
        for primitive in model.primitives {
            for position in positions(for: primitive) { bounds.include(position) }
        }
        return bounds
    }
}
