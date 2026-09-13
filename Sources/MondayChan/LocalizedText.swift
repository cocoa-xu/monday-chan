import FlowingDayControls
import Foundation
import MondayCore

struct LocalizedText {
    let language: InterfaceLanguage
    let bundle: Bundle
    var locale: Locale { Locale(identifier: language.rawValue) }

    init(language: InterfaceLanguage) {
        self.language = language
        let resources = AppResources.bundle
        bundle = resources.url(forResource: language.rawValue, withExtension: "lproj").flatMap(Bundle.init(url:)) ?? resources
    }

    func callAsFunction(_ key: String, _ arguments: CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: "Localizable")
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }

    func languageName(_ language: AppLanguage) -> String {
        switch language {
        case .system: self("Follow System")
        case .english: "English"
        case .japanese: bundle.localizedString(forKey: "Japanese", value: "Japanese", table: "Localizable")
        }
    }

    func error(_ error: Error) -> String {
        switch error {
        case MondayImportError.invalidGameFolder: self("The selected folder does not contain the required game assets.")
        case MondayImportError.invalidMedia: self("The selected media file does not contain usable audio.")
        case MondayImportError.unexpectedAudioDuration: self("Choose the original Monday video, approximately 11 seconds long.")
        case MondayImportError.extractionFailed(let message): self("Asset extraction failed.\n%@", message)
        case MondayImportError.unsafeDestination: self("The import destination is unsafe.")
        case MondayImportError.incomplete(let path): self("The imported assets are incomplete: %@", path)
        case AssetError.missing(let detail): self("Missing asset: %@", detail)
        case AssetError.invalid(let detail): self("Invalid asset: %@", detail)
        default: self("The operation could not be completed.\n%@", error.localizedDescription)
        }
    }

    var controls: FlowingStrings {
        FlowingStrings(selected: self("Selected"), notSelected: self("Not Selected"),
                       expanded: self("Expanded"), collapsed: self("Collapsed"),
                       on: self("On"), off: self("Off"), search: self("Search"), noResults: self("No Results"))
    }
}
