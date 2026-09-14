import AppKit
import Combine
import FlowingDayControls

enum MenuBarIconStyle: String, CaseIterable {
    case sign
    case text
}

@MainActor
final class MondayAppearance: ObservableObject {
    @Published var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: "showsMenuBarIcon") }
    }
    @Published var showsDockIcon: Bool {
        didSet { defaults.set(showsDockIcon, forKey: "showsDockIcon") }
    }
    @Published var menuBarIconStyle: MenuBarIconStyle {
        didSet { defaults.set(menuBarIconStyle.rawValue, forKey: "menuBarIconStyle") }
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsMenuBarIcon = defaults.object(forKey: "showsMenuBarIcon") as? Bool ?? true
        showsDockIcon = defaults.object(forKey: "showsDockIcon") as? Bool ?? true
        menuBarIconStyle = defaults.string(forKey: "menuBarIconStyle").flatMap(MenuBarIconStyle.init(rawValue:)) ?? .sign
    }
}

enum MondayTheme {
    static let onAccent = FlowingPalette.dynamic(light: 0x3B2A08, dark: 0x3B2A08)
    static let accent = FlowingAccent(
        fill: FlowingPalette.dynamic(light: 0xFFE51A, dark: 0xFFE51A),
        foreground: FlowingPalette.dynamic(light: 0x765B00, dark: 0xFFE51A),
        wash: FlowingPalette.translucent(light: 0xFFE51A, lightAlpha: 0.24, dark: 0xFFE51A, darkAlpha: 0.18),
        veil: FlowingPalette.translucent(light: 0xFFE51A, lightAlpha: 0.12, dark: 0xFFE51A, darkAlpha: 0.09)
    )
    static let switchAccent = FlowingAccent(
        fill: FlowingPalette.dynamic(light: 0xF2D531, dark: 0xF2D531),
        foreground: accent.foreground
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
