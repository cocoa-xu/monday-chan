import AppKit

struct MondayDisplay: Identifiable, Equatable {
    let id: String
    let name: String
    let frame: CGRect
    let refreshRate: Int

    @MainActor static var connected: [MondayDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
            return MondayDisplay(id: CFUUIDCreateString(nil, uuid) as String, name: screen.localizedName,
                                 frame: screen.frame, refreshRate: screen.maximumFramesPerSecond)
        }
    }
}
