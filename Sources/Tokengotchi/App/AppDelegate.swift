import AppKit
import Combine
import SwiftUI

// MARK: - AppDelegate
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let petState = PetState()
    let providerManager = ProviderManager()

    // Menu bar controller
    private var menuBarController: MenuBarPetController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — pure menu-bar app
        NSApp.setActivationPolicy(.accessory)

        // Kick off menu bar
        menuBarController = MenuBarPetController(
            petState: petState,
            providerManager: providerManager
        )

        // Trigger wake animation (absorbed into idle as "Little Wave" clip)
        petState.setMode(.idle)
        petState.currentClipID = "idle_wave"
        petState.animationTrigger = UUID()

        // Connect default provider
        Task {
            await providerManager.connectDefault()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        providerManager.disconnectAll()
    }
}
