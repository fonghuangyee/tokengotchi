import AppKit
import SwiftUI

// MARK: - Pet Window Controller
/// Manages both an NSPopover (for menu bar click) and an NSWindow (for dock click).
/// The popover uses the lightweight StatusPopoverView; the window uses the full PetWindowView.
@MainActor
final class PetWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var popover: NSPopover?

    let petState: PetState
    let providerManager: ProviderManager

    var isWindowVisible: Bool {
        return window?.isVisible ?? false
    }

    init(petState: PetState, providerManager: ProviderManager) {
        self.petState = petState
        self.providerManager = providerManager
        super.init()
    }

    // MARK: - Popover (Menu Bar)

    /// Toggle the popover anchored to the given button (the menu bar status item).
    func togglePopover(relativeTo button: NSStatusBarButton) {
        if let popover = popover, popover.isShown {
            popover.close()
            return
        }

        if popover == nil {
            let contentView = StatusPopoverView(
                petState: petState,
                providerManager: providerManager,
                onOpenApp: { [weak self] in
                    self?.popover?.close()
                    self?.show()
                }
            )
            let hostingController = NSHostingController(rootView: contentView)

            let p = NSPopover()
            p.contentViewController = hostingController
            p.behavior = .transient
            p.animates = true
            popover = p
        }

        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// Dismiss the popover if it is currently shown.
    func dismissPopover() {
        popover?.close()
    }

    // MARK: - Window (Dock)

    /// Show the pet window or bring it to front.
    func show() {
        // Dismiss the popover first if it's open.
        popover?.close()

        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = PetWindowView(
            petState: petState,
            providerManager: providerManager
        )

        let hostingView = NSHostingView(rootView: contentView)
        let width: CGFloat = 500
        let height: CGFloat = 620

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Tokengotchi"
        w.contentView = hostingView
        w.delegate = self
        w.center()
        w.minSize = NSSize(width: 420, height: 500)
        w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = true
        w.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1.0)

        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)

        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide instead of close so it can be re-shown.
        sender.orderOut(nil)
        return false
    }
}
