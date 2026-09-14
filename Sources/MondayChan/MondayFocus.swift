import AppKit
import Intents

@MainActor
enum MondayFocus {
    static var canRequestAccess: Bool { INFocusStatusCenter.default.authorizationStatus == .notDetermined }
    static var isFocused: Bool? {
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .authorized else { return nil }
        return center.focusStatus.isFocused
    }

    static func requestAccess() async {
        if canRequestAccess { _ = await INFocusStatusCenter.default.requestAuthorization() }
        else { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
    }
}
