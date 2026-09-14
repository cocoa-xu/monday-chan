import AppKit
import FlowingDayControls
import FlowingDayPreferences
import SwiftUI

struct PreferencesRoot: View {
    enum Page { case playback, resources, general, about }
    @ObservedObject var controller: MondayController
    @ObservedObject var localization: AppLocalization
    @ObservedObject var appearance: MondayAppearance
    let dataRoot: URL
    let manageResources: () -> Void
    @State private var page = Page.playback
    private var text: LocalizedText { localization.text }

    init(controller: MondayController, localization: AppLocalization, appearance: MondayAppearance,
         dataRoot: URL, page: Page = .playback, manageResources: @escaping () -> Void) {
        self.controller = controller
        self.localization = localization
        self.appearance = appearance
        self.dataRoot = dataRoot
        self.manageResources = manageResources
        _page = State(initialValue: page)
    }

    var body: some View {
        PreferencesView(selection: $page, configuration: PreferencesViewConfiguration(
            applicationName: "Monday-chan", preferencesTitle: text("Preferences"),
            defaultAccent: MondayTheme.accent,
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
                PreferencesPage(id: Page.general, title: text("General"), icon: .system("gearshape")) { general },
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

    private var general: some View {
        PreferencesPaneStack {
            PreferencesSection(text("Menu Bar")) {
                PreferencesSegmentedRow(title: text("Icon style"),
                                        caption: text("Choose a miniature sign or a simple 月 character."),
                                        controlWidth: 220,
                                        selection: $appearance.menuBarIconStyle,
                                        options: [FlowingSegmentOption(MenuBarIconStyle.sign, label: text("Mini sign")),
                                                  FlowingSegmentOption(MenuBarIconStyle.text, label: text("Plain text"))])
                PreferencesRowSeparator()
                PreferencesRow(title: text("Preview")) {
                    Group {
                        if appearance.menuBarIconStyle == .sign, let image = MondayMenuBarIcon.sign {
                            Image(nsImage: image)
                        } else {
                            Text("月").font(.system(size: 14, weight: .medium))
                        }
                    }
                    .frame(width: 44, height: 28)
                    .background(FlowingPalette.card, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel(text(appearance.menuBarIconStyle == .sign ? "Mini sign" : "Plain text"))
                }
            }
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
