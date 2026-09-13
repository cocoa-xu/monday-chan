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
    controller?.selectedDisplayID = display.id
    controller?.trigger = .morning
    controller?.volume = 0.35
    controller?.close()
    controller = nil

    let restored = MondayController(library: library, defaults: defaults, displays: { [display] }, now: { sunday })
    defer { restored.close() }
    #expect(restored.selectedDisplayID == display.id)
    #expect(restored.trigger == .morning)
    #expect(abs(restored.volume - 0.35) < 0.001)
}

@Test(.enabled(if: FileManager.default.fileExists(atPath: "data/characters.json"))) @MainActor
func disconnectedSelectedDisplayNeverFallsBack() throws {
    let suite = "MondayChanTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("disconnected", forKey: "monday.displayID")
    defaults.set(MondayTrigger.midnight.rawValue, forKey: "monday.trigger")
    let controller = MondayController(library: try AssetLibrary(root: URL(fileURLWithPath: "data")), defaults: defaults,
                                      displays: { [MondayDisplay(id: "connected", name: "Display", frame: .zero, refreshRate: 60)] },
                                      now: { Date(timeIntervalSince1970: 0) })
    defer { controller.close() }
    controller.evaluateAutomaticPlayback(mouseMoved: true)
    #expect(controller.selectedDisplay == nil)
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
    controller.selectedDisplayID = display.id
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
    controller.selectedDisplayID = display.id
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
