import AppKit
import Combine
import SwiftUI

// MARK: - Menu Bar Pet Controller
// Manages the NSStatusItem (click target) in the menu bar.
// Clicking the status item toggles the popover.
@MainActor
final class MenuBarPetController: NSObject, NSMenuDelegate {

    private let petState: PetState
    private let providerManager: ProviderManager
    private let screenManager = ScreenManager.shared

    // Menu bar icon
    private var statusItem: NSStatusItem!

    // Animation loop
    private var animationTimer: Timer?
    private var startTime: TimeInterval = Date().timeIntervalSinceReferenceDate

    // Pet window controller (shared with DockPetController).
    private let windowController: PetWindowController

    private var cancellables = Set<AnyCancellable>()

    init(
        petState: PetState,
        providerManager: ProviderManager,
        windowController: PetWindowController
    ) {
        self.petState = petState
        self.providerManager = providerManager
        self.windowController = windowController
        super.init()
        setupStatusItem()
        bindEvents()
        bindSystemEvents()
    }

    // MARK: Status Item
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let elapsed = Date().timeIntervalSinceReferenceDate - startTime

        var stamina: Double? = nil
        var modelName: String? = nil
        if let agy = providerManager.available.first(where: { $0.id == "antigravity" })
            as? AntigravityProvider
        {
            stamina = agy.currentStamina
            modelName = agy.activeModelName
        }

        let image = OffscreenPetRenderer.renderFrame(
            clipID: petState.currentClipID,
            pet: PetManager.shared.activePet,
            time: elapsed,
            stamina: stamina,
            modelName: modelName,
            isTemplate: true
        )
        button.image = image
    }

    // MARK: - NSMenuDelegate
    
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            menu.removeAllItems()
            
            let openItem = NSMenuItem(title: "Open Tokengotchi", action: #selector(self.openApp), keyEquivalent: "n")
            openItem.target = self
            // let font = NSFont.systemFont(ofSize: 14, weight: .bold)
            openItem.attributedTitle = NSAttributedString(string: "Open Tokengotchi")
            menu.addItem(openItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let modeLabel = self.getModeLabel()
            let infoView = NSHostingView(rootView: MenuInfoView(
                modeLabel: modeLabel,
                providerName: self.providerManager.activeProviderName
            ))
            infoView.frame = NSRect(x: 0, y: 0, width: 220, height: 44)
            
            let infoItem = NSMenuItem()
            infoItem.view = infoView
            menu.addItem(infoItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let quitItem = NSMenuItem(title: "Quit Tokengotchi", action: #selector(self.quitApp), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)
        }
    }
    
    private func getModeLabel() -> String {
        switch petState.mode {
        case .idle: return "Idle"
        case .busy:
            if let sub = petState.busySubMode {
                return "Working - \(sub.displayName)"
            }
            return "Working"
        case .waiting: return "Waiting"
        case .completed: return "Task Complete"
        case .error: return "Error"
        }
    }

    @objc private func openApp() {
        windowController.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: Bind Agent Events → Pet State
    private func bindEvents() {
        providerManager.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleAgentEvent(event)
            }
            .store(in: &cancellables)

        // Animation loop
        animationTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 24.0, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusIcon()
            }
        }
    }

    // MARK: System Events (sleep/wake)
    private func bindSystemEvents() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSystemWake()
            }
            .store(in: &cancellables)
    }

    private func handleSystemWake() {
        petState.setMode(.idle)
    }

    private func handleAgentEvent(_ event: AgentEvent) {
        guard !petState.isSimulating else { return }

        switch event {
        case .busy(let subMode):
            if petState.mode == .busy {
                petState.setBusySubMode(subMode)
            } else {
                petState.setMode(.busy, subMode: subMode)
            }
        case .completed:
            petState.setMode(.completed)
        case .failed:
            petState.setMode(.error)
        case .contextWarning:
            break
        case .started:
            if petState.mode != .busy { petState.setMode(.busy, subMode: nil) }
        case .disconnected:
            petState.setMode(.idle)
        case .idle:
            petState.setMode(.idle)
        case .waiting:
            petState.setMode(.waiting)
        }
    }
}

// MARK: - Menu Info View
struct MenuInfoView: View {
    let modeLabel: String
    let providerName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Status: \(modeLabel)")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
            
            Text("Provider: \(providerName)")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
