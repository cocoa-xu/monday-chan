import Foundation
import MondayImport

actor ImportedResourceRemoval {
    static let paths = MondayAssetExtractor.preparedFiles + ["events/monday/kanade.m4a"]

    func remove(from directory: URL) throws -> URL? {
        let manager = FileManager.default
        guard directory.isFileURL,
              (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true else {
            throw MondayImportError.unsafeDestination
        }
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        guard root.pathComponents.count > 2, root != manager.homeDirectoryForCurrentUser else {
            throw MondayImportError.unsafeDestination
        }
        var files: [(String, URL)] = []
        for path in Self.paths {
            var file = root
            for component in path.split(separator: "/") {
                file.appendPathComponent(String(component))
                let values = try? file.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values?.isSymbolicLink != true else { throw MondayImportError.unsafeDestination }
            }
            guard manager.fileExists(atPath: file.path) else { continue }
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw MondayImportError.unsafeDestination
            }
            files.append((path, file))
        }
        guard !files.isEmpty else { return nil }
        let staging = root.deletingLastPathComponent().appendingPathComponent("Monday-chan Resources \(UUID().uuidString)")
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        var moved: [(URL, URL)] = []
        do {
            for (path, file) in files {
                let target = staging.appendingPathComponent(path)
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.moveItem(at: file, to: target)
                moved.append((file, target))
            }
            var trash: NSURL?
            try manager.trashItem(at: staging, resultingItemURL: &trash)
            return trash as URL?
        } catch {
            for (original, staged) in moved.reversed() { try manager.moveItem(at: staged, to: original) }
            try? manager.removeItem(at: staging)
            throw error
        }
    }
}
