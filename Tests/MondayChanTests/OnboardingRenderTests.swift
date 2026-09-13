import AppKit
import Testing
@testable import MondayChan

@Test(.enabled(if: ProcessInfo.processInfo.environment["MONDAY_EXPORT_ONBOARDING"] == "1")) @MainActor
func exportEnglishAndJapaneseOnboardingWindows() throws {
    _ = NSApplication.shared
    let output = URL(fileURLWithPath: ".build/onboarding", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (language, state, suffix) in [(AppLanguage.english, MondayOnboardingModel.State.selection, "en"),
                                      (.japanese, .selection, "ja"),
                                      (.japanese, .failed("選択した動画を確認してください。詳細なエラー情報がここに表示されます。"), "ja-error")] {
        let suite = "MondayOnboardingRender.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(language.rawValue, forKey: "appLanguage")
        let localization = AppLocalization(defaults: defaults)
        let window = OnboardingWindow(destination: output.appendingPathComponent("data"), localization: localization,
                                      initialState: state, onCancel: {}) {}
        defer { window.close() }
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: output.appendingPathComponent("setup-\(suffix).png"), options: .atomic)
        #expect(view.bounds.width == 780)
        #expect(view.bounds.height == 540)
        #expect(bitmap.pixelsWide >= 780)
        #expect(bitmap.pixelsHigh >= 540)
    }
}
