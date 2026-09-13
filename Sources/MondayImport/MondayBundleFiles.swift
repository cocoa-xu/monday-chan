import Foundation
import MondayCore

enum MondayBundleKind: CaseIterable {
    case body, hair, idle, run

    var identifier: String {
        switch self {
        case .body: "A33921"
        case .hair: "A33922"
        case .idle: "A34516"
        case .run: "A34600"
        }
    }

    var address: String? {
        switch self {
        case .body: "mdl_chr_drs_06002-nrml-0058-00_body"
        case .hair: "mdl_chr_drs_06002-nrml-0058-00_hair"
        case .idle, .run: nil
        }
    }

    var cacheDirectory: String { identifier.utf8.map { String(format: "%02X", $0) }.joined() }
}

struct MondayBundleFiles {
    let urls: [MondayBundleKind: URL]

    static func locate(in root: URL) throws -> MondayBundleFiles {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey]
        guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            throw AssetError.missing("game directory")
        }
        var found: [MondayBundleKind: URL] = [:]
        for case let url as URL in entries {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { entries.skipDescendants(); continue }
            for kind in MondayBundleKind.allCases {
                if values.isRegularFile == true, (url.lastPathComponent == kind.identifier || url.lastPathComponent == kind.address) {
                    guard values.fileSize ?? 0 <= 64 * 1024 * 1024 else { throw AssetError.invalid("bundle size") }
                    if let existing = found[kind], existing != url { throw AssetError.invalid("multiple copies of " + kind.identifier) }
                    found[kind] = url
                } else if values.isDirectory == true, url.lastPathComponent.uppercased() == kind.cacheDirectory {
                    let candidates = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
                        .filter { candidate in
                            let info = try candidate.resourceValues(forKeys: Set(keys))
                            return info.isRegularFile == true && info.isSymbolicLink != true && candidate.pathExtension != "meta"
                        }
                    guard candidates.count == 1 else { throw AssetError.invalid("ambiguous cache " + kind.identifier) }
                    guard (try candidates[0].resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 64 * 1024 * 1024 else { throw AssetError.invalid("bundle size") }
                    if let existing = found[kind], existing != candidates[0] { throw AssetError.invalid("multiple copies of " + kind.identifier) }
                    found[kind] = candidates[0]
                    entries.skipDescendants()
                }
            }
        }
        for kind in MondayBundleKind.allCases where found[kind] == nil { throw AssetError.missing(kind.identifier) }
        return MondayBundleFiles(urls: found)
    }

    func load(_ kind: MondayBundleKind) throws -> UnityAssetBundle {
        guard let url = urls[kind] else { throw AssetError.missing(kind.identifier) }
        try Task.checkCancellation()
        return try UnityAssetBundle(data: Data(contentsOf: url, options: .mappedIfSafe), headerKey: kind.address)
    }
}
