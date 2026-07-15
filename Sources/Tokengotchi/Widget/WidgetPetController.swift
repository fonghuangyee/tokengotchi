import AppKit
import SwiftUI
import Combine
import CoreGraphics

/// A nonisolated wrapper around NSPanel that allows the CG display callback
/// (which runs on a non-main thread) to synchronously hide the window without
/// violating Swift's @MainActor isolation rules.
final class WindowHideProxy: @unchecked Sendable {
    weak var panel: NSPanel?

    /// Called from the CG callback thread via DispatchQueue.main.sync.
    /// Zeros alpha and orders the window out so it is invisible before macOS
    /// can relocate and render it on the external screen.
    func hideImmediately() {
        panel?.alphaValue = 0
        panel?.orderOut(nil)
    }

    func restoreAlpha() {
        panel?.alphaValue = 1
    }
}

// MARK: - Widget Pet Controller
// Drives the borderless transparent NSPanel that floats on the macOS desktop.
// Syncs with the pet state animations and persists window positions.
@MainActor
final class WidgetPetController: NSObject, NSWindowDelegate {

    private let petState: PetState
    private let providerManager: ProviderManager
    private var window: NSPanel?
    private var isLayoutUpdatingProgrammatically = false
    /// Nonisolated proxy — safe to pass as userInfo into the CG callback.
    let hideProxy = WindowHideProxy()

    // Animation loop (~24fps)
    private var startTime: TimeInterval = Date().timeIntervalSinceReferenceDate
    private var cancellables = Set<AnyCancellable>()

    init(petState: PetState, providerManager: ProviderManager) {
        self.petState = petState
        self.providerManager = providerManager
        super.init()
        setupWindow()
        bindEvents()
        
        let observerPointer = Unmanaged.passUnretained(hideProxy).toOpaque()
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, observerPointer)
    }

    private func setupWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 150, height: 150),
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
        panel.contentAspectRatio = NSSize(width: 1, height: 1)
        panel.hidesOnDeactivate = false

        // Host the SwiftUI view
        let contentView = WidgetPetView(
            petState: petState,
            providerManager: providerManager,
            window: panel
        )
        panel.contentView = NSHostingView(rootView: contentView)

        self.window = panel
        hideProxy.panel = panel

        // Perform initial positioning and display configuration setup
        layoutWindowOnScreenConfigurationChange()
    }

    func show() {
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    func cleanup() {
        cancellables.removeAll()
        let observerPointer = Unmanaged.passUnretained(hideProxy).toOpaque()
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, observerPointer)
        window?.close()
        window = nil
        hideProxy.panel = nil
    }

    deinit {
        let observerPointer = Unmanaged.passUnretained(hideProxy).toOpaque()
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, observerPointer)
    }

    func handleDisplayReconfigurationBeginning() {
        // Restore alpha after reconfiguration ends — the proxy already zeroed it synchronously.
        // layoutWindowOnScreenConfigurationChange() will decide visibility.
        window?.alphaValue = 1
    }

    func handleDisplayReconfigurationEnded() {
        // After reconfiguration completes, restore alpha and re-evaluate screen layout.
        window?.alphaValue = 1
    }

    private func bindEvents() {
        // Watch for visibility changes
        petState.$showWidgetPet
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                if show {
                    self?.layoutWindowOnScreenConfigurationChange()
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

        // Watch for display configuration changes
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.layoutWindowOnScreenConfigurationChange()
            }
            .store(in: &cancellables)
    }

    // MARK: - Screen Layout Management
    private func layoutWindowOnScreenConfigurationChange() {
        guard let window = window else { return }
        
        let targetScreen: NSScreen?
        let isDefaultOrMissing: Bool
        
        if let preferredID = petState.widgetScreenID {
            targetScreen = NSScreen.screens.first(where: { ScreenManager.shared.screenID($0) == preferredID })
            isDefaultOrMissing = false
        } else {
            // No preferred screen saved yet, use default screen (built-in or first available)
            targetScreen = NSScreen.screens.first(where: { $0.isBuiltIn }) ?? NSScreen.main ?? NSScreen.screens[0]
            isDefaultOrMissing = true
        }
        
        if let screen = targetScreen {
            // Preferred screen is connected and active!
            isLayoutUpdatingProgrammatically = true
            
            let w = max(80, petState.widgetWidth)
            let h = max(80, petState.widgetHeight)
            var x = petState.widgetX
            var y = petState.widgetY
            
            let screenFrame = screen.visibleFrame
            // If it's the default/missing screen, or the coordinates are completely off-screen, center it.
            if isDefaultOrMissing || x < screenFrame.minX || x > screenFrame.maxX - 50 {
                x = screenFrame.minX + (screenFrame.width - w) / 2
            }
            if isDefaultOrMissing || y < screenFrame.minY || y > screenFrame.maxY - 50 {
                y = screenFrame.minY + (screenFrame.height - h) / 2
            }
            
            let frame = NSRect(x: x, y: y, width: w, height: h)
            window.setFrame(frame, display: true)
            
            isLayoutUpdatingProgrammatically = false
            
            if isDefaultOrMissing {
                // Persist the default settings
                petState.widgetX = x
                petState.widgetY = y
                petState.widgetScreenID = ScreenManager.shared.screenID(screen)
                petState.widgetScreenIsBuiltIn = screen.isBuiltIn
            }
            
            if petState.showWidgetPet {
                show()
            }
        } else {
            // Preferred screen is disconnected!
            if petState.widgetScreenIsBuiltIn {
                // Case 1: Preferred was MacBook screen and lid is closed -> Hide the widget
                hide()
            } else {
                // Case 2: Preferred was External screen and unplugged -> Fallback to built-in screen centered.
                // We do NOT overwrite widgetScreenID so that it returns when reconnected.
                let fallbackScreen = NSScreen.screens.first(where: { $0.isBuiltIn }) ?? NSScreen.main ?? NSScreen.screens[0]
                
                isLayoutUpdatingProgrammatically = true
                
                let w = max(80, petState.widgetWidth)
                let h = max(80, petState.widgetHeight)
                let screenFrame = fallbackScreen.visibleFrame
                
                let x = screenFrame.minX + (screenFrame.width - w) / 2
                let y = screenFrame.minY + (screenFrame.height - h) / 2
                
                let frame = NSRect(x: x, y: y, width: w, height: h)
                window.setFrame(frame, display: true)
                
                isLayoutUpdatingProgrammatically = false
                
                if petState.showWidgetPet {
                    show()
                }
            }
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard let window = window else { return }
        if isLayoutUpdatingProgrammatically { return }
        
        let isDragging = DragNSView.isCurrentlyDragging
        let isLiveResizing = window.inLiveResize
        
        if isDragging || isLiveResizing {
            if !isDragging {
                constrainWindowToScreen(window)
            }
            let frame = window.frame
            petState.widgetX = frame.origin.x
            petState.widgetY = frame.origin.y
            if let screen = window.screen {
                petState.widgetScreenID = ScreenManager.shared.screenID(screen)
                petState.widgetScreenIsBuiltIn = screen.isBuiltIn
            }
        } else {
            // OS-driven relocation (e.g. screen disconnect)
            if let preferredID = petState.widgetScreenID {
                let isPreferredScreenConnected = NSScreen.screens.contains(where: { ScreenManager.shared.screenID($0) == preferredID })
                if !isPreferredScreenConnected {
                    if petState.widgetScreenIsBuiltIn {
                        hide()
                    } else {
                        layoutWindowOnScreenConfigurationChange()
                    }
                }
            }
        }
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let window = window else { return }
        if isLayoutUpdatingProgrammatically { return }
        
        if !DragNSView.isCurrentlyDragging && !window.inLiveResize {
            if let preferredID = petState.widgetScreenID {
                let isPreferredScreenConnected = NSScreen.screens.contains(where: { ScreenManager.shared.screenID($0) == preferredID })
                if !isPreferredScreenConnected {
                    if petState.widgetScreenIsBuiltIn {
                        hide()
                    } else {
                        layoutWindowOnScreenConfigurationChange()
                    }
                }
            }
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = window else { return }
        if isLayoutUpdatingProgrammatically { return }
        
        let isDragging = DragNSView.isCurrentlyDragging
        let isLiveResizing = window.inLiveResize
        
        if isDragging || isLiveResizing {
            constrainWindowToScreen(window)
            let frame = window.frame
            petState.widgetWidth = frame.size.width
            petState.widgetHeight = frame.size.height
            petState.widgetX = frame.origin.x
            petState.widgetY = frame.origin.y
            if let screen = window.screen {
                petState.widgetScreenID = ScreenManager.shared.screenID(screen)
                petState.widgetScreenIsBuiltIn = screen.isBuiltIn
            }
        }
    }

    private func constrainWindowToScreen(_ window: NSWindow) {
        guard let screen = window.screen else { return }
        let screenFrame = screen.visibleFrame
        var frame = window.frame

        var newX = frame.origin.x
        var newY = frame.origin.y

        // Clamp width/height to screen bounds
        let maxSide = min(screenFrame.width, screenFrame.height)
        window.maxSize = NSSize(width: maxSide, height: maxSide)

        if frame.width > maxSide || frame.height > maxSide {
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

        if newX != frame.origin.x || newY != frame.origin.y || frame.size.width != window.frame.width || frame.size.height != window.frame.height {
            frame.origin.x = newX
            frame.origin.y = newY
            window.setFrame(frame, display: true)
        }
    }
}

// MARK: - Display Reconfiguration Callback
// The userInfo is an Unmanaged<WindowHideProxy> — a nonisolated object that can
// be used from any thread without violating @MainActor isolation.
fileprivate func displayReconfigurationCallback(
    display: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo = userInfo else { return }
    let proxy = Unmanaged<WindowHideProxy>.fromOpaque(userInfo).takeUnretainedValue()

    if flags.contains(.beginConfigurationFlag) {
        // Block this thread synchronously until the window is hidden.
        // This guarantees orderOut happens BEFORE macOS relocates/renders the
        // window on the external screen — eliminating any visual flash.
        if Thread.isMainThread {
            proxy.hideImmediately()
        } else {
            DispatchQueue.main.sync {
                proxy.hideImmediately()
            }
        }
    } else {
        // Configuration ended — restore alpha (async is fine here, no urgency).
        DispatchQueue.main.async {
            proxy.restoreAlpha()
        }
    }
}
