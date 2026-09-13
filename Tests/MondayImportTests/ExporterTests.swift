import Foundation
import Testing
@testable import MondayImport

@Suite(.serialized)
struct ExporterTests {
    @Test
    func integerConversionRejectsUnrepresentableDouble() {
        let value = UnityValue.object(["value": .float(9_223_372_036_854_775_808)])
        #expect(throws: UnityExportError.self) { try value.requiredInt("value") }
    }

    @Test(.enabled(if: exporterFixturesAvailable))
    func motionExportsMatchPreparedSamples() throws {
        for (source, identifier) in [("A34516", "idle01_typ000_lp_bdy00"), ("A34600", "run00_typ000_lp_bdy00")] {
            let bundle = try UnityAssetBundle(data: try Data(contentsOf: dataRoot.appending(path: "source/\(source)")))
            let actual = try MondayMotionExporter.export(bundle: bundle, identifier: identifier)
            let expected = try Data(contentsOf: dataRoot.appending(path: "motions/\(identifier).json"))
            let actualObject = try #require(JSONSerialization.jsonObject(with: actual) as? [String: Any])
            let expectedObject = try #require(JSONSerialization.jsonObject(with: expected) as? [String: Any])
            for key in ["id", "name", "label", "short", "file"] {
                #expect(actualObject[key] as? String == expectedObject[key] as? String)
            }
            #expect(actualObject["loop"] as? Bool == expectedObject["loop"] as? Bool)
            #expect(actualObject["duration"] as? Double == expectedObject["duration"] as? Double)
            #expect(actualObject["fps"] as? Double == expectedObject["fps"] as? Double)
            let actualFrames = try #require(actualObject["frames"] as? [[Double]])
            let expectedFrames = try #require(expectedObject["frames"] as? [[Double]])
            #expect(actualFrames.count == expectedFrames.count)
            var differences = 0
            var firstDifference: String?
            for index in actualFrames.indices where expectedFrames.indices.contains(index) {
                guard actualFrames[index].count == expectedFrames[index].count else { differences += 1; continue }
                for (column, values) in zip(actualFrames[index], expectedFrames[index]).enumerated() where values.0 != values.1 {
                    differences += 1
                    if firstDifference == nil { firstDifference = "frame \(index), attribute \(column + 7): \(values.0) != \(values.1)" }
                }
            }
            #expect(differences == 0, "\(identifier) differs at \(differences) samples; \(firstDifference ?? "unknown")")
        }
    }

    @Test(.enabled(if: exporterFixturesAvailable))
    func modelExportsEquivalentGeometryAndRig() throws {
        let body = try UnityAssetBundle(data: try Data(contentsOf: dataRoot.appending(path: "source/A33921")), headerKey: "mdl_chr_drs_06002-nrml-0058-00_body")
        let hair = try UnityAssetBundle(data: try Data(contentsOf: dataRoot.appending(path: "source/A33922")), headerKey: "mdl_chr_drs_06002-nrml-0058-00_hair")
        let actual = try MondayGLBExporter.export(body: body, hair: hair) { _, texture in
            Data((try texture.requiredString("m_Name")).utf8)
        }
        let expected = try Data(contentsOf: dataRoot.appending(path: "models/06002.glb"))
        let actualGLB = try GLB(actual)
        let expectedGLB = try GLB(expected)
        for key in ["nodes", "meshes", "skins", "accessors", "materials"] {
            #expect((actualGLB.json[key] as? NSArray)?.count == (expectedGLB.json[key] as? NSArray)?.count)
        }
        let actualAccessors = try #require(actualGLB.json["accessors"] as? [[String: Any]])
        let expectedAccessors = try #require(expectedGLB.json["accessors"] as? [[String: Any]])
        #expect(actualAccessors.map { $0["count"] as? Int } == expectedAccessors.map { $0["count"] as? Int })
        #expect(actualAccessors.map { $0["componentType"] as? Int } == expectedAccessors.map { $0["componentType"] as? Int })
        #expect(actualAccessors.map { $0["type"] as? String } == expectedAccessors.map { $0["type"] as? String })
        for index in actualAccessors.indices {
            #expect(try actualGLB.accessorData(index) == expectedGLB.accessorData(index), "Accessor \(index) differs")
        }
        let actualNodes = try #require(actualGLB.json["nodes"] as? [[String: Any]])
        let expectedNodes = try #require(expectedGLB.json["nodes"] as? [[String: Any]])
        #expect(actualNodes.compactMap { $0["name"] as? String } == expectedNodes.compactMap { $0["name"] as? String })
        for index in actualNodes.indices {
            for key in ["translation", "rotation", "scale"] {
                let actualValues = actualNodes[index][key] as? [Double]
                let expectedValues = expectedNodes[index][key] as? [Double]
                #expect(actualValues?.count == expectedValues?.count)
                #expect(zip(actualValues ?? [], expectedValues ?? []).allSatisfy { abs($0 - $1) <= 1e-15 }, "Node \(index) \(key) differs")
            }
            for key in ["children", "mesh", "skin"] {
                #expect((actualNodes[index][key] as? NSObject) == (expectedNodes[index][key] as? NSObject), "Node \(index) \(key) differs")
            }
        }
        #expect((actualGLB.json["skins"] as? NSObject) == (expectedGLB.json["skins"] as? NSObject))
        #expect((actualGLB.json["materials"] as? NSObject) == (expectedGLB.json["materials"] as? NSObject))
    }

    private var dataRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "data")
    }


}

private struct GLB {
    let json: [String: Any]
    let binary: Data

    init(_ data: Data) throws {
        guard data.count >= 20, data.prefix(4) == Data([0x67, 0x6c, 0x54, 0x46]) else { throw GLBError.invalid }
        let length = Int(data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self)) })
        guard length >= 2, 20 + length <= data.count else { throw GLBError.invalid }
        json = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<(20 + length))) as? [String: Any] ?? [:]
        let binaryHeader = 20 + length
        guard binaryHeader + 8 <= data.count else { throw GLBError.invalid }
        let binaryLength = Int(data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: binaryHeader, as: UInt32.self)) })
        guard binaryHeader + 8 + binaryLength <= data.count else { throw GLBError.invalid }
        binary = data.subdata(in: binaryHeader + 8..<(binaryHeader + 8 + binaryLength))
    }

    func accessorData(_ index: Int) throws -> Data {
        guard let accessors = json["accessors"] as? [[String: Any]], accessors.indices.contains(index),
              let viewIndex = accessors[index]["bufferView"] as? Int,
              let views = json["bufferViews"] as? [[String: Any]], views.indices.contains(viewIndex),
              let offset = views[viewIndex]["byteOffset"] as? Int,
              let length = views[viewIndex]["byteLength"] as? Int,
              offset >= 0, length >= 0, offset <= binary.count - length else { throw GLBError.invalid }
        return binary.subdata(in: offset..<(offset + length))
    }
}

private enum GLBError: Error { case invalid }

private let exporterFixturesAvailable: Bool = {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "data")
    return ["source/A33921", "source/A33922", "source/A34516", "source/A34600", "models/06002.glb",
            "motions/idle01_typ000_lp_bdy00.json", "motions/run00_typ000_lp_bdy00.json"]
        .allSatisfy { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
}()
