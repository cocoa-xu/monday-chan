import Foundation
import Testing
@testable import MondayChan

@Test @MainActor func onboardingRequiresBothIndependentSources() {
    let model = MondayOnboardingModel(destination: URL(fileURLWithPath: "/tmp/monday-test")) {}
    #expect(!model.canImport)
    model.gameFolder = URL(fileURLWithPath: "/tmp/game")
    #expect(!model.canImport)
    #expect(model.acceptMedia([URL(fileURLWithPath: "/tmp/performance.mov")]))
    #expect(model.canImport)
}

@Test @MainActor func onboardingAcceptsSupportedMediaAndRejectsOtherFiles() {
    let model = MondayOnboardingModel(destination: URL(fileURLWithPath: "/tmp/monday-test")) {}
    #expect(model.acceptMedia([URL(fileURLWithPath: "/tmp/performance.mp4")]))
    #expect(model.mediaFile?.pathExtension == "mp4")
    #expect(!model.acceptMedia([URL(fileURLWithPath: "/tmp/readme.txt")]))
    #expect(model.mediaFile?.pathExtension == "mp4")
}

@Test func interfaceLanguageFollowsOnlyPrimaryJapanese() {
    #expect(AppLanguage.system.resolve(preferredLanguages: ["ja-JP", "en-US"]) == .japanese)
    #expect(AppLanguage.system.resolve(preferredLanguages: ["en-US", "ja-JP"]) == .english)
    #expect(AppLanguage.english.resolve(preferredLanguages: ["ja-JP"]) == .english)
    #expect(AppLanguage.japanese.resolve(preferredLanguages: ["en-US"]) == .japanese)
}

@Test func onboardingCopyIsLocalizedInEnglishAndJapanese() {
    let english = LocalizedText(language: .english)
    let japanese = LocalizedText(language: .japanese)
    #expect(english("Set up Monday-chan") == "Set Up Monday-chan")
    #expect(japanese("Set up Monday-chan") == "月曜日ちゃんをセットアップ")
    #expect(english("Monday Video or Audio") == "Monday Video or Audio")
    #expect(japanese("Monday Video or Audio") == "月曜日の動画または音声")
    #expect(japanese("Open Original Video") == "元の動画を開く")
    #expect(japanese.controls.search == "検索")
}
