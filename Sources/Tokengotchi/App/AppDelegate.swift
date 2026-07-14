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

    // Widget controller — drives the borderless desktop floating pet window.
    private var widgetController: WidgetPetController?

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

        // Observe display settings changes
        petState.$showMenuBarIcon
            .combineLatest(petState.$showDockPet, petState.$showWidgetPet)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] showIcon, showDock, showWidget in
                self?.applyDisplaySettings(showIcon: showIcon, showDock: showDock, showWidget: showWidget)
            }
            .store(in: &cancellables)

        // Trigger wake animation (absorbed into idle as "Little Wave" clip)
        petState.setMode(.idle)
        petState.animationTrigger = UUID()

        // Connect default provider
        Task {
            await providerManager.connectDefault()
        }
    }
    
    // MARK: - Display Settings Handling
    private func applyDisplaySettings(showIcon: Bool, showDock: Bool, showWidget: Bool) {
        let wasVisible = petWindowController?.isWindowVisible ?? false

        // Determine activation policy: regular if Dock pet is enabled, otherwise accessory
        let targetPolicy: NSApplication.ActivationPolicy = showDock ? .regular : .accessory
        if NSApp.activationPolicy() != targetPolicy {
            NSApp.setActivationPolicy(targetPolicy)
        }

        // Manage Menu Bar controller
        if showIcon {
            setupMenuBarController()
        } else {
            destroyMenuBarController()
        }

        // Manage Dock controller
        if showDock {
            setupDockController()
        } else {
            destroyDockController()
        }

        // Manage Widget controller
        if showWidget {
            setupWidgetController()
        } else {
            destroyWidgetController()
        }

        if wasVisible {
            self.petWindowController?.show()
            NSApp.activate(ignoringOtherApps: true)
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

    private func setupWidgetController() {
        if widgetController == nil {
            widgetController = WidgetPetController(
                petState: petState,
                providerManager: providerManager
            )
        }
    }

    private func destroyWidgetController() {
        widgetController?.cleanup()
        widgetController = nil
    }

    func showMainWindow() {
        petWindowController?.show()
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
