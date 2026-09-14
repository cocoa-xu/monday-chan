import AppKit
import Combine
import MondayCore

@MainActor
final class MondayController: ObservableObject {
    enum PlaybackError: Error { case missingAudio, missingCharacter, other(Error) }
    enum PlaybackState: Equatable { case idle, loading, playing }

    @Published var selectedDisplayIDs: Set<String> {
        didSet {
            defaults.set(selectedDisplayIDs.sorted(), forKey: "monday.displayIDs")
            error = nil
            if state != .idle { stop() }
            evaluateAutomaticPlayback()
        }
    }
    @Published var trigger: MondayTrigger {
        didSet {
            defaults.set(trigger.rawValue, forKey: "monday.trigger")
            error = nil
            evaluateAutomaticPlayback()
        }
    }
    @Published var allowsDuringFocus: Bool {
        didSet {
            defaults.set(allowsDuringFocus, forKey: "monday.allowsDuringFocus")
            evaluateAutomaticPlayback()
        }
    }
    @Published var volume: Double {
        didSet {
            let normalized = volume.isFinite ? min(max(volume, 0), 1) : 0.8
            if normalized != volume { volume = normalized; return }
            defaults.set(volume, forKey: "monday.volume")
            playback?.setVolume(Float(volume))
        }
    }
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var error: Error?
    @Published private(set) var displays: [MondayDisplay]
    @Published private(set) var focusIsUnavailable = false
    var selectedDisplays: [MondayDisplay] { displays.filter { selectedDisplayIDs.contains($0.id) } }

    private let library: AssetLibrary
    private let defaults: UserDefaults
    private let loadPerformance: @Sendable (AssetLibrary) async throws -> MondayPerformance
    private let displayProvider: @MainActor () -> [MondayDisplay]
    private let focusProvider: @MainActor () -> Bool?
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    private var completedDays: Set<String>
    private var loadTask: Task<Void, Never>?
    private var overlays: [MondayOverlay] = []
    private var playback: MondayPlayback?
    private var playbackDisplays: [MondayDisplay] = []
    private var completedDisplays: Set<String> = []
    private var playbackGeneration = UUID()
    private var isClosed = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private enum UnavailableReason { case sleeping, inactive }
    private var unavailableReasons: Set<UnavailableReason> = []

    init(library: AssetLibrary, defaults: UserDefaults = .standard,
         loader: MondayPerformanceLoader = MondayPerformanceLoader(),
         loadPerformance: (@Sendable (AssetLibrary) async throws -> MondayPerformance)? = nil,
         displays: @escaping @MainActor () -> [MondayDisplay] = { MondayDisplay.connected },
         now: @escaping () -> Date = Date.init,
         timeZone: @escaping () -> TimeZone = { .autoupdatingCurrent },
         focus: @escaping @MainActor () -> Bool? = { MondayFocus.isFocused }) {
        self.library = library
        self.defaults = defaults
        self.loadPerformance = loadPerformance ?? { library in try await loader.load(library: library) }
        displayProvider = displays
        focusProvider = focus
        self.now = now
        self.timeZone = timeZone
        self.displays = displays()
        selectedDisplayIDs = Set(defaults.stringArray(forKey: "monday.displayIDs")
                                 ?? defaults.string(forKey: "monday.displayID").map { [$0] } ?? [])
        trigger = defaults.string(forKey: "monday.trigger").flatMap(MondayTrigger.init(rawValue:)) ?? .manual
        allowsDuringFocus = defaults.bool(forKey: "monday.allowsDuringFocus")
        let storedVolume = defaults.object(forKey: "monday.volume") == nil ? 0.8 : defaults.double(forKey: "monday.volume")
        volume = storedVolume.isFinite ? min(max(storedVolume, 0), 1) : 0.8
        completedDays = Set(defaults.stringArray(forKey: "monday.completedDays") ?? [])
        installObservers()
        evaluateAutomaticPlayback()
    }

    func play() { startPlayback(completedDay: nil) }

    func stop() {
        playbackGeneration = UUID()
        loadTask?.cancel()
        loadTask = nil
        overlays.forEach { $0.stop() }
        overlays.removeAll()
        playback?.stop()
        playback = nil
        playbackDisplays.removeAll()
        completedDisplays.removeAll()
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
        if !playbackDisplays.isEmpty && selectedDisplays != playbackDisplays { stop() }
    }

    func sessionDidWake() {
        guard !isClosed else { return }
        unavailableReasons.remove(.inactive)
        refreshDisplays()
        evaluateAutomaticPlayback()
    }

    func sessionDidBecomeUnavailable() {
        guard !isClosed else { return }
        unavailableReasons.insert(.inactive)
        stop()
        updateTimer()
    }

    func requestFocusAccess() async {
        await MondayFocus.requestAccess()
        evaluateAutomaticPlayback()
    }

    func evaluateAutomaticPlayback() {
        guard !isClosed else { return }
        let focused = focusProvider()
        focusIsUnavailable = focused == nil
        defer { updateTimer() }
        guard trigger != .manual, unavailableReasons.isEmpty, state == .idle, error == nil,
              !selectedDisplays.isEmpty, allowsDuringFocus || focused == false,
              let day = schedule.occurrence(at: now(), timeZone: timeZone()) else { return }
        startPlayback(completedDay: day)
    }

    private var schedule: MondaySchedule {
        var seconds = 0
        if trigger == .randomSunday, let window = MondaySchedule.window(on: now(), timeZone: timeZone()) {
            var choices = defaults.dictionary(forKey: "monday.randomSeconds") as? [String: Int] ?? [:]
            if let stored = choices[window.day], (0..<900).contains(stored) { seconds = stored }
            else {
                seconds = Int.random(in: 0..<900)
                choices[window.day] = seconds
                let days = choices.keys.sorted().suffix(16)
                defaults.set(choices.filter { days.contains($0.key) }, forKey: "monday.randomSeconds")
            }
        }
        return MondaySchedule(trigger: trigger, completedDays: completedDays, randomSecond: seconds)
    }

    private func startPlayback(completedDay: String?) {
        guard !isClosed, state == .idle, unavailableReasons.isEmpty, !selectedDisplays.isEmpty else { return }
        let displays = selectedDisplays
        error = nil
        state = .loading
        playbackDisplays = displays
        let generation = UUID()
        playbackGeneration = generation
        loadTask = Task { [weak self, library, loadPerformance] in
            do {
                let performance = try await loadPerformance(library)
                try Task.checkCancellation()
                guard let self, self.playbackGeneration == generation else { return }
                guard self.canPresent(on: displays, completedDay: completedDay) else { self.stop(); return }
                let playback = try MondayPlayback(performance: performance, volume: Float(self.volume), participantCount: displays.count)
                self.playback = playback
                for display in displays {
                    let overlay = try MondayOverlay(performance: performance, library: library, display: display,
                                                    volume: Float(self.volume), playback: playback,
                                                    onDismiss: { [weak self] in self?.stop() }, onError: { [weak self] error in
                        guard let self, self.playbackGeneration == generation else { return }
                        self.error = self.playbackError(for: error)
                        self.stop()
                    }) { [weak self] in self?.playbackFinished(displayID: display.id, generation: generation) }
                    self.overlays.append(overlay)
                }
                guard self.canPresent(on: displays, completedDay: completedDay) else { self.stop(); return }
                for overlay in self.overlays { try overlay.start() }
                self.state = .playing
                self.loadTask = nil
                if let completedDay { self.recordCompletion(completedDay) }
            } catch {
                guard let self, self.playbackGeneration == generation else { return }
                if !(error is CancellationError) { self.error = self.playbackError(for: error) }
                self.stop()
            }
        }
    }

    private func canPresent(on displays: [MondayDisplay], completedDay: String?) -> Bool {
        guard unavailableReasons.isEmpty, selectedDisplays == displays else { return false }
        guard let completedDay else { return true }
        return (allowsDuringFocus || focusProvider() == false)
            && schedule.occurrence(at: now(), timeZone: timeZone()) == completedDay
    }

    private func playbackFinished(displayID: String, generation: UUID) {
        guard playbackGeneration == generation else { return }
        completedDisplays.insert(displayID)
        if completedDisplays.count == playbackDisplays.count { stop() }
    }

    private func recordCompletion(_ day: String) {
        completedDays.insert(day)
        completedDays = Set(completedDays.sorted().suffix(16))
        defaults.set(completedDays.sorted(), forKey: "monday.completedDays")
    }

    private func updateTimer() {
        timer?.invalidate()
        timer = nil
        guard !isClosed, trigger != .manual, unavailableReasons.isEmpty else { return }
        let date = now()
        let delay = max(1, MondaySchedule.nextCheck(after: date, timeZone: timeZone()).timeIntervalSince(date))
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluateAutomaticPlayback() }
        }
        timer?.tolerance = delay > 60 ? 1 : 0.1
    }

    private func installObservers() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSApplication.didChangeScreenParametersNotification, NSApplication.didBecomeActiveNotification,
                     NSNotification.Name.NSSystemTimeZoneDidChange, NSNotification.Name.NSSystemClockDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshDisplays()
                    self?.evaluateAutomaticPlayback()
                }
            })
        }
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
