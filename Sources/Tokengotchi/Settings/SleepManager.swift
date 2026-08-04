import Foundation
import IOKit.pwr_mgt

// MARK: - Sleep Manager
// Prevents macOS from automatically sleeping (display + idle system sleep)
// using an IOKit power assertion. Persists the user's preference.
final class SleepManager: ObservableObject {

    static let shared = SleepManager()

    @Published var preventSleep: Bool {
        didSet {
            UserDefaults.standard.set(preventSleep, forKey: "tg.preventSleep")
            apply()
        }
    }

    private var assertionID: IOPMAssertionID = 0
    private var assertionActive = false

    private init() {
        preventSleep = UserDefaults.standard.bool(forKey: "tg.preventSleep")
        // Apply the persisted preference on launch.
        apply()
    }

    // MARK: - Assertion Handling
    private func apply() {
        if preventSleep {
            guard !assertionActive else { return }
            let reason = "Tokengotchi: user enabled Prevent Sleep" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertionID
            )
            assertionActive = (result == kIOReturnSuccess)
        } else {
            guard assertionActive else { return }
            IOPMAssertionRelease(assertionID)
            assertionActive = false
        }
    }
}
