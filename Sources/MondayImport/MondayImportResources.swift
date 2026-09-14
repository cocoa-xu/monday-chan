import Foundation

enum MondayImportResources {
    static let bundle = resolve(in: .main) ?? .module

    static func resolve(in applicationBundle: Bundle) -> Bundle? {
        applicationBundle.url(forResource: "MondayChan_MondayImport", withExtension: "bundle")
            .flatMap(Bundle.init(url:))
    }
}
