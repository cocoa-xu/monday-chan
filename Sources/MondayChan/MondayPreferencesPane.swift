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
                PreferencesSearchPickerRow(
                    title: text("Monitor"),
                    caption: text("Monday-chan appears only on the monitor you choose."),
                    selection: $controller.selectedDisplayID,
                    options: [FlowingSelectOption<String?>(nil, label: text("Choose a monitor"))] + controller.displays.map {
                        FlowingSelectOption<String?>($0.id, label: $0.name)
                    }
                )
                PreferencesRowSeparator()
                PreferencesSearchPickerRow(
                    title: text("Automatic playback"),
                    caption: text("Uses your local time and plays at most once each Monday. If Monday-chan starts or wakes later that Monday, playback catches up."),
                    selection: $controller.trigger,
                    options: MondayTrigger.allCases.map { FlowingSelectOption($0, label: triggerName($0)) }
                )
                PreferencesRowSeparator()
                PreferencesSliderRow(title: text("Volume"), value: $controller.volume, in: 0...1, step: 0.05) {
                    String(format: "%.0f%%", $0 * 100)
                }
            }
            PreferencesSection(text("Monday-chan")) {
                PreferencesRow(title: statusText) {
                    Button(controller.state == .idle ? text("Play") : text("Stop")) {
                        controller.state == .idle ? controller.play() : controller.stop()
                    }
                    .buttonStyle(FlowingSoftButtonStyle(isProminent: controller.state == .idle))
                    .disabled(controller.state == .idle && controller.selectedDisplay == nil)
                }
            }
            if controller.selectedDisplayID != nil && controller.selectedDisplay == nil {
                Text(text("The selected monitor is not connected. Connect it to play Monday-chan."))
                    .font(.caption).foregroundStyle(FlowingPalette.muted)
            }
            Text(text("Right-click Kanade or use Stop to end the performance."))
                .font(.caption).foregroundStyle(FlowingPalette.muted)
            if let error = controller.error {
                Text(errorText(error)).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var statusText: String {
        switch controller.state {
        case .idle: text("Ready to play")
        case .loading: text("Loading Monday-chan…")
        case .playing: text("Monday-chan is playing")
        }
    }

    private func triggerName(_ trigger: MondayTrigger) -> String {
        switch trigger {
        case .manual: text("Manual only")
        case .midnight: text("Monday at 12:00 AM")
        case .morning: text("Monday at 9:00 AM")
        case .firstActivity: text("First mouse movement on Monday")
        }
    }

    private func errorText(_ error: Error) -> String {
        guard let error = error as? MondayController.PlaybackError else { return text.error(error) }
        switch error {
        case .missingAudio: return text("Monday-chan’s audio is missing. Add events/monday/kanade.m4a to the data folder.")
        case .missingCharacter: return text("Monday-chan’s character data is missing. Import character 06002 and try again.")
        case .other(let underlying): return text.error(underlying)
        }
    }
}
