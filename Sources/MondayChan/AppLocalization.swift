import Combine
import Foundation

enum InterfaceLanguage: String, CaseIterable {
    case english = "en"
    case japanese = "ja"
}

enum AppLanguage: String, CaseIterable {
    case system
    case english = "en"
    case japanese = "ja"

    func resolve(preferredLanguages: [String]) -> InterfaceLanguage {
        switch self {
        case .english: .english
        case .japanese: .japanese
        case .system:
            Locale(identifier: preferredLanguages.first ?? "en").language.languageCode?.identifier == "ja" ? .japanese : .english
        }
    }
}

@MainActor
final class AppLocalization: ObservableObject {
    @Published var selection: AppLanguage {
        didSet {
            defaults.set(selection.rawValue, forKey: "appLanguage")
            refresh()
        }
    }
    @Published private(set) var text: LocalizedText
    private let defaults: UserDefaults
    private let preferredLanguages: () -> [String]

    init(defaults: UserDefaults = .standard, preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }) {
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages
        let selection = defaults.string(forKey: "appLanguage").flatMap(AppLanguage.init(rawValue:)) ?? .system
        self.selection = selection
        text = LocalizedText(language: selection.resolve(preferredLanguages: preferredLanguages()))
    }

    func refresh() {
        let language = selection.resolve(preferredLanguages: preferredLanguages())
        if text.language != language { text = LocalizedText(language: language) }
    }
}
