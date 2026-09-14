import Foundation
import Testing
@testable import MondayChan

@Test @MainActor func onboardingRequiresBothIndependentSources() async {
    let model = MondayOnboardingModel(destination: URL(fileURLWithPath: "/tmp/monday-test"), validateMedia: { _ in }) {}
    #expect(!model.canImport)
    model.gameFolder = URL(fileURLWithPath: "/tmp/game")
    #expect(!model.canImport)
    #expect(model.acceptMedia([URL(fileURLWithPath: "/tmp/performance.mov")]))
    for _ in 0..<100 where !model.canImport { await Task.yield() }
    #expect(model.canImport)
}

@Test @MainActor func onboardingAcceptsSupportedMediaAndRejectsOtherFiles() async {
    let model = MondayOnboardingModel(destination: URL(fileURLWithPath: "/tmp/monday-test"), validateMedia: { _ in }) {}
    #expect(model.acceptMedia([URL(fileURLWithPath: "/tmp/performance.mp4")]))
    for _ in 0..<100 where model.mediaIsChecking { await Task.yield() }
    #expect(model.mediaFile?.pathExtension == "mp4")
    #expect(!model.acceptMedia([URL(fileURLWithPath: "/tmp/readme.txt")]))
    #expect(model.mediaFile?.pathExtension == "mp4")
}

@Test @MainActor func invalidMondayMediaStaysOnTheSelectionPage() async {
    let model = MondayOnboardingModel(destination: URL(fileURLWithPath: "/tmp/monday-test"),
                                      validateMedia: { _ in throw MondayImportError.unexpectedAudioDuration }) {}
    model.gameFolder = URL(fileURLWithPath: "/tmp/game")
    #expect(model.acceptMedia([URL(fileURLWithPath: "/tmp/wrong.mp4")]))
    for _ in 0..<100 where model.mediaIsChecking { await Task.yield() }
    #expect(model.state == .selection)
    #expect(model.mediaHasError)
    #expect(!model.canImport)
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
    #expect(japanese("Check Your Video") == "動画を確認してください")
    #expect(japanese("This does not look like the Monday video. Choose the original clip or its audio and try again.")
            == "月曜日の動画ではないようです。元の動画、またはその音声を選び直してください。")
    #expect(japanese("Open Original Video") == "元の動画を開く")
    #expect(japanese.controls.search == "検索")
}
