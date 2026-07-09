import AppKit
import Combine
import SwiftUI

// MARK: - Dock Pet Controller
// Drives the macOS Dock tile with a smooth, full-color animated pet
// (VectorPetRenderer). The same PetState drives both this and the menu
// bar pet, so they animate in lockstep.
//
// Clicking the Dock icon opens the pet window (via PetWindowController).
//
// IMPORTANT: the Dock tile is a "snapshot" surface. It does NOT redraw
// automatically when its contentView changes — you must call
// `dockTile.display()` to push a new frame. So we drive animation with
// an explicit Timer that renders each frame and tells the tile to
// refresh.
@MainActor
final class DockPetController {

    private let petState: PetState
    private let providerManager: ProviderManager

    // Animation loop (~24fps).
    private var animationTimer: Timer?
    private var startTime: TimeInterval = Date().timeIntervalSinceReferenceDate

    // Pet window controller (shared with MenuBarPetController).
    private let windowController: PetWindowController

    // The image view that the Dock tile snapshots.
    private let dockImageView = NSImageView()

    init(
        petState: PetState,
        providerManager: ProviderManager,
        windowController: PetWindowController
    ) {
        self.petState = petState
        self.providerManager = providerManager
        self.windowController = windowController

        dockImageView.frame = NSRect(x: 0, y: 0, width: 128, height: 128)
        dockImageView.imageScaling = .scaleProportionallyUpOrDown

        setupDockTile()
        bindEvents()
    }

    // MARK: Dock Tile
    private func setupDockTile() {
        let tile = NSApp.dockTile
        tile.contentView = dockImageView
        renderDockFrame()
        tile.display()
    }

    // MARK: Animation
    private func bindEvents() {
        animationTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 24.0, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.renderDockFrame()
                NSApp.dockTile.display()
            }
        }
    }

    private func renderDockFrame() {
        let elapsed = Date().timeIntervalSinceReferenceDate - startTime

        var stamina: Double? = nil
        var modelName: String? = nil
        if let agy = providerManager.available.first(where: { $0.id == "antigravity" })
            as? AntigravityProvider
        {
            stamina = agy.currentStamina
            modelName = agy.activeModelName
        }

        dockImageView.image = VectorPetRenderer.renderFrame(
            clipID: petState.currentClipID,
            pet: PetManager.shared.activePet,
            time: elapsed,
            stamina: stamina,
            modelName: modelName
        )
    }

    // MARK: Dock Click → Window
    /// Called by AppDelegate.applicationShouldHandleReopen when the user
    /// clicks the Dock icon. Opens the pet window.
    func handleDockClick() {
        windowController.show()
    }
}
