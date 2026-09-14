import AppKit
import Combine
import FlowingDayControls

enum MenuBarIconStyle: String, CaseIterable {
    case sign
    case text
}

@MainActor
final class MondayAppearance: ObservableObject {
    @Published var menuBarIconStyle: MenuBarIconStyle {
        didSet { defaults.set(menuBarIconStyle.rawValue, forKey: "menuBarIconStyle") }
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarIconStyle = defaults.string(forKey: "menuBarIconStyle").flatMap(MenuBarIconStyle.init(rawValue:)) ?? .sign
    }
}

enum MondayTheme {
    static let accent = FlowingAccent(
        fill: FlowingPalette.dynamic(light: 0x9B6800, dark: 0x946300),
        foreground: FlowingPalette.dynamic(light: 0x7F5100, dark: 0xFFD947),
        wash: FlowingPalette.translucent(light: 0xF5A900, lightAlpha: 0.19, dark: 0xFFD947, darkAlpha: 0.18),
        veil: FlowingPalette.translucent(light: 0xF5A900, lightAlpha: 0.09, dark: 0xFFD947, darkAlpha: 0.09)
    )
}

@MainActor
enum MondayMenuBarIcon {
    static let sign: NSImage? = {
        guard let url = AppResources.bundle.url(forResource: "monday-menu-sign", withExtension: "svg", subdirectory: "Assets"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 22, height: 18)
        image.isTemplate = false
        image.accessibilityDescription = "Monday-chan"
        return image
    }()

    static func apply(_ style: MenuBarIconStyle, to button: NSStatusBarButton) {
        let image = style == .sign ? sign : nil
        button.title = image == nil ? "月" : ""
        button.image = image
        button.font = .systemFont(ofSize: 14, weight: .medium)
        button.toolTip = "Monday-chan"
        button.setAccessibilityLabel("Monday-chan")
    }
}
