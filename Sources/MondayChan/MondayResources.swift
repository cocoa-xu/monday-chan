import Combine
import Foundation
import MondayCore

@MainActor
final class MondayResources: ObservableObject {
    let root: URL
    @Published private(set) var controller: MondayController?
    @Published private(set) var isRemoving = false
    @Published private(set) var error: Error?

    init(root: URL, controller: MondayController? = nil) {
        self.root = root
        self.controller = controller
    }

    func activate() throws {
        let library = try AssetLibrary(root: root)
        controller?.close()
        controller = MondayController(library: library)
        error = nil
    }

    func remove() async {
        guard !isRemoving else { return }
        isRemoving = true
        controller?.sessionDidBecomeUnavailable()
        defer { isRemoving = false }
        do {
            _ = try await ImportedResourceRemoval().remove(from: root)
            controller?.close()
            controller = nil
            error = nil
        } catch {
            self.error = error
            controller?.sessionDidWake()
        }
    }
}
