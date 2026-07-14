import AppKit
import SwiftUI
import Combine

// MARK: - Widget Pet Controller
// Drives the borderless transparent NSPanel that floats on the macOS desktop.
// Syncs with the pet state animations and persists window positions.
@MainActor
final class WidgetPetController: NSObject, NSWindowDelegate {

    private let petState: PetState
    private let providerManager: ProviderManager
    private var window: NSPanel?

    // Animation loop (~24fps)
    private var startTime: TimeInterval = Date().timeIntervalSinceReferenceDate
    private var cancellables = Set<AnyCancellable>()

    init(petState: PetState, providerManager: ProviderManager) {
        self.petState = petState
        self.providerManager = providerManager
        super.init()
        setupWindow()
        bindEvents()
    }

    private func setupWindow() {
        // Find the target screen based on saved screen ID
        let targetScreen: NSScreen
        if let screenID = petState.widgetScreenID,
           let screen = NSScreen.screens.first(where: { ScreenManager.shared.screenID($0) == screenID }) {
            targetScreen = screen
        } else {
            targetScreen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen.screens[0]
        }

        let screenFrame = targetScreen.frame
        let w = max(80, petState.widgetWidth)
        let h = max(80, petState.widgetHeight)

        // Make sure it's at least partially on that screen
        var x = petState.widgetX
        var y = petState.widgetY
        if x < screenFrame.minX || x > screenFrame.maxX - 50 {
            x = screenFrame.minX + (screenFrame.width - w) / 2
        }
        if y < screenFrame.minY || y > screenFrame.maxY - 50 {
            y = screenFrame.minY + (screenFrame.height - h) / 2
        }

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.title = "Tokengotchi Widget"
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.minSize = NSSize(width: 80, height: 80)
        panel.hidesOnDeactivate = false

        // Host the SwiftUI view
        let contentView = WidgetPetView(
            petState: petState,
            providerManager: providerManager,
            window: panel
        )
        panel.contentView = NSHostingView(rootView: contentView)

        self.window = panel

        // Show window if widget should be visible
        if petState.showWidgetPet {
            show()
        }
    }

    func show() {
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func cleanup() {
        cancellables.removeAll()
        window?.close()
        window = nil
    }

    private func bindEvents() {
        // Watch for visibility changes
        petState.$showWidgetPet
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                if show {
                    self?.show()
                } else {
                    self?.hide()
                }
            }
            .store(in: &cancellables)

        // Watch for active pet updates to redraw
        PetManager.shared.$activePet
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Force display update
                self?.window?.contentView?.needsDisplay = true
            }
            .store(in: &cancellables)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        constrainWindowToScreen(window)
        let frame = window.frame
        petState.widgetX = frame.origin.x
        petState.widgetY = frame.origin.y
        if let screen = window.screen {
            petState.widgetScreenID = ScreenManager.shared.screenID(screen)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = window else { return }
        constrainWindowToScreen(window)
        let frame = window.frame
        petState.widgetWidth = frame.size.width
        petState.widgetHeight = frame.size.height
        petState.widgetX = frame.origin.x
        petState.widgetY = frame.origin.y
    }

    private func constrainWindowToScreen(_ window: NSWindow) {
        guard let screen = window.screen else { return }
        let screenFrame = screen.visibleFrame
        var frame = window.frame

        var newX = frame.origin.x
        var newY = frame.origin.y

        // Clamp width/height to screen bounds
        let maxSide = min(screenFrame.width, screenFrame.height)
        if frame.width > maxSide {
            frame.size = NSSize(width: maxSide, height: maxSide)
        }

        // Clamp x
        if newX < screenFrame.minX {
            newX = screenFrame.minX
        } else if newX + frame.width > screenFrame.maxX {
            newX = screenFrame.maxX - frame.width
        }

        // Clamp y
        if newY < screenFrame.minY {
            newY = screenFrame.minY
        } else if newY + frame.height > screenFrame.maxY {
            newY = screenFrame.maxY - frame.height
        }

        if newX != frame.origin.x || newY != frame.origin.y || frame.size.width != window.frame.width {
            frame.origin.x = newX
            frame.origin.y = newY
            window.setFrame(frame, display: true)
        }
    }
}
