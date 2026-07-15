import Foundation
import AppKit
import CoreGraphics

// MARK: - Screen Manager
// Resolves which NSScreen the pet overlay should appear on.
// Persists the user's preference across launches.
final class ScreenManager: ObservableObject {

    static let shared = ScreenManager()

    // nil = "Follow menu bar" (default). Non-nil = specific screen UUID.
    @Published var preferredScreenID: String? {
        didSet {
            UserDefaults.standard.set(preferredScreenID, forKey: "tg.preferredScreenID")
        }
    }

    private init() {
        preferredScreenID = UserDefaults.standard.string(forKey: "tg.preferredScreenID")
    }

    // MARK: - Resolve Target Screen
    /// Returns the screen the pet should live on, based on user preference.
    func resolveTargetScreen() -> NSScreen {
        // If user picked a specific screen, try to find it
        if let id = preferredScreenID,
           let screen = NSScreen.screens.first(where: { screenID($0) == id }) {
            return screen
        }
        // Default: whichever screen has the active menu bar
        return NSScreen.screens.first(where: { $0.hasMenuBar }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// A stable string ID for an NSScreen (based on its device UUID or display ID).
    func screenID(_ screen: NSScreen) -> String {
        if let uuid = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return uuid.stringValue
        }
        return screen.localizedName
    }

    /// All available screens with their IDs for the Settings picker.
    var availableScreens: [(id: String, name: String)] {
        NSScreen.screens.map { screen in
            (id: screenID(screen), name: screen.localizedName)
        }
    }
}

// MARK: - NSScreen Extension
extension NSScreen {
    /// True if this screen currently shows the macOS menu bar.
    var hasMenuBar: Bool {
        return self == NSScreen.screens.first
    }

    /// True if this screen is the built-in display (e.g. MacBook screen).
    var isBuiltIn: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        return CGDisplayIsBuiltin(displayID) != 0
    }
}
