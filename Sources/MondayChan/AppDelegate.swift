import AppKit
import Combine
import FlowingDayPreferences
import MondayCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let localization = AppLocalization()
    private let appearance = MondayAppearance()
    private var resources: MondayResources!
    private var controller: MondayController? { resources?.controller }
    private let loginItem = LoginItem()
    private var preferences: PreferencesWindowPresenter<PreferencesRoot>?
    private var onboarding: OnboardingWindow?
    private var statusItem: NSStatusItem?
    private var languageSubscription: AnyCancellable?
    private var stateSubscription: AnyCancellable?
    private var localeSubscription: AnyCancellable?
    private var appearanceSubscription: AnyCancellable?
    private var presenceSubscription: AnyCancellable?
    private var resourceSubscription: AnyCancellable?
    private var launchedAtLogin = false
    private var startupTask: Task<Void, Never>?
    private var dataRoot: URL!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            dataRoot = try resolveDataRoot()
            launchedAtLogin = LoginItem.launchedAtLogin
            resources = MondayResources(root: dataRoot)
            preferences = PreferencesWindowPresenter(rootView: PreferencesRoot(
                resources: resources, localization: localization, appearance: appearance, loginItem: loginItem,
                manageResources: { [weak self] in self?.showOnboarding() }
            ))
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
        loginItem.refresh()
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
            if !launchedAtLogin { showOnboarding() }
        }
    }

    private func activatePlayback() {
        do {
            try resources.activate()
            guard let controller else { return }
            onboarding?.close()
            onboarding = nil
            installMenus()
            if !launchedAtLogin || CommandLine.arguments.contains("--preferences") { showPreferences() }
            if CommandLine.arguments.contains("--play-monday") {
                if controller.selectedDisplayIDs.isEmpty, let display = controller.displays.first { controller.selectedDisplayIDs = [display.id] }
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
                self?.showPreferences()
            }) { [weak self] in
                self?.activatePlayback()
                self?.showPreferences()
            }
        }
        onboarding?.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreferences()
        return false
    }

    private func installSubscriptions() {
        presenceSubscription = appearance.$showsDockIcon.combineLatest(appearance.$showsMenuBarIcon)
            .sink { [weak self] dock, menuBar in
                NSApp.setActivationPolicy(dock ? .regular : .accessory)
                if !menuBar, let item = self?.statusItem {
                    NSStatusBar.system.removeStatusItem(item)
                    self?.statusItem = nil
                }
                DispatchQueue.main.async { [weak self] in self?.installMenus() }
            }
        resourceSubscription = resources.$controller.sink { [weak self] controller in
            self?.stateSubscription = controller?.$state.sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.installMenus() }
            }
            DispatchQueue.main.async { [weak self] in self?.installMenus() }
        }
        appearanceSubscription = appearance.$menuBarIconStyle.sink { [weak self] style in
            guard let button = self?.statusItem?.button else { return }
            MondayMenuBarIcon.apply(style, to: button)
        }
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
        let setup = menu.addItem(withTitle: text("Preferences…"),
                                 action: #selector(showPreferences), keyEquivalent: ",")
        setup.target = self
        if let controller {
            let playback = menu.addItem(withTitle: controller.state == .idle ? text("Play Monday-chan") : text("Stop Monday-chan"),
                                        action: #selector(togglePlayback), keyEquivalent: "")
            playback.target = self
        }
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: text("Quit Monday-chan"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        if appearance.showsMenuBarIcon && statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) }
        if let button = statusItem?.button { MondayMenuBarIcon.apply(appearance.menuBarIconStyle, to: button) }
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

    @objc private func showPreferences() { preferences?.show() }
    @objc private func togglePlayback() {
        guard let controller else { return }
        if controller.state == .idle, controller.selectedDisplays.isEmpty { showPreferences() }
        else { controller.state == .idle ? controller.play() : controller.stop() }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
