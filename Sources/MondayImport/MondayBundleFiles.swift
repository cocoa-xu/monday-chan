import CryptoKit
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

enum MondayGameRelease: String, CaseIterable {
    case v1_1_1 = "1.1.1"

    var fingerprints: [MondayBundleKind: String] {
        switch self {
        case .v1_1_1:
            [
                .body: "f4aed80813f704b189627abe7360ddf3637aba577bee16238df0bcb5e2690894",
                .hair: "1a2c657b1b2b6b7245b456b882eb4b407c410618cded2477ecc78791eac174ec",
                .idle: "39dcf4b88469f5967078580f1cee2ed8c0a2c750caf0a7334e3446b8326e31e3",
                .run: "5e6478c1d6cb138163ae2ded40cf9df079b262410fa6519e973074c5b09d6f13"
            ]
        }
    }

    static func identify(fingerprints: [MondayBundleKind: String]) -> MondayGameRelease? {
        allCases.first { $0.fingerprints == fingerprints }
    }

    static func identify(files: MondayBundleFiles) throws -> MondayGameRelease {
        var fingerprints: [MondayBundleKind: String] = [:]
        for kind in MondayBundleKind.allCases {
            guard let url = files.urls[kind] else { throw AssetError.missing(kind.identifier) }
            fingerprints[kind] = try fingerprint(url)
        }
        guard let release = identify(fingerprints: fingerprints) else {
            throw AssetError.invalid("unsupported game version")
        }
        return release
    }

    private static func fingerprint(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
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

    func gameRelease() throws -> MondayGameRelease {
        try MondayGameRelease.identify(files: self)
    }
}
