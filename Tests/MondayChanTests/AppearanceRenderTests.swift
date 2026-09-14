import AppKit
import FlowingDayPreferences
import MondayCore
import Testing
@testable import MondayChan

@Test(.enabled(if: ProcessInfo.processInfo.environment["MONDAY_EXPORT_APPEARANCE"] == "1")) @MainActor
func exportMenuBarPreferencesInBothLanguagesAndAppearances() throws {
    _ = NSApplication.shared
    let output = URL(fileURLWithPath: ".build/appearance", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let root = URL(fileURLWithPath: "data", isDirectory: true)
    let library = try AssetLibrary(root: root)
    for language in [AppLanguage.english, .japanese] {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let suite = "MondayAppearanceRender.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(language.rawValue, forKey: "appLanguage")
            let localization = AppLocalization(defaults: defaults)
            let appearance = MondayAppearance(defaults: defaults)
            let controller = MondayController(library: library, defaults: defaults)
            defer { controller.close() }
            for page in [PreferencesRoot.Page.general, .playback, .resources, .about] {
                let presenter = PreferencesWindowPresenter(rootView: PreferencesRoot(
                    resources: MondayResources(root: root, controller: controller), localization: localization, appearance: appearance,
                    loginItem: LoginItem(), page: page, manageResources: {}
                ))
                let window = presenter.window
                defer { window.close() }
                window.appearance = NSAppearance(named: name)
                let view = try #require(window.contentView)
                view.layoutSubtreeIfNeeded()
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                let suffix = name == .aqua ? "light" : "dark"
                try data.write(to: output.appendingPathComponent("\(language.rawValue)-\(suffix)-\(page).png"), options: .atomic)
                #expect(view.bounds.width == 900)
                #expect(view.bounds.height == 640)
            }
        }
    }
}
