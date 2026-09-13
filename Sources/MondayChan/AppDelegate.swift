import AppKit
import Combine
import FlowingDayPreferences
import MondayCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let localization = AppLocalization()
    private var controller: MondayController?
    private var preferences: PreferencesWindowPresenter<PreferencesRoot>?
    private var onboarding: OnboardingWindow?
    private var statusItem: NSStatusItem?
    private var languageSubscription: AnyCancellable?
    private var stateSubscription: AnyCancellable?
    private var localeSubscription: AnyCancellable?
    private var startupTask: Task<Void, Never>?
    private var dataRoot: URL!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            dataRoot = try resolveDataRoot()
            installSubscriptions()
            installMenus()
            startupTask = Task { [weak self] in await self?.restoreOrOnboard() }
        } catch {
            showFatal(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        startupTask?.cancel()
        onboarding?.cancel()
        controller?.close()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        localization.refresh()
    }

    private func resolveDataRoot() throws -> URL {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--data"), arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return support.appendingPathComponent("Monday-chan/data", isDirectory: true)
    }

    private func restoreOrOnboard() async {
        do {
            _ = try await MondayImporter().validate(destination: dataRoot)
            try Task.checkCancellation()
            activatePlayback()
        } catch is CancellationError {
            return
        } catch {
            showOnboarding()
        }
    }

    private func activatePlayback() {
        do {
            controller?.close()
            let controller = MondayController(library: try AssetLibrary(root: dataRoot))
            self.controller = controller
            preferences = PreferencesWindowPresenter(rootView: PreferencesRoot(
                controller: controller, localization: localization, dataRoot: dataRoot,
                manageResources: { [weak self] in self?.showOnboarding() }
            ))
            stateSubscription = controller.$state.dropFirst().sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.installMenus() }
            }
            onboarding?.close()
            onboarding = nil
            installMenus()
            if CommandLine.arguments.contains("--preferences") { showPreferences() }
            if CommandLine.arguments.contains("--play-monday") {
                if controller.selectedDisplayID == nil { controller.selectedDisplayID = controller.displays.first?.id }
                controller.play()
            }
        } catch {
            showFatal(error)
        }
    }

    private func showOnboarding() {
        startupTask?.cancel()
        startupTask = nil
        controller?.sessionDidBecomeUnavailable()
        preferences?.window.close()
        if onboarding == nil {
            onboarding = OnboardingWindow(destination: dataRoot, localization: localization, onCancel: { [weak self] in
                self?.controller?.sessionDidWake()
            }) { [weak self] in
                self?.activatePlayback()
                self?.showPreferences()
            }
        }
        onboarding?.show()
    }

    private func installSubscriptions() {
        languageSubscription = localization.$text.sink { [weak self] _ in
            self?.preferences?.window.title = self?.localization.text("Preferences") ?? "Preferences"
            self?.installMenus()
        }
        localeSubscription = NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.localization.refresh() }
    }

    private func installMenus() {
        let text = localization.text
        let menu = NSMenu()
        let setup = menu.addItem(withTitle: controller == nil ? text("Set Up Monday-chan…") : text("Preferences…"),
                                 action: controller == nil ? #selector(openSetup) : #selector(showPreferences), keyEquivalent: ",")
        setup.target = self
        if let controller {
            let playback = menu.addItem(withTitle: controller.state == .idle ? text("Play Monday-chan") : text("Stop Monday-chan"),
                                        action: #selector(togglePlayback), keyEquivalent: "")
            playback.target = self
        }
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: text("Quit Monday-chan"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
        statusItem?.button?.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "Monday-chan")
        statusItem?.menu = menu
        let main = NSMenu()
        let item = main.addItem(withTitle: "Monday-chan", action: nil, keyEquivalent: "")
        item.submenu = menu.copy() as? NSMenu
        NSApp.mainMenu = main
    }

    private func showFatal(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = localization.text("Monday-chan could not start")
        alert.informativeText = localization.text.error(error)
        alert.runModal()
        NSApp.terminate(nil)
    }

    @objc private func openSetup() { showOnboarding() }
    @objc private func showPreferences() { preferences?.show() }
    @objc private func togglePlayback() {
        guard let controller else { return }
        if controller.state == .idle, controller.selectedDisplay == nil { showPreferences() }
        else { controller.state == .idle ? controller.play() : controller.stop() }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
