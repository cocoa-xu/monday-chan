import FlowingDayControls
import FlowingDayPreferences
import MondayCore
import SwiftUI

struct MondayPreferencesPane: View {
    @ObservedObject var controller: MondayController
    @EnvironmentObject private var localization: AppLocalization
    private var text: LocalizedText { localization.text }

    var body: some View {
        PreferencesPaneStack {
            PreferencesSection(text("Playback")) {
                PreferencesRow(symbol: "display", title: text("Monitors")) {
                    FlowingMultiSelectMenu(displaySummary, label: text("Monitors"), minimumWidth: 230,
                                           options: displayOptions).frame(width: 250)
                }
                PreferencesRowSeparator()
                PreferencesRow(symbol: "calendar", title: text("Automatic playback")) {
                    FlowingSelect(label: text("Automatic playback"), selection: $controller.trigger,
                                  options: MondayTrigger.allCases.map { FlowingSelectOption($0, label: triggerName($0)) },
                                  minimumWidth: 230).frame(width: 250)
                }
                if controller.trigger != .manual {
                    PreferencesRowSeparator()
                    PreferencesSwitchRow(symbol: "moon", title: text("Allow during Focus"), isOn: $controller.allowsDuringFocus)
                        .flowingAccent(MondayTheme.switchAccent)
                    if !controller.allowsDuringFocus && controller.focusIsUnavailable {
                        PreferencesRowSeparator()
                        PreferencesRow(symbol: "moon.badge.exclamationmark", title: text("Focus access needed"),
                                       caption: text("Automatic playback waits until Focus status is available.")) {
                            Button(text(MondayFocus.canRequestAccess ? "Allow Access…" : "Open Settings")) {
                                Task { await controller.requestFocusAccess() }
                            }
                                .buttonStyle(FlowingSoftButtonStyle())
                        }
                    }
                }
                PreferencesRowSeparator()
                PreferencesSliderRow(symbol: "speaker.wave.2", title: text("Volume"), value: $controller.volume, in: 0...1, step: 0.05) {
                    String(format: "%.0f%%", $0 * 100)
                }
                PreferencesRowSeparator()
                PreferencesRow(symbol: "play.circle", title: text("Preview")) {
                    Button {
                        controller.state == .idle ? controller.play() : controller.stop()
                    } label: {
                        Text(text(controller.state == .idle ? "Play" : "Stop"))
                            .foregroundStyle(controller.state == .idle ? MondayTheme.onAccent : MondayTheme.accent.foreground)
                    }
                    .buttonStyle(FlowingSoftButtonStyle(isProminent: controller.state == .idle))
                    .disabled(controller.state == .idle && controller.selectedDisplays.isEmpty)
                    .opacity(controller.state == .idle && controller.selectedDisplays.isEmpty ? 0.45 : 1)
                }
            }
            if !controller.selectedDisplayIDs.isEmpty && controller.selectedDisplays.isEmpty {
                Text(text("Selected monitors are disconnected.")).font(.caption).foregroundStyle(FlowingPalette.muted)
            }
            if let error = controller.error {
                Text(errorText(error)).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var displaySummary: String {
        if controller.selectedDisplayIDs.isEmpty { return text("Choose monitors") }
        if controller.selectedDisplayIDs.count == 1, let display = controller.selectedDisplays.first { return display.name }
        return text("%d selected", controller.selectedDisplayIDs.count)
    }

    private var displayOptions: [FlowingMultiSelectOption] {
        let connected = Set(controller.displays.map(\.id))
        let entries = controller.displays.map { ($0.id, $0.name) }
            + controller.selectedDisplayIDs.subtracting(connected).sorted().map { ($0, text("Disconnected monitor")) }
        return entries.map { id, name in
            FlowingMultiSelectOption(name, id: id, isOn: Binding(get: { controller.selectedDisplayIDs.contains(id) }, set: {
                if $0 { controller.selectedDisplayIDs.insert(id) }
                else { controller.selectedDisplayIDs.remove(id) }
            }))
        }
    }

    private func triggerName(_ trigger: MondayTrigger) -> String {
        switch trigger {
        case .manual: text("Manual only")
        case .sunday2345: text("Sunday · 23:45")
        case .sunday2350: text("Sunday · 23:50")
        case .sunday2359: text("Sunday · 23:59")
        case .randomSunday: text("Sunday · Random 23:45–00:00")
        }
    }

    private func errorText(_ error: Error) -> String {
        guard let error = error as? MondayController.PlaybackError else { return text.error(error) }
        switch error {
        case .missingAudio, .missingCharacter: return text("Resources are missing. Import them again in Resources.")
        case .other(let underlying): return text.error(underlying)
        }
    }
}
