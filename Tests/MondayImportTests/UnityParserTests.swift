import Foundation
@testable import MondayImport
import XCTest

final class UnityParserTests: XCTestCase {
    func testLZ4LiteralAndOverlappingMatch() throws {
        let input = Data([0x44, 0x61, 0x62, 0x63, 0x64, 0x04, 0x00])
        XCTAssertEqual(try LZ4.decode(input, size: 12), Data("abcdabcdabcd".utf8))
    }

    func testLZ4RejectsInvalidDistance() {
        XCTAssertThrowsError(try LZ4.decode(Data([0x00, 0x01, 0x00]), size: 4))
        XCTAssertThrowsError(try LZ4.decode(Data(), size: -1))
        XCTAssertThrowsError(try LZ4.decode(Data(), size: 128 * 1024 * 1024 + 1))
    }

    func testReaderRejectsPastEndAndAlignPastEnd() throws {
        var reader = BinaryReader(Data([1, 2, 3]))
        XCTAssertEqual(try reader.uint16(), 0x0102)
        XCTAssertThrowsError(try reader.uint16())
        XCTAssertThrowsError(try reader.align(4))
    }

    func testArchiveRejectsTruncatedHeadersAndUnsafeNames() {
        XCTAssertThrowsError(try UnityFSArchive(data: Data("UnityFS".utf8)))
        for name in ["", "/absolute", "../outside", "folder/../outside", "folder//file", "folder\\file"] {
            XCTAssertFalse(UnityFSArchive.validEntryName(name))
        }
        XCTAssertTrue(UnityFSArchive.validEntryName("CAB-file.resS"))
    }

    func testValueReaderRejectsDuplicateFieldsAndOversizedArrays() throws {
        let scalar = UnityTypeNode(type: "UInt8", name: "same", size: 1, flags: 0, children: [])
        let duplicate = UnityTypeNode(type: "Root", name: "Base", size: 2, flags: 0, children: [scalar, scalar])
        var duplicateReader = BinaryReader(Data([1, 2]), order: .little)
        var duplicateBudget = 10
        XCTAssertThrowsError(try UnitySerializedFile.readValue(duplicate, &duplicateReader, depth: 0, budget: &duplicateBudget))

        let size = UnityTypeNode(type: "int", name: "size", size: 4, flags: 0, children: [])
        let data = UnityTypeNode(type: "UInt8", name: "data", size: 1, flags: 0, children: [])
        let array = UnityTypeNode(type: "Array", name: "Array", size: -1, flags: 0, children: [size, data])
        let vector = UnityTypeNode(type: "vector", name: "values", size: -1, flags: 0, children: [array])
        var arrayReader = BinaryReader(Data([0xff, 0xff, 0xff, 0x7f]), order: .little)
        var arrayBudget = 100
        XCTAssertThrowsError(try UnitySerializedFile.readValue(vector, &arrayReader, depth: 0, budget: &arrayBudget))
    }

    func testSerializedFileRejectsTruncatedInput() {
        XCTAssertThrowsError(try UnitySerializedFile(data: Data(repeating: 0, count: 64)))
    }

    func testRealBundlesDecodeEveryObject() throws {
        guard let fixtureRoot = ProcessInfo.processInfo.environment["MONDAY_IMPORT_FIXTURES"] else {
            throw XCTSkip("Set MONDAY_IMPORT_FIXTURES to run real-bundle tests")
        }
        let root = fixtureRoot.appending("/")
        let fixtures: [(String, String?, Int, String, String)] = [
            ("A33921", "mdl_chr_drs_06002-nrml-0058-00_body", 443, "Mesh", "Geo_Body_LOD0"),
            ("A33922", "mdl_chr_drs_06002-nrml-0058-00_hair", 172, "Mesh", "Geo_Hair_LOD0"),
            ("A34516", nil, 9, "AnimationClip", "mot_general_chr_drs_idle01_typ000_lp_bdy00"),
            ("A34600", nil, 9, "AnimationClip", "mot_general_chr_drs_run00_typ000_lp_bdy00"),
        ]
        for fixture in fixtures {
            let data = try Data(contentsOf: URL(fileURLWithPath: root + fixture.0))
            let bundle = try UnityAssetBundle(data: data, headerKey: fixture.1)
            XCTAssertEqual(bundle.assets.objects.count, fixture.2)
            let values = try bundle.assets.objects.map { ($0, try bundle.assets.value(for: $0)) }
            XCTAssertTrue(values.contains { object, value in
                object.className == fixture.3 && value["m_Name"]?.string == fixture.4
            })
            if fixture.0 == "A33921" || fixture.0 == "A33922" {
                let resource = try XCTUnwrap(bundle.archive.entries.first { $0.name.hasSuffix(".resS") })
                XCTAssertFalse(try bundle.externalResourceData(named: (resource.name as NSString).lastPathComponent).isEmpty)
            }
        }
    }
}
