import AppKit
import Combine
import FlowingDayControls
import Testing
@testable import MondayChan

@Test @MainActor func menuBarStylePersistsAndFallsBackToSign() throws {
    let suite = "MondayAppearanceTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let appearance = MondayAppearance(defaults: defaults)
    #expect(appearance.menuBarIconStyle == .sign)
    for style in MenuBarIconStyle.allCases.reversed() {
        appearance.menuBarIconStyle = style
        #expect(MondayAppearance(defaults: defaults).menuBarIconStyle == style)
    }
    defaults.set("unknown", forKey: "menuBarIconStyle")
    #expect(MondayAppearance(defaults: defaults).menuBarIconStyle == .sign)
}

@Test @MainActor func menuBarStyleChangesImmediatelyWithoutLeavingStaleContent() throws {
    _ = NSApplication.shared
    let suite = "MondayMenuBarTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    defer { NSStatusBar.system.removeStatusItem(item) }
    let button = try #require(item.button)
    let appearance = MondayAppearance(defaults: defaults)
    let subscription = appearance.$menuBarIconStyle.sink { MondayMenuBarIcon.apply($0, to: button) }
    defer { subscription.cancel() }
    let sign = try #require(button.image)
    #expect(!sign.isTemplate)
    #expect(sign.size == NSSize(width: 22, height: 18))
    #expect(button.title.isEmpty)
    appearance.menuBarIconStyle = .text
    #expect(button.image == nil)
    #expect(button.title == "月")
    appearance.menuBarIconStyle = .sign
    #expect(button.image === sign)
    #expect(button.title.isEmpty)
    #expect(button.accessibilityLabel() == "Monday-chan")
}

@Test @MainActor func goldenAccentKeepsTextReadableInBothAppearances() throws {
    for name in [NSAppearance.Name.aqua, .darkAqua] {
        let appearance = try #require(NSAppearance(named: name))
        appearance.performAsCurrentDrawingAppearance {
            guard let fill = NSColor(MondayTheme.accent.fill).usingColorSpace(.sRGB),
                  let foreground = NSColor(MondayTheme.accent.foreground).usingColorSpace(.sRGB),
                  let canvas = NSColor(FlowingPalette.canvas).usingColorSpace(.sRGB) else {
                Issue.record("Theme colors must resolve to sRGB.")
                return
            }
            #expect(contrast(fill, NSColor(MondayTheme.onAccent)) >= 4.5)
            #expect(contrast(foreground, canvas) >= 4.5)
            #expect(fill.redComponent > fill.greenComponent)
            #expect(fill.greenComponent > fill.blueComponent)
        }
    }
}

@Test @MainActor func miniatureSignKeepsVectorArtworkAndCentersItsOutlinedGlyph() throws {
    let sign = try #require(MondayMenuBarIcon.sign)
    #expect(!sign.representations.isEmpty)
    #expect(sign.representations.allSatisfy { !($0 is NSBitmapImageRep) && $0.pixelsWide == 0 && $0.pixelsHigh == 0 })
    let url = try #require(AppResources.bundle.url(forResource: "monday-menu-sign", withExtension: "svg", subdirectory: "Assets"))
    let document = try XMLDocument(contentsOf: url)
    #expect(try document.nodes(forXPath: "//*[local-name()='image' or local-name()='text']").isEmpty)
    let glyph = try #require(document.nodes(forXPath: "//*[@id='moon']").first)
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"66\" height=\"54\" viewBox=\"0 0 66 54\">\(glyph.xmlString)</svg>"
    let image = try #require(NSImage(data: Data(svg.utf8)))
    for scale in [1, 2, 4] {
        let width = 22 * scale, height = 18 * scale
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= 0.5 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        #expect(maxX >= minX && maxY >= minY)
        #expect(abs(Double(minX + maxX + 1 - width + scale)) <= 1)
        #expect(abs(Double(minY + maxY + 1 - height)) <= 1)
    }
}

@Test func menuBarPreferencesAreLocalized() {
    let english = LocalizedText(language: .english)
    let japanese = LocalizedText(language: .japanese)
    #expect(english("Mini sign") == "Mini Sign")
    #expect(english("Icon style") == "Icon Style")
    #expect(english("Automatic playback") == "Automatic Playback")
    #expect(english("Version and acknowledgements") == "Version and Acknowledgements")
    #expect(japanese("Menu Bar") == "メニューバー")
    #expect(japanese("Mini sign") == "ミニ看板")
    #expect(japanese("Plain text") == "文字のみ")
    #expect(japanese("Quit") == "終了")
    #expect(english("Ready or not, Monday-chan is coming.") == "Ready or not, Monday-chan is coming.")
    #expect(japanese("Ready or not, Monday-chan is coming.") == "準備はいい？ 月曜日ちゃんがやってくるよ。")
}

@Test func statusBarClicksOpenTheExpectedDestination() {
    #expect(MondayStatusBarAction.resolve(eventType: .leftMouseUp) == .preferences)
    #expect(MondayStatusBarAction.resolve(eventType: .rightMouseUp) == .quickControls)
    #expect(MondayStatusBarAction.resolve(eventType: nil) == .preferences)
}

@Test func statusPopoverDismissesOnlyForOutsideWindows() {
    #expect(!MondayStatusPopoverDismissal.shouldDismiss(clickedWindow: 10, popoverWindow: nil, statusItemWindow: 20))
    #expect(!MondayStatusPopoverDismissal.shouldDismiss(clickedWindow: 10, popoverWindow: 10, statusItemWindow: 20))
    #expect(!MondayStatusPopoverDismissal.shouldDismiss(clickedWindow: 20, popoverWindow: 10, statusItemWindow: 20))
    #expect(MondayStatusPopoverDismissal.shouldDismiss(clickedWindow: 30, popoverWindow: 10, statusItemWindow: 20))
}

private func contrast(_ first: NSColor, _ second: NSColor) -> Double {
    func luminance(_ color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB)!
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { component -> Double in
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
    }
    let a = luminance(first), b = luminance(second)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

@Test @MainActor func menuBarAndDockCanBothBeHiddenAndPersistIndependently() throws {
    let suite = "MondayPresenceTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let appearance = MondayAppearance(defaults: defaults)
    #expect(appearance.showsDockIcon && appearance.showsMenuBarIcon)
    appearance.showsDockIcon = false
    #expect(appearance.showsMenuBarIcon)
    appearance.showsMenuBarIcon = false
    let restored = MondayAppearance(defaults: defaults)
    #expect(!restored.showsDockIcon && !restored.showsMenuBarIcon)
    restored.showsDockIcon = true
    #expect(!restored.showsMenuBarIcon)
}
