import Foundation
import Combine
import SwiftUI

// MARK: - Pet Mode (5 top-level states)
// See AnimationLibrary.swift for PetMode, BusySubstate, AnimationClip,
// AnimationLibrary, and AnimationAssignments definitions.

// MARK: - Pet State (main observable)
@MainActor
final class PetState: ObservableObject {

    // Identity
    @Published var config: PetConfig = PetConfig.default

    // Mode (current top-level state)
    @Published var mode: PetMode = .idle
    @Published var busySubstate: BusySubstate? = nil

    // Clip rotation (animation selection within a mode)
    @Published var currentClipID: String = AnimationLibrary.defaultClip(for: .idle).id
    @Published var assignments: AnimationAssignments = .default
    @Published var randomize: Bool = true

    @Published var animationTrigger: UUID = UUID()
    @Published var isSimulating: Bool = false

    // Position in menu bar overlay
    @Published var petX: CGFloat = 200
    @Published var walkDirection: CGFloat = 1  // 1 = right, -1 = left
    @Published var isNearEdge: Bool = false
    @Published var showConfetti: Bool = false

    // Vitals
    @Published var mood: Double = 75           // 0–100

    // Backwards-compatible alias used by existing UI (read-only computed)
    var currentAnimation: PetMode { mode }

    // Derived
    var moodLabel: String {
        switch mood {
        case 80...100: return "😄 Ecstatic"
        case 60..<80:  return "😊 Happy"
        case 40..<60:  return "😐 Neutral"
        case 20..<40:  return "😟 Sad"
        default:       return "😢 Miserable"
        }
    }

    var moodColor: Color {
        switch mood {
        case 70...100: return Color(hue: 0.35, saturation: 0.8, brightness: 0.85)
        case 40..<70:  return Color(hue: 0.14, saturation: 0.8, brightness: 0.9)
        default:       return Color(hue: 0.6, saturation: 0.5, brightness: 0.7)
        }
    }

    // The currently resolved clip (read by renderer + UI previews).
    var currentClip: AnimationClip {
        AnimationLibrary.clip(currentClipID)
    }

    // Clip rotation scheduling
    private var clipRotationTask: Task<Void, Never>?

    init() {
        load()
    }

    // MARK: - Mode Transition
    /// Public entry point — set a new top-level mode (and optional busy substate).
    /// Cancels any existing clip rotation and kicks off a fresh clip + dwell timer.
    func setMode(_ newMode: PetMode, substate: BusySubstate? = nil) {
        // Stop any pending clip rotation from the previous mode.
        clipRotationTask?.cancel()
        clipRotationTask = nil

        mode = newMode
        busySubstate = (newMode == .busy) ? substate : nil

        // Pick the first clip for this mode (and substate, if busy).
        let clips = assignments.clips(for: newMode, substate: busySubstate)
        let first = pickClip(from: clips)
        currentClipID = first.id
        animationTrigger = UUID()

        // Schedule transient auto-return (completed/error → idle after celebration).
        if newMode.isTransient {
            scheduleTransientReturn(for: newMode)
        }

        // Confetti on completion.
        if newMode == .completed {
            showConfetti = true
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run { self?.showConfetti = false }
            }
        }

        // Begin random clip rotation if there's more than one clip.
        scheduleNextClipRotation()
    }

    /// Convenience for callers that want to change only the busy substate
    /// without flipping the top-level mode (e.g. user_input → planner_response).
    func setBusySubstate(_ substate: BusySubstate?) {
        guard mode == .busy else {
            // If we weren't busy yet, become busy with this substate.
            setMode(.busy, substate: substate)
            return
        }
        // Already busy — if substate is unchanged, just keep going.
        if substate == busySubstate { return }
        busySubstate = substate
        // Re-pick a clip that matches the new substate (no dwell reset needed).
        let clips = assignments.clips(for: .busy, substate: busySubstate)
        currentClipID = pickClip(from: clips).id
        animationTrigger = UUID()
    }

    // MARK: - Clip Rotation
    private func scheduleNextClipRotation() {
        clipRotationTask?.cancel()
        let clips = assignments.clips(for: mode, substate: busySubstate)
        guard clips.count > 1 else { return } // nothing to rotate through

        // Dwell: 3–8 seconds, hard cut.
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
                // Only rotate if we're still in the same mode/substate.
                guard self.mode == modeCapture, self.busySubstate == substateCapture else { return }
                let next: AnimationClip
                if isRandom {
                    next = self.pickClipAvoidingCurrent(from: clipsCapture)
                } else {
                    // Sequential: find current index, advance by 1.
                    let idx = clipsCapture.firstIndex(where: { $0.id == self.currentClipID }) ?? -1
                    next = clipsCapture[(idx + 1) % clipsCapture.count]
                }
                self.currentClipID = next.id
                self.animationTrigger = UUID()
                self.scheduleNextClipRotation()
            }
        }
    }

    private func pickClip(from clips: [AnimationClip]) -> AnimationClip {
        if clips.isEmpty { return AnimationLibrary.defaultClip(for: mode) }
        return randomize ? clips.randomElement()! : clips[0]
    }

    private func pickClipAvoidingCurrent(from clips: [AnimationClip]) -> AnimationClip {
        guard clips.count > 1 else { return clips[0] }
        let pool = clips.filter { $0.id != currentClipID }
        return pool.randomElement() ?? clips[0]
    }

    // MARK: - Transient Auto-Return
    private func scheduleTransientReturn(for mode: PetMode) {
        let duration: UInt64
        switch mode {
        case .completed: duration = 3_000_000_000  // 3s
        case .error:     duration = 2_500_000_000  // 2.5s
        default:         duration = 2_000_000_000
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

    // MARK: - Mood
    func adjustMood(by delta: Double) {
        mood = max(0, min(100, mood + delta))
    }

    // MARK: - Persistence
    func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(PetSaveState(from: self)) {
            UserDefaults.standard.set(data, forKey: "tokengotchi.petState")
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: "tokengotchi.petState"),
              let save = try? JSONDecoder().decode(PetSaveState.self, from: data) else {
            return
        }
        save.apply(to: self)
    }
}

// MARK: - Save State (Codable snapshot)
private struct PetSaveState: Codable {
    var configData: Data
    var mood: Double
    var assignments: AnimationAssignments
    var randomize: Bool

    @MainActor
    init(from state: PetState) {
        configData = (try? JSONEncoder().encode(state.config)) ?? Data()
        mood = state.mood
        assignments = state.assignments
        randomize = state.randomize
    }

    @MainActor
    func apply(to state: PetState) {
        if let cfg = try? JSONDecoder().decode(PetConfig.self, from: configData) {
            state.config = cfg
        }
        state.mood = mood
        state.assignments = assignments
        state.randomize = randomize
        // Make sure the current clip reflects the loaded assignments.
        state.currentClipID = state.assignments.clips(for: state.mode, substate: state.busySubstate).first?.id
            ?? AnimationLibrary.defaultClip(for: state.mode).id
    }
}
