import AppKit
import SwiftUI
import Combine

// MARK: - Menu Bar Pet Controller
// Manages the NSStatusItem (click target) AND a borderless NSWindow
// that overlays the entire menu bar for the walking pet sprite.
@MainActor
final class MenuBarPetController {

    private let petState: PetState
    private let providerManager: ProviderManager
    private let screenManager = ScreenManager.shared

    // Menu bar icon
    private var statusItem: NSStatusItem!

    // Animation loop
    private var animationTimer: Timer?
    private var startTime: TimeInterval = Date().timeIntervalSinceReferenceDate

    // Popover for dashboard
    private var popover: NSPopover!

    private var cancellables = Set<AnyCancellable>()

    init(petState: PetState, providerManager: ProviderManager) {
        self.petState = petState
        self.providerManager = providerManager
        setupStatusItem()
        setupPopover()
        bindEvents()
        bindSystemEvents()
    }

    // MARK: Status Item
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.action = #selector(togglePopover)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusIcon(.idle)
    }

    private func updateStatusIcon(_ state: PetMode) {
        guard let button = statusItem.button else { return }

        let now = Date().timeIntervalSinceReferenceDate
        let elapsed = now - startTime

        // Find antigravity provider to get stamina and model name
        var stamina: Double? = nil
        var modelName: String? = nil
        if let agy = providerManager.available.first(where: { $0.id == "antigravity" }) as? AntigravityProvider {
            stamina = agy.currentStamina
            modelName = agy.activeModelName
        }

        // Generate the pixel-art blob natively in CoreGraphics.
        // We render the currently-selected clip for the active mode.
        let image = OffscreenPetRenderer.renderFrame(
            clipID: petState.currentClipID,
            config: petState.config,
            time: elapsed,
            stamina: stamina,
            modelName: modelName
        )

        button.image = image
    }

    // MARK: Popover
    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = CGSize(width: 340, height: 520)
        popover.behavior = .transient
        popover.animates = true

        let dashboard = PetDashboardView(
            petState: petState,
            providerManager: providerManager
        )
        popover.contentViewController = NSHostingController(rootView: dashboard)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        }
    }

    // MARK: Bind Agent Events → Pet State
    private func bindEvents() {
        providerManager.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleAgentEvent(event)
            }
            .store(in: &cancellables)

        // Start animation loop
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.updateStatusIcon(self.petState.mode)
            }
        }
    }

    // MARK: System Events (sleep/wake + screen changes)
    private func bindSystemEvents() {
        // Wake from sleep → wave
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSystemWake()
            }
            .store(in: &cancellables)
    }

    private func handleSystemWake() {
        // `wake` was absorbed into idle as the "Little Wave" clip. We set idle
        // and briefly pin the wave clip for a friendly wake-up greeting;
        // normal idle rotation resumes after ~2s.
        petState.setMode(.idle)
        let previousClip = petState.currentClipID
        petState.currentClipID = "idle_wave"
        petState.animationTrigger = UUID()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self = self else { return }
            if self.petState.currentClipID == "idle_wave" && self.petState.mode == .idle {
                self.petState.currentClipID = previousClip
                self.petState.animationTrigger = UUID()
            }
        }
    }

    private func handleAgentEvent(_ event: AgentEvent) {
        // If simulating animations, ignore automated real-time provider events
        guard !petState.isSimulating else { return }

        switch event {
        case .busy(let substate):
            // Entering busy (or switching substate within busy).
            if petState.mode == .busy {
                petState.setBusySubstate(substate)
            } else {
                petState.setMode(.busy, substate: substate)
            }
        case .completed:
            petState.setMode(.completed)
            petState.adjustMood(by: 10)
        case .failed:
            petState.setMode(.error)
            petState.adjustMood(by: -10)
        case .contextWarning:
            // Mood-only: never overwrite the active working clip.
            petState.adjustMood(by: -5)
        case .started:
            // First sign of life for a turn → go busy (no specific substate yet).
            if petState.mode != .busy { petState.setMode(.busy, substate: nil) }
        case .disconnected:
            petState.setMode(.idle)
        case .idle:
            petState.setMode(.idle)
        case .waiting:
            petState.setMode(.waiting)
        }
    }
}
