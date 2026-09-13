import AppKit
import Combine
import MondayCore

@MainActor
final class MondayController: ObservableObject {
    enum PlaybackError: Error { case missingAudio, missingCharacter, other(Error) }

    enum PlaybackState: Equatable {
        case idle
        case loading
        case playing
    }

    @Published var selectedDisplayID: String? {
        didSet {
            defaults.set(selectedDisplayID, forKey: Keys.displayID)
            error = nil
            displayConfigurationChanged()
            evaluateAutomaticPlayback()
        }
    }
    @Published var trigger: MondayTrigger {
        didSet {
            defaults.set(trigger.rawValue, forKey: Keys.trigger)
            error = nil
            resetMouseBaseline()
            evaluateAutomaticPlayback()
        }
    }
    @Published var volume: Double {
        didSet {
            let normalized = volume.isFinite ? min(max(volume, 0), 1) : 0.8
            if normalized != volume {
                volume = normalized
                return
            }
            defaults.set(volume, forKey: Keys.volume)
            overlay?.setVolume(Float(volume))
        }
    }
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var error: Error?
    @Published private(set) var displays: [MondayDisplay]

    var selectedDisplay: MondayDisplay? { displays.first { $0.id == selectedDisplayID } }

    private enum Keys {
        static let displayID = "monday.displayID"
        static let trigger = "monday.trigger"
        static let volume = "monday.volume"
        static let completedDays = "monday.completedDays"
    }

    private let library: AssetLibrary
    private let defaults: UserDefaults
    private let loadPerformance: @Sendable (AssetLibrary) async throws -> MondayPerformance
    private let displayProvider: @MainActor () -> [MondayDisplay]
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    private var completedDays: Set<String>
    private var loadTask: Task<Void, Never>?
    private var overlay: MondayOverlay?
    private var playbackDisplay: MondayDisplay?
    private var playbackGeneration = UUID()
    private var isClosed = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private enum UnavailableReason { case sleeping, inactive }
    private var unavailableReasons: Set<UnavailableReason> = []
    private var mouseBaseline: UInt32?

    init(library: AssetLibrary, defaults: UserDefaults = .standard,
         loader: MondayPerformanceLoader = MondayPerformanceLoader(),
         loadPerformance: (@Sendable (AssetLibrary) async throws -> MondayPerformance)? = nil,
         displays: @escaping @MainActor () -> [MondayDisplay] = { MondayDisplay.connected },
         now: @escaping () -> Date = Date.init,
         timeZone: @escaping () -> TimeZone = { .autoupdatingCurrent }) {
        self.library = library
        self.defaults = defaults
        self.loadPerformance = loadPerformance ?? { library in try await loader.load(library: library) }
        self.displayProvider = displays
        self.now = now
        self.timeZone = timeZone
        self.displays = displays()
        selectedDisplayID = defaults.string(forKey: Keys.displayID)
        trigger = defaults.string(forKey: Keys.trigger).flatMap(MondayTrigger.init(rawValue:)) ?? .manual
        let storedVolume = defaults.object(forKey: Keys.volume) == nil ? 0.8 : defaults.double(forKey: Keys.volume)
        volume = storedVolume.isFinite ? min(max(storedVolume, 0), 1) : 0.8
        completedDays = Set(defaults.stringArray(forKey: Keys.completedDays) ?? [])
        installObservers()
        updateTimer()
        resetMouseBaseline()
        evaluateAutomaticPlayback()
    }

    func play() {
        guard !isClosed else { return }
        startPlayback(completedDay: nil)
    }

    func stop() {
        playbackGeneration = UUID()
        loadTask?.cancel()
        loadTask = nil
        overlay?.stop()
        overlay = nil
        playbackDisplay = nil
        state = .idle
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        stop()
        timer?.invalidate()
        timer = nil
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
    }

    func refreshDisplays() {
        displays = displayProvider()
        if let playbackDisplay, selectedDisplay != playbackDisplay { stop() }
    }

    func sessionDidWake() {
        guard !isClosed else { return }
        unavailableReasons.remove(.inactive)
        resetMouseBaseline()
        refreshDisplays()
        evaluateAutomaticPlayback()
    }

    func sessionDidBecomeUnavailable() {
        guard !isClosed else { return }
        unavailableReasons.insert(.inactive)
        stop()
        updateTimer()
    }

    func evaluateAutomaticPlayback(mouseMoved: Bool? = nil) {
        guard !isClosed, trigger != .manual, unavailableReasons.isEmpty, state == .idle, error == nil, selectedDisplay != nil else {
            updateTimer()
            return
        }
        let movement = mouseMoved ?? detectedMouseMovement()
        let schedule = MondaySchedule(trigger: trigger, completedDays: completedDays)
        guard let day = schedule.occurrence(at: now(), timeZone: timeZone(), mouseMoved: movement) else {
            updateTimer()
            return
        }
        startPlayback(completedDay: day)
        updateTimer()
    }

    private func startPlayback(completedDay: String?) {
        guard !isClosed, state == .idle, let display = selectedDisplay else { return }
        error = nil
        state = .loading
        playbackDisplay = display
        let generation = UUID()
        playbackGeneration = generation
        loadTask = Task { [weak self, library, loadPerformance] in
            do {
                let performance = try await loadPerformance(library)
                try Task.checkCancellation()
                guard let self, self.playbackGeneration == generation, self.unavailableReasons.isEmpty,
                      self.selectedDisplay == display else { return }
                let overlay = try MondayOverlay(performance: performance, library: library, display: display,
                                                volume: Float(self.volume), onError: { [weak self] error in
                    guard let self, self.playbackGeneration == generation else { return }
                    self.error = self.playbackError(for: error)
                }) { [weak self] in self?.playbackFinished(generation: generation) }
                self.overlay = overlay
                do { try overlay.start() }
                catch { overlay.stop(); self.overlay = nil; throw error }
                guard self.playbackGeneration == generation else { overlay.stop(); return }
                self.state = .playing
                self.loadTask = nil
                if let completedDay { self.recordCompletion(completedDay) }
            } catch is CancellationError {
                self?.finishCancelledLoad(generation: generation)
            } catch {
                guard let self, self.playbackGeneration == generation else { return }
                self.error = self.playbackError(for: error)
                self.state = .idle
                self.loadTask = nil
                self.overlay?.stop()
                self.overlay = nil
                self.playbackDisplay = nil
            }
        }
    }

    private func playbackFinished(generation: UUID) {
        guard playbackGeneration == generation else { return }
        overlay = nil
        playbackDisplay = nil
        state = .idle
    }

    private func finishCancelledLoad(generation: UUID) {
        guard playbackGeneration == generation else { return }
        loadTask = nil
        if overlay == nil {
            playbackDisplay = nil
            state = .idle
        }
    }

    private func recordCompletion(_ day: String) {
        completedDays.insert(day)
        completedDays = Set(completedDays.sorted().suffix(16))
        defaults.set(completedDays.sorted(), forKey: Keys.completedDays)
    }

    private func displayConfigurationChanged() {
        if state != .idle { stop() }
    }

    private func detectedMouseMovement() -> Bool {
        guard trigger == .firstActivity else { return false }
        let counter = CGEventSource.counterForEventType(.combinedSessionState, eventType: .mouseMoved)
        defer { mouseBaseline = counter }
        guard let baseline = mouseBaseline else { return false }
        return counter != baseline
    }

    private func resetMouseBaseline() {
        mouseBaseline = trigger == .firstActivity
            ? CGEventSource.counterForEventType(.combinedSessionState, eventType: .mouseMoved)
            : nil
    }

    private func updateTimer() {
        if trigger == .manual || !unavailableReasons.isEmpty {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluateAutomaticPlayback() }
            }
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDisplays() }
        })
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.unavailableReasons.insert(name == NSWorkspace.screensDidSleepNotification ? .sleeping : .inactive)
                    self.stop()
                    self.updateTimer()
                }
            })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.unavailableReasons.remove(name == NSWorkspace.screensDidWakeNotification ? .sleeping : .inactive)
                    self.resetMouseBaseline()
                    self.refreshDisplays()
                    self.evaluateAutomaticPlayback()
                }
            })
        }
    }

    private func playbackError(for error: Error) -> PlaybackError {
        guard case AssetError.missing(let detail) = error else { return .other(error) }
        if detail.contains("events/monday/kanade.m4a") { return .missingAudio }
        if detail.contains(MondayPerformance.characterID) { return .missingCharacter }
        return .other(error)
    }
}
