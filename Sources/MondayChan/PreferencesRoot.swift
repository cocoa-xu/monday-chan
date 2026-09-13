import AppKit
import FlowingDayControls
import FlowingDayPreferences
import SwiftUI

struct PreferencesRoot: View {
    enum Page { case playback, resources, general, about }
    @ObservedObject var controller: MondayController
    @ObservedObject var localization: AppLocalization
    let dataRoot: URL
    let manageResources: () -> Void
    @State private var page = Page.playback
    private var text: LocalizedText { localization.text }

    var body: some View {
        PreferencesView(selection: $page, configuration: PreferencesViewConfiguration(
            applicationName: "Monday-chan", preferencesTitle: text("Preferences"),
            strings: PreferencesStrings(closePreferences: text("Close Preferences"), controls: text.controls)
        ), groups: [
            PreferencesPageGroup(id: "monday", pages: [
                PreferencesPage(id: Page.playback, title: text("Playback"),
                                subtitle: text("Choose when and where Monday-chan appears."),
                                icon: .system("play.circle")) { MondayPreferencesPane(controller: controller) },
                PreferencesPage(id: Page.resources, title: text("Resources"),
                                subtitle: text("Manage the locally imported performance files."),
                                icon: .system("shippingbox")) { resources }
            ]),
            PreferencesPageGroup(id: "application", pages: [
                PreferencesPage(id: Page.general, title: text("General"), icon: .system("gearshape")) { language },
                PreferencesPage(id: Page.about, title: text("About"), icon: .system("info.circle")) { about }
            ])
        ])
        .environmentObject(localization)
        .environment(\.locale, text.locale)
    }

    private var resources: some View {
        PreferencesPaneStack {
            PreferencesSection(text("Imported resources")) {
                PreferencesRow(title: text("Data folder"), caption: dataRoot.path(percentEncoded: false)) {
                    Button(text("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([dataRoot]) }
                        .buttonStyle(FlowingSoftButtonStyle())
                }
                PreferencesRowSeparator()
                PreferencesRow(title: text("Replace resources"),
                               caption: text("Import again from a game or export folder and a separate performance media file.")) {
                    Button(text("Import Again…"), action: manageResources).buttonStyle(FlowingSoftButtonStyle())
                }
            }
            Text(text("Imported resources stay on this Mac and are not included with the application."))
                .font(.caption).foregroundStyle(FlowingPalette.muted)
        }
    }

    private var language: some View {
        PreferencesPaneStack {
            PreferencesSection(text("Language")) {
                PreferencesSearchPickerRow(title: text("Language"),
                                           caption: text("Choose the language used throughout Monday-chan."),
                                           selection: $localization.selection,
                                           options: AppLanguage.allCases.map { FlowingSelectOption($0, label: text.languageName($0)) })
            }
            Text(text("Changes apply immediately.")).font(.caption).foregroundStyle(FlowingPalette.faint)
        }
    }

    private var about: some View {
        PreferencesPaneStack {
            PreferencesSection(text("Acknowledgements")) {
                PreferencesRow(title: "FlowingDayUI",
                               caption: text("Interface components · Version 2.6.4 · Apache License 2.0")) {
                    Button(text("View License")) {
                        guard let url = AppResources.bundle.url(forResource: "FlowingDayUI-LICENSE", withExtension: "txt",
                                                               subdirectory: "ThirdPartyNotices") else { return }
                        NSWorkspace.shared.open(url)
                    }.buttonStyle(FlowingSoftButtonStyle())
                }
            }
        }
    }
}
