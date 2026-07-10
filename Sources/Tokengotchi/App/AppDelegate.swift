import AppKit
import Combine
import SwiftUI

// MARK: - AppDelegate
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let petState = PetState()
    let providerManager = ProviderManager()

    // Menu bar controller — keeps the small template icon in the menu bar.
    private var menuBarController: MenuBarPetController?

    // Dock controller — drives the big, smooth, full-color Dock tile pet.
    private var dockController: DockPetController?

    // Pet window controller — replaces the old NSPopover with a proper window.
    private var petWindowController: PetWindowController?
    
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set a programmatic application icon as fallback.
        // This ensures the Dock never shows a blank white square —
        // it covers the brief window before the dynamic dockTile.contentView
        // takes over, and remains in the Dock's recent-apps section after quit.
        if NSApp.applicationIconImage == nil {
            NSApp.applicationIconImage = VectorPetRenderer.renderStaticIcon(size: 256)
        }

        // Build the pet window controller (shared by both menu bar and dock).
        petWindowController = PetWindowController(
            petState: petState,
            providerManager: providerManager
        )

        // Observe display mode changes
        petState.$displayMode
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.applyDisplayMode(mode)
            }
            .store(in: &cancellables)

        // Trigger wake animation (absorbed into idle as "Little Wave" clip)
        petState.setMode(.idle)
        petState.currentClipID = "idle_wave"
        petState.animationTrigger = UUID()

        // Connect default provider
        Task {
            await providerManager.connectDefault()
        }
    }
    
    // MARK: - Display Mode Handling
    private func applyDisplayMode(_ mode: PetDisplayMode) {
        let wasVisible = petWindowController?.isWindowVisible ?? false

        switch mode {
        case .both:
            NSApp.setActivationPolicy(.regular)
            setupMenuBarController()
            setupDockController()
        case .menuBar:
            NSApp.setActivationPolicy(.accessory)
            setupMenuBarController()
            destroyDockController()
        case .dock:
            NSApp.setActivationPolicy(.regular)
            setupDockController()
            destroyMenuBarController()
        }

        if wasVisible {
            DispatchQueue.main.async { [weak self] in
                self?.petWindowController?.show()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    private func setupMenuBarController() {
        if menuBarController == nil {
            menuBarController = MenuBarPetController(
                petState: petState,
                providerManager: providerManager,
                windowController: petWindowController!
            )
        }
    }
    
    private func destroyMenuBarController() {
        menuBarController = nil
    }

    private func setupDockController() {
        if dockController == nil {
            dockController = DockPetController(
                petState: petState,
                providerManager: providerManager,
                windowController: petWindowController!
            )
        }
    }
    
    private func destroyDockController() {
        dockController = nil
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
    }

    // MARK: Dock Click
    // Called by macOS when the user clicks the Dock icon and there are no
    // windows to activate. We show the pet window.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        petWindowController?.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        providerManager.disconnectAll()
    }
}
