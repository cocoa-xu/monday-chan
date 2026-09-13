import Foundation

enum AppResources {
    static let bundle: Bundle = {
        if let url = Bundle.main.url(forResource: "MondayChan_MondayChan", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()
}
