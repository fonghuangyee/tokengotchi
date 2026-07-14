import SwiftUI
import AppKit

struct WidgetPetView: View {
    @ObservedObject var petState: PetState
    @ObservedObject var providerManager: ProviderManager
    let window: NSWindow

    private var antigravity: AntigravityProvider? {
        providerManager.available.first(where: { $0.id == "antigravity" }) as? AntigravityProvider
    }

    private static let startDate = Date()

    var body: some View {
        TimelineView(.periodic(from: Self.startDate, by: 1.0 / 24.0)) { context in
            let elapsed = context.date.timeIntervalSince1970 - petState.animationStartTime
            
            let stamina: Double? = antigravity?.currentStamina
            let modelName: String? = antigravity?.activeModelName

            let image = VectorPetRenderer.renderFrame(
                clipID: petState.currentClipID,
                pet: PetManager.shared.activePet,
                time: elapsed,
                stamina: stamina,
                modelName: modelName,
                customSize: window.frame.width
            )

            ZStack {
                // Background native drag and right-click context menu view
                DragWindowView(petState: petState, window: window)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Pet render (allows hit testing to fall through to DragWindowView)
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Drag Window View
// Inserts a transparent NSView that handles:
//  - Left-click drag for window repositioning
//  - Right-click for size context menu (Small/Medium/Large)
//  - CALayer-based neon border when the window hits a screen edge
struct DragWindowView: NSViewRepresentable {
    let petState: PetState
    let window: NSWindow

    func makeNSView(context: Context) -> NSView {
        let view = DragNSView(petState: petState, window: window)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class DragNSView: NSView {
    private let petState: PetState
    private weak var hostWindow: NSWindow?

    // CALayer used for the neon glow border (no SwiftUI re-render needed)
    private let borderLayer = CALayer()
    private var wallHitResetTimer: Timer?

    init(petState: PetState, window: NSWindow) {
        self.petState = petState
        self.hostWindow = window
        super.init(frame: .zero)
        wantsLayer = true
        setupBorderLayer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Border Layer Setup

    private func setupBorderLayer() {
        borderLayer.cornerRadius = 16
        borderLayer.borderWidth = 0
        borderLayer.borderColor = NSColor.systemRed.withAlphaComponent(0.9).cgColor
        borderLayer.backgroundColor = NSColor.systemRed.withAlphaComponent(0).cgColor
        borderLayer.frame = bounds
        borderLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(borderLayer)
    }

    private func showWallHit() {
        wallHitResetTimer?.invalidate()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        borderLayer.borderWidth = 3.5
        borderLayer.backgroundColor = NSColor.systemRed.withAlphaComponent(0.12).cgColor
        CATransaction.commit()

        wallHitResetTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.hideWallHit()
        }
    }

    private func hideWallHit() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        borderLayer.borderWidth = 0
        borderLayer.backgroundColor = NSColor.systemRed.withAlphaComponent(0).cgColor
        CATransaction.commit()
    }

    // MARK: - Drag Handling

    private var initialMouseLocation: NSPoint?
    private var initialWindowOrigin: NSPoint?

    override func mouseDown(with event: NSEvent) {
        guard let window = hostWindow else { return }
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowOrigin = window.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = hostWindow,
              let startMouse = initialMouseLocation,
              let startOrigin = initialWindowOrigin else { return }

        let currentMouse = NSEvent.mouseLocation
        let dx = currentMouse.x - startMouse.x
        let dy = currentMouse.y - startMouse.y

        var frame = window.frame
        let desiredX = startOrigin.x + dx
        let desiredY = startOrigin.y + dy

        // Clamp to screen bounds and detect boundary hits
        var hitWall = false
        if let screen = window.screen ?? NSScreen.main {
            let sf = screen.visibleFrame
            let clampedX: CGFloat
            let clampedY: CGFloat

            if desiredX < sf.minX {
                clampedX = sf.minX
                hitWall = true
            } else if desiredX + frame.width > sf.maxX {
                clampedX = sf.maxX - frame.width
                hitWall = true
            } else {
                clampedX = desiredX
            }

            if desiredY < sf.minY {
                clampedY = sf.minY
                hitWall = true
            } else if desiredY + frame.height > sf.maxY {
                clampedY = sf.maxY - frame.height
                hitWall = true
            } else {
                clampedY = desiredY
            }

            frame.origin.x = clampedX
            frame.origin.y = clampedY
        } else {
            frame.origin.x = desiredX
            frame.origin.y = desiredY
        }

        window.setFrame(frame, display: true)

        if hitWall {
            showWallHit()
        }
    }

    override func mouseUp(with event: NSEvent) {
        initialMouseLocation = nil
        initialWindowOrigin = nil
    }

    // MARK: - Right-Click Context Menu (Size Presets)

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "Widget Options")

        let openItem = NSMenuItem(title: "Open Tokengotchi", action: #selector(openTokengotchi), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let smallItem = NSMenuItem(title: "Small Size", action: #selector(setSmall), keyEquivalent: "")
        smallItem.target = self
        menu.addItem(smallItem)

        let mediumItem = NSMenuItem(title: "Medium Size", action: #selector(setMedium), keyEquivalent: "")
        mediumItem.target = self
        menu.addItem(mediumItem)

        let largeItem = NSMenuItem(title: "Large Size", action: #selector(setLarge), keyEquivalent: "")
        largeItem.target = self
        menu.addItem(largeItem)

        menu.addItem(NSMenuItem.separator())

        let centerItem = NSMenuItem(title: "Snap to Center", action: #selector(centerPosition), keyEquivalent: "")
        centerItem.target = self
        menu.addItem(centerItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func screenShortDimension() -> CGFloat {
        let screen = hostWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        return min(screen.frame.width, screen.frame.height)
    }

    @objc private func openTokengotchi() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.showMainWindow()
        }
    }

    @objc private func setSmall() {
        applySize(preset: .small)
    }

    @objc private func setMedium() {
        applySize(preset: .medium)
    }

    @objc private func setLarge() {
        applySize(preset: .large)
    }

    @objc private func centerPosition() {
        guard let window = hostWindow else { return }
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.visibleFrame
        
        var frame = window.frame
        let newX = sf.minX + (sf.width - frame.width) / 2
        let newY = sf.minY + (sf.height - frame.height) / 2
        frame.origin = NSPoint(x: newX, y: newY)
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.petState.widgetX = frame.origin.x
                self?.petState.widgetY = frame.origin.y
            }
        }
    }

    private enum SizePreset {
        case small, medium, large
    }

    private func applySize(preset: SizePreset) {
        guard let window = hostWindow else { return }
        let shorterSide = screenShortDimension()
        
        let side: CGFloat
        switch preset {
        case .small:
            side = 150
        case .medium:
            side = shorterSide * 0.5
        case .large:
            side = shorterSide
        }
        
        var frame = window.frame
        // Keep center position fixed when resizing
        let cx = frame.midX
        let cy = frame.midY
        frame.size = NSSize(width: side, height: side)
        frame.origin.x = cx - side / 2
        frame.origin.y = cy - side / 2

        // Clamp to screen
        if let screen = window.screen ?? NSScreen.main {
            let sf = screen.visibleFrame
            frame.origin.x = max(sf.minX, min(frame.origin.x, sf.maxX - side))
            frame.origin.y = max(sf.minY, min(frame.origin.y, sf.maxY - side))
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.petState.widgetWidth = side
                self?.petState.widgetHeight = side
                self?.petState.widgetX = frame.origin.x
                self?.petState.widgetY = frame.origin.y
            }
        }
    }
}
