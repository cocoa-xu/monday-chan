import Foundation

public enum AssetError: Error, LocalizedError, Equatable {
    case invalid(String)
    case missing(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message): "Invalid asset: \(message)"
        case .missing(let message): "Missing asset: \(message)"
        }
    }
}

public struct CharacterDescriptor: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let group: String
    public let outfit: String
    public let model: String
    public let mouths: String
}

public struct CharacterCatalog: Decodable, Sendable {
    public let characters: [CharacterDescriptor]
}

public struct MouthCatalog: Decodable, Sendable {
    public struct Size: Decodable, Sendable {
        public let x: Float
        public let y: Float
        public let z: Float
    }
    public let cells: [String: Int]
    public let projector_size: Size
}

public struct AssetLibrary: Sendable {
    public let root: URL
    public let catalog: CharacterCatalog

    public init(root: URL) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        let catalogURL = self.root.appendingPathComponent("characters.json")
        catalog = FileManager.default.fileExists(atPath: catalogURL.path)
            ? try JSONDecoder().decode(CharacterCatalog.self, from: Data(contentsOf: catalogURL))
            : CharacterCatalog(characters: [])
        guard catalog.characters.isEmpty || catalog.characters.map(\.id) == ["06002"] else {
            throw AssetError.invalid("Monday-chan requires character 06002")
        }
    }

    public func character(_ id: String) throws -> CharacterDescriptor {
        guard let character = catalog.characters.first(where: { $0.id == id }) else {
            throw AssetError.missing("character \(id)")
        }
        return character
    }

    public func url(for path: String) throws -> URL {
        let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/") else { throw AssetError.invalid("path leaves the data directory") }
        guard FileManager.default.fileExists(atPath: url.path) else { throw AssetError.missing(path) }
        return url
    }

    public func mouths(for character: CharacterDescriptor) throws -> MouthCatalog {
        let url = try url(for: character.mouths + "index.json")
        let mouths = try JSONDecoder().decode(MouthCatalog.self, from: Data(contentsOf: url))
        guard mouths.cells == ["mouth_00": 0, "mouth_07": 7, "mouth_17": 17, "mouth_35": 35] else { throw AssetError.invalid("Monday-chan requires mouth cells 0, 7, 17, and 35") }
        let size = mouths.projector_size
        guard [size.x, size.y, size.z].allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw AssetError.invalid("mouth projector size")
        }
        return mouths
    }
}
