import Foundation
import simd
import Testing
@testable import MondayCore

@Test func sharedGeometryBoundsKeepDistinctNodeAndSkinTransforms() throws {
    let model = try boundsFixture()
    let rig = try CharacterRig(model: model)
    for frame in 0..<40 {
        rig.pose[1].rotation = Quaternion(angle: Float(frame) * 0.1, axis: Vector3(0, 0, 1))
        rig.pose[2].scale = Vector3(-1, 1 + Float(frame) * 0.04, 0.6)
        rig.pose[5].translation.y = 10 + Float(frame) * 0.13
        rig.pose[6].rotation = Quaternion(angle: Float(frame) * -0.08, axis: Vector3(1, 0, 0))
        rig.updateWorld()
        var reference = Bounds3()
        for primitive in model.primitives {
            for position in rig.positions(for: primitive) { reference.include(position) }
        }
        let actual = rig.bounds()
        #expect(actual.minimum == reference.minimum)
        #expect(actual.maximum == reference.maximum)
    }
}

private func boundsFixture() throws -> CharacterModel {
    let values: [Float] = [-1, 0, 0, 2, 0, 0, 0, 3, 1]
    let binary = values.withUnsafeBytes { Data($0) }
    let primitive: [String: Any] = ["attributes": ["POSITION": 0]]
    let document: [String: Any] = [
        "buffers": [["byteLength": binary.count]], "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": binary.count]],
        "accessors": [["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"]],
        "nodes": [["children": [1, 2, 3, 4, 5, 6]],
                  ["mesh": 0, "translation": [-4, 0, 0]], ["mesh": 0, "translation": [6, 0, 0]],
                  ["mesh": 0, "skin": 0], ["mesh": 0, "skin": 1],
                  ["translation": [0, 10, 0]], ["translation": [0, -10, 0]]],
        "meshes": [["primitives": [primitive, primitive, primitive]]],
        "skins": [["joints": [5]], ["joints": [6]]], "scenes": [["nodes": [0]]]
    ]
    var json = try JSONSerialization.data(withJSONObject: document)
    while !json.count.isMultiple(of: 4) { json.append(32) }
    var data = Data()
    func word(_ value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    word(0x46546c67); word(2); word(UInt32(28 + json.count + binary.count))
    word(UInt32(json.count)); word(0x4e4f534a); data.append(json)
    word(UInt32(binary.count)); word(0x004e4942); data.append(binary)
    return try CharacterModel(data: data)
}
