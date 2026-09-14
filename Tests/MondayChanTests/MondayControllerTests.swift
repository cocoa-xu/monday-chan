import Foundation
import MondayCore
import Testing
@testable import MondayChan

@Test(.enabled(if: FileManager.default.fileExists(atPath: "data/characters.json"))) @MainActor
func mondayPreferencesPersistAcrossControllerRestarts() throws {
    let suite = "MondayChanTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let display = MondayDisplay(id: "display-1", name: "Studio Display", frame: .zero, refreshRate: 60)
    let library = try AssetLibrary(root: URL(fileURLWithPath: "data"))
    let sunday = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 13)))
    var controller: MondayController? = MondayController(library: library, defaults: defaults, displays: { [display] }, now: { sunday })
    controller?.selectedDisplayIDs = [display.id]
    controller?.trigger = .sunday2350
    controller?.volume = 0.35
    controller?.close()
    controller = nil

    let restored = MondayController(library: library, defaults: defaults, displays: { [display] }, now: { sunday })
    defer { restored.close() }
    #expect(restored.selectedDisplayIDs == [display.id])
    #expect(restored.trigger == .sunday2350)
    #expect(abs(restored.volume - 0.35) < 0.001)
}

@Test(.enabled(if: FileManager.default.fileExists(atPath: "data/characters.json"))) @MainActor
func disconnectedSelectedDisplayNeverFallsBack() throws {
    let suite = "MondayChanTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("disconnected", forKey: "monday.displayID")
    defaults.set(MondayTrigger.sunday2345.rawValue, forKey: "monday.trigger")
    let controller = MondayController(library: try AssetLibrary(root: URL(fileURLWithPath: "data")), defaults: defaults,
                                      displays: { [MondayDisplay(id: "connected", name: "Display", frame: .zero, refreshRate: 60)] },
                                      now: { Date(timeIntervalSince1970: 0) })
    defer { controller.close() }
    controller.evaluateAutomaticPlayback()
    #expect(controller.selectedDisplays.isEmpty)
    #expect(controller.state == .idle)
}

@Test(.enabled(if: FileManager.default.fileExists(atPath: "data/characters.json"))) @MainActor
func stopCancelsAnInFlightMondayLoad() async throws {
    let suite = "MondayChanTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let display = MondayDisplay(id: "display-1", name: "Display", frame: .zero, refreshRate: 60)
    let controller = MondayController(
        library: try AssetLibrary(root: URL(fileURLWithPath: "data")), defaults: defaults,
        loadPerformance: { _ in
            try await Task.sleep(for: .seconds(30))
            throw CancellationError()
        }, displays: { [display] }
    )
    defer { controller.close() }
    controller.selectedDisplayIDs = [display.id]
    controller.play()
    #expect(controller.state == .loading)
    controller.stop()
    await Task.yield()
    #expect(controller.state == .idle)
}

@Test(.enabled(if: FileManager.default.fileExists(atPath: "data/characters.json"))) @MainActor
func cancelledLoadCannotClearANewerPlayAttempt() async throws {
    let suite = "MondayChanTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let display = MondayDisplay(id: "display-1", name: "Display", frame: .zero, refreshRate: 60)
    let controller = MondayController(
        library: try AssetLibrary(root: URL(fileURLWithPath: "data")), defaults: defaults,
        loadPerformance: { _ in
            try await Task.sleep(for: .seconds(30))
            throw CancellationError()
        }, displays: { [display] }
    )
    defer { controller.close() }
    controller.selectedDisplayIDs = [display.id]
    controller.play()
    controller.stop()
    controller.play()
    await Task.yield()
    #expect(controller.state == .loading)
}

@Test(.enabled(if: FileManager.default.fileExists(atPath: "data/characters.json"))) @MainActor
func invalidPersistedVolumeUsesTheDefault() throws {
    let suite = "MondayChanTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(Double.nan, forKey: "monday.volume")
    let controller = MondayController(library: try AssetLibrary(root: URL(fileURLWithPath: "data")), defaults: defaults, displays: { [] })
    defer { controller.close() }
    #expect(controller.volume == 0.8)
}

@Test(arguments: [true, false, nil] as [Bool?]) @MainActor
func automaticPlaybackRequiresKnownUnfocusedStatus(focused: Bool?) throws {
    let suite = "MondayFocusTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["one", "two"], forKey: "monday.displayIDs")
    defaults.set(MondayTrigger.sunday2345.rawValue, forKey: "monday.trigger")
    let controller = MondayController(library: try AssetLibrary(root: FileManager.default.temporaryDirectory), defaults: defaults,
                                      loadPerformance: { _ in try await Task.sleep(for: .seconds(30)); throw CancellationError() },
                                      displays: { [.init(id: "one", name: "One", frame: .zero, refreshRate: 60),
                                                   .init(id: "two", name: "Two", frame: .zero, refreshRate: 120)] },
                                      now: { Date(timeIntervalSince1970: 1789343700) },
                                      timeZone: { TimeZone(secondsFromGMT: 0)! }, focus: { focused })
    defer { controller.close() }
    #expect(controller.state == (focused == false ? .loading : .idle))
    #expect(controller.focusIsUnavailable == (focused == nil))
    controller.stop()
    controller.allowsDuringFocus = true
    #expect(controller.state == .loading)
    controller.stop()
    controller.trigger = .manual
    controller.allowsDuringFocus = false
    controller.play()
    #expect(controller.state == .loading)
}

@Test @MainActor func randomSundayTimeAndMonitorSelectionSurviveRestart() throws {
    let suite = "MondayRandomTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["one", "disconnected"], forKey: "monday.displayIDs")
    defaults.set(MondayTrigger.randomSunday.rawValue, forKey: "monday.trigger")
    let library = try AssetLibrary(root: FileManager.default.temporaryDirectory)
    let display = MondayDisplay(id: "one", name: "One", frame: .zero, refreshRate: 60)
    let sunday = ISO8601DateFormatter().date(from: "2026-09-13T23:00:00Z")!
    func makeController() -> MondayController {
        MondayController(library: library, defaults: defaults, displays: { [display] }, now: { sunday },
                         timeZone: { TimeZone(secondsFromGMT: 0)! }, focus: { false })
    }
    let first = makeController()
    let choice = try #require((defaults.dictionary(forKey: "monday.randomSeconds") as? [String: Int])?["2026-09-13"])
    #expect((0..<900).contains(choice))
    first.close()
    let restored = makeController()
    defer { restored.close() }
    #expect((defaults.dictionary(forKey: "monday.randomSeconds") as? [String: Int])?["2026-09-13"] == choice)
    #expect(restored.selectedDisplayIDs == ["one", "disconnected"])
    #expect(restored.selectedDisplays == [display])
    #expect(restored.state == .idle)
}

@Test @MainActor func oldMondaySchedulesMigrateToManualAndEmptyDisplaySelectionStaysEmpty() throws {
    let suite = "MondayMigrationTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("midnight", forKey: "monday.trigger")
    defaults.set("legacy", forKey: "monday.displayID")
    defaults.set([String](), forKey: "monday.displayIDs")
    let controller = MondayController(library: try AssetLibrary(root: FileManager.default.temporaryDirectory), defaults: defaults,
                                      focus: { false })
    defer { controller.close() }
    #expect(controller.trigger == .manual)
    #expect(controller.selectedDisplayIDs.isEmpty)
}
