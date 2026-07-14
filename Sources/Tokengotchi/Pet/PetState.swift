import Foundation
import Combine
import SwiftUI

// MARK: - Legacy Display Mode (kept for migration)
enum PetDisplayMode: String, Codable {
    case both = "Both"
    case menuBar = "Menu Bar Only"
    case dock = "Dock Only"
}

// MARK: - Pet State (main observable)
@MainActor
final class PetState: ObservableObject {

    // Identity (read from PetManager)
    var config: PetConfig { PetManager.shared.activePet.toPetConfig() }

    // Mode (current top-level state)
    @Published var mode: PetMode = .idle
    @Published var busySubstate: BusySubstate? = nil

    // Clip rotation (animation selection within a mode)
    @Published var currentClipID: String = ""
    @Published var randomize: Bool = true

    @Published var animationTrigger: UUID = UUID()
    @Published var animationStartTime: TimeInterval = Date().timeIntervalSince1970
    @Published var isSimulating: Bool = false

    // App Preferences
    @Published var showMenuBarIcon: Bool = true {
        didSet { save() }
    }
    @Published var showDockPet: Bool = true {
        didSet { save() }
    }
    @Published var showWidgetPet: Bool = false {
        didSet { save() }
    }

    // Widget frame geometry & screen persistence
    @Published var widgetX: CGFloat = 400 {
        didSet { save() }
    }
    @Published var widgetY: CGFloat = 400 {
        didSet { save() }
    }
    @Published var widgetWidth: CGFloat = 150 {
        didSet { save() }
    }
    @Published var widgetHeight: CGFloat = 150 {
        didSet { save() }
    }
    @Published var widgetScreenID: String? = nil {
        didSet { save() }
    }

    // Position in menu bar overlay
    @Published var petX: CGFloat = 200
    @Published var walkDirection: CGFloat = 1  // 1 = right, -1 = left
    @Published var isNearEdge: Bool = false
    @Published var showConfetti: Bool = false

    // Backwards-compatible alias used by existing UI (read-only computed)
    var currentAnimation: PetMode { mode }

    var currentClip: AnimationClip {
        if let animation = PetManager.shared.activePet.toAnimationClips().first(where: { $0.id == currentClipID }) {
            return animation
        }
        return AnimationClip.defaultClip(for: mode)
    }

    private var clipRotationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        load()
        
        // Listen to active pet changes to update clip if needed
        PetManager.shared.$activePet
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Re-trigger current mode so it picks a clip from the new pet
                self.setMode(self.mode, substate: self.busySubstate)
            }
            .store(in: &cancellables)
            
        // Initial clip
        if currentClipID.isEmpty {
            setMode(.idle)
        }
    }
    
    // MARK: - Available Clips
    private func availableClips(for targetMode: PetMode, substate: BusySubstate?) -> [AnimationClip] {
        let clips = PetManager.shared.activePet.toAnimationClips()
        let matching = clips.filter { clip in
            guard clip.modes.contains(targetMode) else { return false }
            if targetMode == .busy {
                return clip.busySubstate == substate || clip.busySubstate == nil
            }
            return true
        }
        return matching.isEmpty ? [AnimationClip.defaultClip(for: targetMode)] : matching
    }

    // MARK: - Mode Transition
    func setMode(_ newMode: PetMode, substate: BusySubstate? = nil) {
        clipRotationTask?.cancel()
        clipRotationTask = nil

        mode = newMode
        busySubstate = (newMode == .busy) ? substate : nil

        let clips = availableClips(for: newMode, substate: busySubstate)
        let first = pickClip(from: clips)
        currentClipID = first.id
        animationTrigger = UUID()
        animationStartTime = Date().timeIntervalSince1970

        var transientDurationInSeconds: TimeInterval? = nil
        if newMode == .completed {
            transientDurationInSeconds = max(first.duration, 3.0)
        } else if newMode == .error {
            transientDurationInSeconds = max(first.duration, 2.5)
        }

        if newMode.isTransient {
            scheduleTransientReturn(for: newMode, durationOverride: transientDurationInSeconds)
        }

        if newMode == .completed {
            showConfetti = true
            let durationNanoseconds = UInt64((transientDurationInSeconds ?? 3.0) * 1_000_000_000)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: durationNanoseconds)
                await MainActor.run { self?.showConfetti = false }
            }
        }

        scheduleNextClipRotation()
    }

    func setBusySubstate(_ substate: BusySubstate?) {
        guard mode == .busy else {
            setMode(.busy, substate: substate)
            return
        }
        if substate == busySubstate { return }
        busySubstate = substate
        
        let clips = availableClips(for: .busy, substate: busySubstate)
        currentClipID = pickClip(from: clips).id
        animationTrigger = UUID()
        animationStartTime = Date().timeIntervalSince1970
    }

    // MARK: - Clip Rotation
    private func scheduleNextClipRotation() {
        clipRotationTask?.cancel()
        let clips = availableClips(for: mode, substate: busySubstate)
        guard clips.count > 1 else { return }

        let dwell = Double.random(in: 3.0...8.0)
        let clipsCapture = clips
        let modeCapture = mode
        let substateCapture = busySubstate
        let isRandom = randomize

        clipRotationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(dwell * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self = self else { return }
                guard self.mode == modeCapture, self.busySubstate == substateCapture else { return }
                
                let next: AnimationClip
                if isRandom {
                    next = self.pickClipAvoidingCurrent(from: clipsCapture)
                } else {
                    let idx = clipsCapture.firstIndex(where: { $0.id == self.currentClipID }) ?? -1
                    next = clipsCapture[(idx + 1) % clipsCapture.count]
                }
                self.currentClipID = next.id
                self.animationTrigger = UUID()
                self.animationStartTime = Date().timeIntervalSince1970
                self.scheduleNextClipRotation()
            }
        }
    }

    private func pickClip(from clips: [AnimationClip]) -> AnimationClip {
        if clips.isEmpty { return AnimationClip.defaultClip(for: mode) }
        return randomize ? clips.randomElement()! : clips[0]
    }

    private func pickClipAvoidingCurrent(from clips: [AnimationClip]) -> AnimationClip {
        guard clips.count > 1 else { return clips[0] }
        let pool = clips.filter { $0.id != currentClipID }
        return pool.randomElement() ?? clips[0]
    }

    // MARK: - Transient Auto-Return
    private func scheduleTransientReturn(for mode: PetMode, durationOverride: TimeInterval? = nil) {
        let duration: UInt64
        if let override = durationOverride {
            duration = UInt64(override * 1_000_000_000)
        } else {
            switch mode {
            case .completed: duration = 3_000_000_000
            case .error:     duration = 2_500_000_000
            default:         duration = 2_000_000_000
            }
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: duration)
            await MainActor.run {
                guard let self = self else { return }
                if self.mode == mode {
                    self.setMode(.idle)
                }
            }
        }
    }

    // MARK: - Persistence
    func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(PetSaveState(from: self)) {
            UserDefaults.standard.set(data, forKey: "tokengotchi.petStateV2")
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: "tokengotchi.petStateV2"),
              let save = try? JSONDecoder().decode(PetSaveState.self, from: data) else {
            return
        }
        save.apply(to: self)
    }
}

// MARK: - Save State (Codable snapshot)
private struct PetSaveState: Codable {
    var randomize: Bool
    var displayMode: PetDisplayMode? // for migration
    
    var showMenuBarIcon: Bool?
    var showDockPet: Bool?
    var showWidgetPet: Bool?
    var widgetX: CGFloat?
    var widgetY: CGFloat?
    var widgetWidth: CGFloat?
    var widgetHeight: CGFloat?
    var widgetScreenID: String?

    @MainActor
    init(from state: PetState) {
        randomize = state.randomize
        showMenuBarIcon = state.showMenuBarIcon
        showDockPet = state.showDockPet
        showWidgetPet = state.showWidgetPet
        widgetX = state.widgetX
        widgetY = state.widgetY
        widgetWidth = state.widgetWidth
        widgetHeight = state.widgetHeight
        widgetScreenID = state.widgetScreenID
    }

    @MainActor
    func apply(to state: PetState) {
        state.randomize = randomize
        
        // Migration from legacy displayMode
        if let mode = displayMode {
            switch mode {
            case .both:
                state.showMenuBarIcon = true
                state.showDockPet = true
                state.showWidgetPet = false
            case .menuBar:
                state.showMenuBarIcon = true
                state.showDockPet = false
                state.showWidgetPet = false
            case .dock:
                state.showMenuBarIcon = false
                state.showDockPet = true
                state.showWidgetPet = false
            }
        }
        
        if let showMenuBarIcon = showMenuBarIcon {
            state.showMenuBarIcon = showMenuBarIcon
        }
        if let showDockPet = showDockPet {
            state.showDockPet = showDockPet
        }
        if let showWidgetPet = showWidgetPet {
            state.showWidgetPet = showWidgetPet
        }
        if let widgetX = widgetX {
            state.widgetX = widgetX
        }
        if let widgetY = widgetY {
            state.widgetY = widgetY
        }
        if let widgetWidth = widgetWidth {
            state.widgetWidth = widgetWidth
        }
        if let widgetHeight = widgetHeight {
            state.widgetHeight = widgetHeight
        }
        if let widgetScreenID = widgetScreenID {
            state.widgetScreenID = widgetScreenID
        }
    }
}
