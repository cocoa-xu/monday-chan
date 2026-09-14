import AppKit
import FlowingDayControls
import FlowingDayPreferences
import SwiftUI

struct PreferencesRoot: View {
    enum Page { case playback, resources, general, about }
    @ObservedObject var resources: MondayResources
    @ObservedObject var localization: AppLocalization
    @ObservedObject var appearance: MondayAppearance
    @ObservedObject var loginItem: LoginItem
    let manageResources: () -> Void
    @State private var page: Page
    @State private var confirmsRemoval = false
    private var text: LocalizedText { localization.text }

    init(resources: MondayResources, localization: AppLocalization, appearance: MondayAppearance,
         loginItem: LoginItem, page: Page = .playback, manageResources: @escaping () -> Void) {
        self.resources = resources
        self.localization = localization
        self.appearance = appearance
        self.loginItem = loginItem
        self.manageResources = manageResources
        _page = State(initialValue: page)
    }

    var body: some View {
        PreferencesView(selection: $page, configuration: PreferencesViewConfiguration(
            applicationName: "Monday-chan", preferencesTitle: text("Preferences"),
            defaultAccent: MondayTheme.accent,
            strings: PreferencesStrings(closePreferences: text("Close Preferences"), controls: text.controls)
        ), groups: [
            PreferencesPageGroup(id: "settings", pages: [
                PreferencesPage(id: Page.general, title: text("General"),
                                icon: .system("gearshape")) { general },
                PreferencesPage(id: Page.playback, title: text("Playback"),
                                icon: .system("play.circle")) { playback },
                PreferencesPage(id: Page.resources, title: text("Resources"),
                                icon: .system("shippingbox")) { resourcePane }
            ]),
            PreferencesPageGroup(id: "application", pages: [
                PreferencesPage(id: Page.about, title: text("About"),
                                subtitle: text("Version and acknowledgements"), icon: .system("info.circle"), headerIcon: .application) { about }
            ])
        ])
        .environmentObject(localization)
        .environment(\.locale, text.locale)
    }

    @ViewBuilder private var playback: some View {
        if let controller = resources.controller {
            MondayPreferencesPane(controller: controller).disabled(resources.isRemoving)
        } else {
            PreferencesSection(text("Resources")) {
                PreferencesRow(symbol: "shippingbox", title: text("No resources imported")) {
                    Button(text("Import…"), action: manageResources).buttonStyle(FlowingSoftButtonStyle())
                }
            }
        }
    }

    private var resourcePane: some View {
        PreferencesPaneStack {
            PreferencesSection(text("Imported resources")) {
                PreferencesRow(symbol: "shippingbox", title: text(resources.controller == nil ? "No resources imported" : "Monday-chan")) {
                    Button(text(resources.controller == nil ? "Import…" : "Import Again…"), action: manageResources)
                        .buttonStyle(FlowingSoftButtonStyle())
                }
                if resources.controller != nil {
                    PreferencesRowSeparator()
                    PreferencesRow(symbol: "folder", title: text("Data folder")) {
                        Button(text("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([resources.root]) }
                            .buttonStyle(FlowingSoftButtonStyle())
                    }
                    PreferencesRowSeparator()
                    PreferencesRow(symbol: "trash", title: text("Remove resources")) {
                        Button(text(resources.isRemoving ? "Removing…" : "Move to Trash…")) { confirmsRemoval = true }
                            .buttonStyle(FlowingSoftButtonStyle())
                    }
                }
            }.disabled(resources.isRemoving)
            if let error = resources.error {
                Text(text.error(error)).font(.caption).foregroundStyle(.red)
            }
        }
        .flowingConfirmationDialog(text("Remove imported resources?"),
                                   message: text("Imported copies will move to the Trash. Your original files and preferences will be kept."),
                                   isPresented: $confirmsRemoval, confirmationTitle: text("Move to Trash"),
                                   cancellationTitle: text("Cancel"), kind: .destructive, confirmationIsDefault: false) {
            Task { await resources.remove() }
        }
    }

    private var general: some View {
        PreferencesPaneStack {
            PreferencesSection(text("Application")) {
                PreferencesSwitchRow(symbol: "power", title: text("Launch at login"),
                                     isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                    .flowingAccent(MondayTheme.switchAccent)
                if loginItem.status == .requiresApproval {
                    PreferencesRowSeparator()
                    PreferencesRow(title: text("Allow in System Settings")) {
                        Button(text("Open Settings"), action: loginItem.openSettings).buttonStyle(FlowingSoftButtonStyle())
                    }
                }
                PreferencesRowSeparator()
                PreferencesSwitchRow(symbol: "dock.rectangle", title: text("Show in Dock"), isOn: $appearance.showsDockIcon)
                    .flowingAccent(MondayTheme.switchAccent)
                PreferencesRowSeparator()
                PreferencesRow(symbol: "globe", title: text("Language")) {
                    FlowingSelect(label: text("Language"), selection: $localization.selection,
                                  options: AppLanguage.allCases.map { FlowingSelectOption($0, label: text.languageName($0)) },
                                  minimumWidth: 180).frame(width: 180)
                }
            }
            PreferencesSection(text("Menu Bar")) {
                PreferencesSwitchRow(symbol: "menubar.rectangle", title: text("Show in menu bar"), isOn: $appearance.showsMenuBarIcon)
                    .flowingAccent(MondayTheme.switchAccent)
                if appearance.showsMenuBarIcon {
                    PreferencesRowSeparator()
                    PreferencesRow(symbol: "character", title: text("Icon style")) {
                        HStack(spacing: 12) {
                            if appearance.menuBarIconStyle == .sign, let image = MondayMenuBarIcon.sign {
                                Image(nsImage: image)
                            } else {
                                Text("月").font(.system(size: 14, weight: .medium))
                            }
                            FlowingSelect(label: text("Icon style"), selection: $appearance.menuBarIconStyle,
                                          options: [.init(.sign, label: text("Mini sign")), .init(.text, label: text("Plain text"))],
                                          minimumWidth: 180).frame(width: 180)
                        }
                    }
                }
            }
            if !appearance.showsDockIcon && !appearance.showsMenuBarIcon {
                Text(text("Open Monday-chan from Applications to return to Preferences."))
                    .font(.caption).foregroundStyle(FlowingPalette.muted)
            }
            if let error = loginItem.error {
                Text(text.error(error)).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { loginItem.refresh() }
    }

    private var flowingDayIcon: PreferencesRowIcon {
        if let url = AppResources.bundle.url(forResource: "flowing-day-ui", withExtension: "svg", subdirectory: "Assets"),
           let image = NSImage(contentsOf: url) { return .image(image) }
        return .system("square.on.square.fill")
    }

    private var about: some View {
        PreferencesPaneStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Monday-chan").font(.title2.bold())
                Text(text("Version %@", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"))
                    .foregroundStyle(FlowingPalette.muted)
            }
            PreferencesSection(text("Acknowledgements")) {
                PreferencesRow(icon: flowingDayIcon, title: "FlowingDayUI",
                               caption: text("Reusable preferences windows and macOS interface components.")) {
                    Link("GitHub", destination: URL(string: "https://github.com/cocoa-xu/flowing-day-ui")!)
                        .buttonStyle(FlowingSoftButtonStyle())
                }
            }
            HStack(spacing: 4) {
                Text("Copyright © 2026").foregroundStyle(FlowingPalette.muted)
                Link("Cocoa", destination: URL(string: "https://uwucocoa.moe")!)
                    .foregroundStyle(MondayTheme.accent.foreground)
            }.font(.callout)
        }
    }
}
