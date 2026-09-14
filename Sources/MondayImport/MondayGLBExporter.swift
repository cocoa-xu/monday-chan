import Foundation

public typealias MondayTexturePNGProvider = (UnityAssetBundle, UnityValue) throws -> Data

public enum MondayGLBExporter {
    public static func export(body: UnityAssetBundle, hair: UnityAssetBundle?, texturePNG: @escaping MondayTexturePNGProvider) throws -> Data {
        let exporter = GLBExporter(texturePNG: texturePNG)
        try exporter.addBody(body)
        if let hair { try exporter.addHair(hair) }
        return try exporter.finish()
    }
}

private final class GLBExporter {
    private var gl: [String: Any] = [
        "accessors": [[String: Any]](), "meshes": [[String: Any]](), "nodes": [[String: Any]](),
        "skins": [[String: Any]](), "images": [[String: Any]](), "textures": [[String: Any]](),
        "materials": [[String: Any]](), "samplers": [["magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497]],
        "bufferViews": [[String: Any]]()
    ]
    private var binary = Data()
    private var imageCache: [Data: Int] = [:]
    private var textureCache: [String: Int] = [:]
    private var missingTextures = Set<String>()
    private var materialCache: [String: Int] = [:]
    private var bodyRoot = 0
    private var bodyHead: Int?
    private var bodyMeshNodes: [Int] = []
    private var hairRoot: Int?
    private var hairMeshNodes: [Int] = []
    private let texturePNG: MondayTexturePNGProvider

    init(texturePNG: @escaping MondayTexturePNGProvider) { self.texturePNG = texturePNG }

    func addBody(_ bundle: UnityAssetBundle) throws {
        let hierarchy = try addHierarchy(bundle)
        bodyRoot = hierarchy.root
        bodyHead = hierarchy.nodes.first { hierarchy.names[$0.key] == "jnt_C_head00_00" }?.value
        bodyMeshNodes = try addMeshes(bundle, nodes: hierarchy.nodes)
    }

    func addHair(_ bundle: UnityAssetBundle) throws {
        let hierarchy = try addHierarchy(bundle)
        hairRoot = hierarchy.root
        hairMeshNodes = try addMeshes(bundle, nodes: hierarchy.nodes)
    }

    func finish() throws -> Data {
        var nodes = self.nodes
        nodes[bodyRoot]["children"] = ((nodes[bodyRoot]["children"] as? [Int]) ?? []) + bodyMeshNodes
        if let hairRoot, let bodyHead {
            nodes[hairRoot]["translation"] = [0, 0, 0]
            nodes[hairRoot]["rotation"] = [0, 0, 0, 1]
            nodes[hairRoot]["scale"] = [1, 1, 1]
            nodes[hairRoot]["children"] = ((nodes[hairRoot]["children"] as? [Int]) ?? []) + hairMeshNodes
            nodes[bodyHead]["children"] = ((nodes[bodyHead]["children"] as? [Int]) ?? []) + [hairRoot]
        }
        let conversionRoot = nodes.count
        nodes.append(["name": "CharacterRoot", "scale": [-1, 1, 1], "children": [bodyRoot]])
        for index in nodes.indices where (nodes[index]["children"] as? [Int])?.isEmpty == true { nodes[index].removeValue(forKey: "children") }
        gl["nodes"] = nodes
        gl["scenes"] = [["nodes": [conversionRoot]]]
        gl["scene"] = 0
        gl["asset"] = ["version": "2.0", "generator": "Monday-chan native importer"]
        gl["buffers"] = [["byteLength": binary.count]]
        var json = try JSONSerialization.data(withJSONObject: gl, options: [.sortedKeys])
        json.append(Data(repeating: 0x20, count: (4 - json.count % 4) % 4))
        binary.append(Data(repeating: 0, count: (4 - binary.count % 4) % 4))
        var result = Data()
        result.appendLittle(UInt32(0x46546c67))
        result.appendLittle(UInt32(2))
        result.appendLittle(UInt32(12 + 8 + json.count + 8 + binary.count))
        result.appendLittle(UInt32(json.count))
        result.append(Data("JSON".utf8))
        result.append(json)
        result.appendLittle(UInt32(binary.count))
        result.append(Data([0x42, 0x49, 0x4e, 0]))
        result.append(binary)
        return result
    }

    private var nodes: [[String: Any]] {
        get { gl["nodes"] as! [[String: Any]] }
        set { gl["nodes"] = newValue }
    }

    private func addHierarchy(_ bundle: UnityAssetBundle) throws -> (root: Int, nodes: [Int64: Int], names: [Int64: String]) {
        var transforms: [Int64: UnityValue] = [:]
        var transformOrder: [Int64] = []
        var names: [Int64: String] = [:]
        for object in bundle.assets.objects {
            if object.className == "Transform" {
                guard transforms[object.pathID] == nil else { throw UnityExportError.invalid("duplicate transform ID") }
                transforms[object.pathID] = try bundle.assets.value(for: object)
                transformOrder.append(object.pathID)
            }
            if object.className == "GameObject" {
                let value = try bundle.assets.value(for: object)
                names[object.pathID] = try value.requiredString("m_Name")
            }
        }
        guard let rootID = try transformOrder.first(where: { try transforms[$0]!.required("m_Father").pathID() == 0 }) else {
            throw UnityExportError.missing("root transform")
        }
        var mapping: [Int64: Int] = [:]
        var nodeNames: [Int64: String] = [:]
        var visited = Set<Int64>()
        var stack = [rootID]
        var output = nodes
        while let pathID = stack.popLast() {
            guard visited.insert(pathID).inserted else { throw UnityExportError.invalid("transform hierarchy") }
            guard let transform = transforms[pathID] else { throw UnityExportError.missing("transform") }
            let gameObject = try transform.required("m_GameObject").pathID()
            let name = names[gameObject] ?? "?"
            mapping[pathID] = output.count
            nodeNames[pathID] = name
            output.append([
                "name": name,
                "translation": try vector(try transform.required("m_LocalPosition"), count: 3),
                "rotation": try vector(try transform.required("m_LocalRotation"), count: 4),
                "scale": try vector(try transform.required("m_LocalScale"), count: 3),
                "children": [Int]()
            ])
            stack.append(contentsOf: try transform.requiredArray("m_Children").map { try $0.pathID() })
        }
        for pathID in transformOrder {
            guard let transform = transforms[pathID] else { continue }
            let parent = try transform.required("m_Father").pathID()
            if let childNode = mapping[pathID], let parentNode = mapping[parent] {
                output[parentNode]["children"] = ((output[parentNode]["children"] as? [Int]) ?? []) + [childNode]
            }
        }
        nodes = output
        return (try mapping[rootID].unwrap("root node"), mapping, nodeNames)
    }

    private func addMeshes(_ bundle: UnityAssetBundle, nodes mapping: [Int64: Int]) throws -> [Int] {
        var objects: [Int64: UnityObjectInfo] = [:]
        for object in bundle.assets.objects {
            guard objects.updateValue(object, forKey: object.pathID) == nil else { throw UnityExportError.invalid("duplicate object ID") }
        }
        var result: [Int] = []
        for rendererInfo in bundle.assets.objects where rendererInfo.className == "SkinnedMeshRenderer" {
            let renderer = try bundle.assets.value(for: rendererInfo)
            let meshID = try renderer.required("m_Mesh").pathID()
            guard let meshInfo = objects[meshID] else { throw UnityExportError.missing("mesh") }
            let mesh = try bundle.assets.value(for: meshInfo)
            if try mesh.requiredString("m_Name").contains("LOD1") { continue }
            let bones = try renderer.requiredArray("m_Bones").map { try $0.pathID() }
            result.append(try addMesh(bundle, mesh: mesh, renderer: renderer, bones: bones, nodeMapping: mapping))
        }
        return result
    }

    private func addMesh(_ bundle: UnityAssetBundle, mesh: UnityValue, renderer: UnityValue,
                         bones: [Int64], nodeMapping: [Int64: Int]) throws -> Int {
        let vertexData = try mesh.required("m_VertexData")
        let data = try vertexData.requiredBytes("m_DataSize")
        let count = try vertexData.requiredInt("m_VertexCount")
        guard count > 0, count <= 10_000_000, count <= data.count / 40 else { throw UnityExportError.invalid("vertex count") }
        let channels = try vertexData.requiredArray("m_Channels")
        let stream1 = try channels.filter { try $0.requiredInt("stream") == 1 }
        let stream2 = try channels.filter { try $0.requiredInt("stream") == 2 }
        let stream1Layout = try stream1.map { (try $0.requiredInt("offset"), try $0.requiredInt("dimension"), try $0.requiredInt("format")) }
        guard stream1Layout.allSatisfy({ $0.0 >= 0 && $0.0 <= data.count && (0...4).contains($0.1) }) else {
            throw UnityExportError.invalid("vertex channel")
        }
        let stride1 = stream1Layout.map { $0.0 + $0.1 * ($0.2 == 1 ? 2 : 4) }.max() ?? 16
        guard channels.indices.contains(4) else { throw UnityExportError.invalid("UV channel") }
        let uvOffset = try channels[4].requiredInt("offset")
        let halfUV = try channels[4].requiredInt("format") == 1
        let base1 = (count * 40 + 15) & ~15
        let base2 = (base1 + count * stride1 + 15) & ~15
        guard uvOffset >= 0, uvOffset + (halfUV ? 4 : 8) <= stride1, base2 <= data.count else {
            throw UnityExportError.invalid("vertex streams")
        }
        let stride2 = count > 0 ? (data.count - base2) / count : 0
        guard stream2.isEmpty || stride2 > 0 else { throw UnityExportError.invalid("skin stream") }
        var positions: [Float] = [], normals: [Float] = [], uvs: [Float] = [], joints: [UInt16] = [], weights: [Float] = []
        for index in 0..<count {
            let base = index * 40
            positions += try (0..<3).map { try data.float32(at: base + $0 * 4) }
            normals += try (0..<3).map { try data.float32(at: base + 12 + $0 * 4) }
            let uvBase = base1 + index * stride1 + uvOffset
            let u: Float, v: Float
            if halfUV {
                u = Float(binary16: try data.uint16(at: uvBase))
                v = Float(binary16: try data.uint16(at: uvBase + 2))
            } else {
                u = try data.float32(at: uvBase); v = try data.float32(at: uvBase + 4)
            }
            uvs += [u, 1 - v]
            if stream2.isEmpty {
                joints += [0, 0, 0, 0]; weights += [1, 0, 0, 0]
            } else {
                let joint32 = try stream2.last!.requiredInt("format") == 10
                let dimension = try stream2[0].requiredInt("dimension")
                let influence = dimension == 2 ? 2 : dimension == 1 ? 1 : 4
                let jointOffset = influence == 2 ? 8 : influence == 4 ? 16 : 0
                let weightCount = influence
                guard stride2 >= jointOffset + influence * (joint32 ? 4 : 2),
                      influence == 1 || stride2 >= influence * 4 else { throw UnityExportError.invalid("skin stream") }
                for component in 0..<4 {
                    if component < influence {
                        let offset = base2 + index * stride2 + jointOffset + component * (joint32 ? 4 : 2)
                        let value = joint32 ? try data.uint32(at: offset) : UInt32(try data.uint16(at: offset))
                        guard value <= UInt16.max else { throw UnityExportError.invalid("joint index") }
                        joints.append(UInt16(value))
                        weights.append(influence == 1 ? 1 : try data.float32(at: base2 + index * stride2 + component * 4))
                    } else { joints.append(0); weights.append(0) }
                }
                guard weightCount > 0 else { throw UnityExportError.invalid("weights") }
            }
        }
        guard [positions, normals, uvs, weights].allSatisfy({ $0.allSatisfy(\.isFinite) }) else { throw UnityExportError.invalid("vertex values") }
        let morphs = try addMorphs(try mesh.required("m_Shapes"), vertexCount: count)
        let indexBytes = try mesh.requiredBytes("m_IndexBuffer")
        let index32 = try mesh.requiredInt("m_IndexFormat") != 0
        let allIndices = try stride(from: 0, to: indexBytes.count, by: index32 ? 4 : 2).map {
            index32 ? try indexBytes.uint32(at: $0) : UInt32(try indexBytes.uint16(at: $0))
        }
        let materials = try renderer.requiredArray("m_Materials").map { try $0.pathID() }
        var primitives: [[String: Any]] = []
        var seen = Set<Triangle>()
        for (submeshIndex, submesh) in try mesh.requiredArray("m_SubMeshes").enumerated() {
            let first = try submesh.requiredInt("firstByte") / (index32 ? 4 : 2)
            let indexCount = try submesh.requiredInt("indexCount")
            let baseVertex = submesh["baseVertex"] == nil ? 0 : try submesh.requiredInt("baseVertex")
            guard first >= 0, first <= allIndices.count, indexCount >= 0, indexCount <= allIndices.count - first,
                  indexCount.isMultiple(of: 3), baseVertex >= 0, baseVertex < count else { throw UnityExportError.invalid("submesh") }
            let candidate = try allIndices[first..<(first + indexCount)].map {
                let value = Int64($0) + Int64(baseVertex)
                guard value >= 0, value < Int64(count) else { throw UnityExportError.invalid("vertex index") }
                return UInt32(value)
            }
            var triangles = Set<Triangle>()
            for offset in stride(from: 0, to: candidate.count - candidate.count % 3, by: 3) {
                triangles.insert(Triangle(candidate[offset], candidate[offset + 1], candidate[offset + 2]))
            }
            if triangles.isSubset(of: seen) { continue }
            seen.formUnion(triangles)
            let indices = candidate
            let attributes = try addAttributes(positions: positions, normals: normals, uvs: uvs, joints: joints, weights: weights)
            let material = try addMaterial(bundle, pathID: submeshIndex < materials.count ? materials[submeshIndex] : 0)
            let groups: [([UInt32], Int)]
            if try mesh.requiredString("m_Name") == "Geo_Iris_LOD0" {
                var normal: [UInt32] = [], effect: [UInt32] = []
                for offset in stride(from: 0, to: indices.count, by: 3) {
                    let triangle = Array(indices[offset..<(offset + 3)])
                    if triangle.allSatisfy({ uvs[Int($0) * 2 + 1] >= 0.5 }) {
                        normal.append(contentsOf: triangle)
                    } else {
                        effect.append(contentsOf: triangle)
                    }
                }
                groups = [(normal, material), (effect, try addIrisEffect(from: material))]
            } else { groups = [(indices, material)] }
            for (group, groupMaterial) in groups where !group.isEmpty {
                var primitive: [String: Any] = ["attributes": attributes, "indices": addIndices(group), "material": groupMaterial]
                if !morphs.targets.isEmpty { primitive["targets"] = morphs.targets }
                primitives.append(primitive)
            }
        }
        let skin = try addSkin(mesh: mesh, bones: bones, nodes: nodeMapping)
        var meshJSON: [String: Any] = ["name": try mesh.requiredString("m_Name"), "primitives": primitives]
        if !morphs.targets.isEmpty {
            meshJSON["extras"] = ["targetNames": morphs.names]
            meshJSON["weights"] = try renderer.requiredArray("m_BlendShapeWeights").map { ($0.number ?? 0) / 100 }
        }
        var meshes = gl["meshes"] as! [[String: Any]]
        let meshIndex = meshes.count
        meshes.append(meshJSON)
        gl["meshes"] = meshes
        var nodes = self.nodes
        let nodeIndex = nodes.count
        var node: [String: Any] = ["name": "mesh_" + (try mesh.requiredString("m_Name")), "mesh": meshIndex]
        if let skin { node["skin"] = skin }
        nodes.append(node)
        self.nodes = nodes
        return nodeIndex
    }

    private func addAttributes(positions: [Float], normals: [Float], uvs: [Float], joints: [UInt16], weights: [Float]) throws -> [String: Int] {
        let position = addAccessor(data: Data(floats: positions), component: 5126, count: positions.count / 3, type: "VEC3", target: 34962)
        var accessors = gl["accessors"] as! [[String: Any]]
        accessors[position]["min"] = (0..<3).map { axis in positions.dropFirst(axis).stride(by: 3).min()! }
        accessors[position]["max"] = (0..<3).map { axis in positions.dropFirst(axis).stride(by: 3).max()! }
        gl["accessors"] = accessors
        return ["POSITION": position,
                "NORMAL": addAccessor(data: Data(floats: normals), component: 5126, count: normals.count / 3, type: "VEC3", target: 34962),
                "TEXCOORD_0": addAccessor(data: Data(floats: uvs), component: 5126, count: uvs.count / 2, type: "VEC2", target: 34962),
                "JOINTS_0": addAccessor(data: Data(uint16s: joints), component: 5123, count: joints.count / 4, type: "VEC4", target: 34962),
                "WEIGHTS_0": addAccessor(data: Data(floats: weights), component: 5126, count: weights.count / 4, type: "VEC4", target: 34962)]
    }

    private func addMorphs(_ shapes: UnityValue, vertexCount: Int) throws -> (targets: [[String: Int]], names: [String]) {
        guard let channels = shapes["channels"]?.array, let frames = shapes["shapes"]?.array,
              let vertices = shapes["vertices"]?.array, let fullWeights = shapes["fullWeights"]?.array else { return ([], []) }
        var targets: [[String: Int]] = [], names: [String] = []
        for channel in channels {
            guard try channel.requiredInt("frameCount") == 1 else { throw UnityExportError.invalid("multi-frame blend shape") }
            let frameIndex = try channel.requiredInt("frameIndex")
            guard frames.indices.contains(frameIndex), fullWeights.indices.contains(frameIndex), let weight = fullWeights[frameIndex].number, weight.isFinite, weight > 0 else {
                throw UnityExportError.invalid("blend shape frame")
            }
            let frame = frames[frameIndex]
            let first = try frame.requiredInt("firstVertex")
            let count = try frame.requiredInt("vertexCount")
            guard first >= 0, first <= vertices.count, count >= 0, count <= vertices.count - first else { throw UnityExportError.invalid("blend vertices") }
            var target: [String: Int] = [:]
            for (semantic, field) in [("POSITION", "vertex"), ("NORMAL", "normal")] {
                if semantic == "NORMAL", frame["hasNormals"] != .bool(true) { continue }
                var values = [Float](repeating: 0, count: vertexCount * 3)
                for vertex in vertices[first..<(first + count)] {
                    let index = try vertex.requiredInt("index")
                    guard index >= 0, index < vertexCount else { throw UnityExportError.invalid("morph index") }
                    let delta = try vector(try vertex.required(field), count: 3).map { Float($0 * 100 / weight) }
                    values.replaceSubrange(index * 3..<(index * 3 + 3), with: delta)
                }
                let accessor = addAccessor(data: Data(floats: values), component: 5126, count: vertexCount, type: "VEC3", target: 34962)
                if semantic == "POSITION" {
                    var accessors = gl["accessors"] as! [[String: Any]]
                    accessors[accessor]["min"] = (0..<3).map { values.dropFirst($0).stride(by: 3).min()! }
                    accessors[accessor]["max"] = (0..<3).map { values.dropFirst($0).stride(by: 3).max()! }
                    gl["accessors"] = accessors
                }
                target[semantic] = accessor
            }
            targets.append(target)
            names.append(try channel.requiredString("name"))
        }
        return (targets, names)
    }

    private func addSkin(mesh: UnityValue, bones: [Int64], nodes: [Int64: Int]) throws -> Int? {
        guard !bones.isEmpty, let poses = mesh["m_BindPose"]?.array, !poses.isEmpty else { return nil }
        guard poses.count == bones.count else { throw UnityExportError.invalid("skin bind poses") }
        var values: [Float] = []
        for pose in poses {
            for column in 0..<4 { for row in 0..<4 { values.append(Float(try pose.requiredNumber("e\(row)\(column)"))) } }
        }
        let accessor = addAccessor(data: Data(floats: values), component: 5126, count: poses.count, type: "MAT4", target: nil)
        let joints = try bones.map { try nodes[$0].unwrap("skin joint") }
        var skins = gl["skins"] as! [[String: Any]]
        let index = skins.count
        skins.append(["joints": joints, "inverseBindMatrices": accessor])
        gl["skins"] = skins
        return index
    }

    private func addMaterial(_ bundle: UnityAssetBundle, pathID: Int64) throws -> Int {
        guard pathID != 0, let info = bundle.assets.object(pathID: pathID), info.className == "Material" else { return addUntexturedMaterial() }
        let material = try bundle.assets.value(for: info)
        let environments = material["m_SavedProperties"]?["m_TexEnvs"]?.array ?? []
        var textureID: Int64?
        for environment in environments {
            if let pair = environment.array, pair.count == 2, pair[0].string == "_BaseMap" {
                textureID = try pair[1].required("m_Texture").pathID()
            } else if environment["first"]?.string == "_BaseMap", let value = environment["second"] {
                textureID = try value.required("m_Texture").pathID()
            }
        }
        guard let textureID, let texture = try addTexture(bundle, pathID: textureID) else { return addUntexturedMaterial() }
        let key = "\(pathID)-\(texture)"
        if let cached = materialCache[key] { return cached }
        var json: [String: Any] = ["name": try material.requiredString("m_Name"),
            "pbrMetallicRoughness": ["baseColorTexture": ["index": texture], "metallicFactor": 0, "roughnessFactor": 1],
            "doubleSided": true]
        if material["m_ValidKeywords"]?.array?.contains(where: { $0.string == "_ALPHATEST_ON" }) == true {
            json["alphaMode"] = "MASK"; json["alphaCutoff"] = 0.5
        }
        var materials = gl["materials"] as! [[String: Any]]
        let index = materials.count
        materials.append(json); gl["materials"] = materials; materialCache[key] = index
        return index
    }

    private func addUntexturedMaterial() -> Int {
        var materials = gl["materials"] as! [[String: Any]]
        let index = materials.count
        materials.append(["name": "Untextured surface", "pbrMetallicRoughness": ["metallicFactor": 0, "roughnessFactor": 1], "doubleSided": true])
        gl["materials"] = materials
        return index
    }

    private func addIrisEffect(from material: Int) throws -> Int {
        var materials = gl["materials"] as! [[String: Any]]
        guard materials.indices.contains(material) else { throw UnityExportError.invalid("iris material") }
        var effect = materials[material]
        effect["name"] = "Iris effects"; effect["alphaMode"] = "BLEND"; effect.removeValue(forKey: "alphaCutoff")
        if var pbr = effect["pbrMetallicRoughness"] as? [String: Any] { pbr["baseColorFactor"] = [1, 1, 1, 0]; effect["pbrMetallicRoughness"] = pbr }
        let index = materials.count; materials.append(effect); gl["materials"] = materials; return index
    }

    private func addTexture(_ bundle: UnityAssetBundle, pathID: Int64) throws -> Int? {
        let key = String(pathID)
        if let cached = textureCache[key] { return cached }
        if missingTextures.contains(key) { return nil }
        guard let info = bundle.assets.object(pathID: pathID), info.className == "Texture2D" else { missingTextures.insert(key); return nil }
        let value = try bundle.assets.value(for: info)
        let png = try texturePNG(bundle, value)
        let image: Int
        if let cached = imageCache[png] { image = cached }
        else {
            image = (gl["images"] as! [[String: Any]]).count
            let view = addBufferView(png, target: nil)
            var images = gl["images"] as! [[String: Any]]; images.append(["bufferView": view, "mimeType": "image/png"]); gl["images"] = images
            imageCache[png] = image
        }
        var textures = gl["textures"] as! [[String: Any]]
        let index = textures.count
        textures.append(["name": (try? value.requiredString("m_Name")) ?? "Texture", "source": image, "sampler": 0])
        gl["textures"] = textures; textureCache[key] = index; return index
    }

    private func addIndices(_ values: [UInt32]) -> Int {
        if values.max() ?? 0 > UInt16.max { return addAccessor(data: Data(uint32s: values), component: 5125, count: values.count, type: "SCALAR", target: 34963) }
        return addAccessor(data: Data(uint16s: values.map(UInt16.init)), component: 5123, count: values.count, type: "SCALAR", target: 34963)
    }

    private func addAccessor(data: Data, component: Int, count: Int, type: String, target: Int?) -> Int {
        let view = addBufferView(data, target: target)
        var accessors = gl["accessors"] as! [[String: Any]]
        let index = accessors.count
        accessors.append(["bufferView": view, "componentType": component, "count": count, "type": type])
        gl["accessors"] = accessors
        return index
    }

    private func addBufferView(_ data: Data, target: Int?) -> Int {
        binary.append(Data(repeating: 0, count: (4 - binary.count % 4) % 4))
        let offset = binary.count; binary.append(data)
        var view: [String: Any] = ["buffer": 0, "byteOffset": offset, "byteLength": data.count]
        if let target { view["target"] = target }
        var views = gl["bufferViews"] as! [[String: Any]]
        let index = views.count; views.append(view); gl["bufferViews"] = views; return index
    }

    private func vector(_ value: UnityValue, count: Int) throws -> [Double] {
        let keys = ["x", "y", "z", "w"]
        return try (0..<count).map { try value.requiredNumber(keys[$0]) }
    }

}

private struct Triangle: Hashable {
    let a: UInt32, b: UInt32, c: UInt32
    init(_ a: UInt32, _ b: UInt32, _ c: UInt32) { self.a = a; self.b = b; self.c = c }
}

private extension Optional {
    func unwrap(_ name: String) throws -> Wrapped {
        guard let self else { throw UnityExportError.missing(name) }
        return self
    }
}

private extension Data {
    init(floats: [Float]) { self.init(); for value in floats { appendLittle(value.bitPattern) } }
    init(uint16s: [UInt16]) { self.init(); for value in uint16s { appendLittle(value) } }
    init(uint32s: [UInt32]) { self.init(); for value in uint32s { appendLittle(value) } }
    mutating func appendLittle<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}

private extension Collection {
    func stride(by step: Int) -> [Element] {
        var result: [Element] = []
        var index = startIndex
        while index != endIndex { result.append(self[index]); index = self.index(index, offsetBy: step, limitedBy: endIndex) ?? endIndex }
        return result
    }
}
