import Foundation

// MARK: - Busy Substate
// Antigravity's transcript reports fine-grained tool phases. We keep them as
// optional substates under `.busy` so the renderer/UI can bias clip selection.
// Other providers that can't report substates just emit `.busy` alone.
public enum BusySubstate: String, CaseIterable, Codable, Hashable {
    case reading, thinking, writing, searching, planning, building, running

    public var displayName: String { rawValue.capitalized }
}

// MARK: - Pet Mode (5 top-level states)
public enum PetMode: String, CaseIterable, Codable, Hashable {
    case idle, busy, waiting, completed, error

    /// Transient modes auto-return to `.idle` after a short celebration/panic.
    public var isTransient: Bool { self == .completed || self == .error }

    public var displayName: String {
        switch self {
        case .idle:      return "Idle"
        case .busy:      return "Busy"
        case .waiting:   return "Waiting"
        case .completed: return "Completed"
        case .error:     return "Error"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .idle:      return "pawprint.fill"
        case .busy:      return "gearshape.2.fill"
        case .waiting:   return "person.fill.questionmark"
        case .completed: return "checkmark.circle.fill"
        case .error:     return "exclamationmark.triangle.fill"
        }
    }

    public var accentColorHex: String {
        switch self {
        case .idle:      return "#8E8E93" // gray
        case .busy:      return "#BF5AF2" // purple
        case .waiting:   return "#FFD60A" // yellow
        case .completed: return "#30D158" // green
        case .error:     return "#FF453A" // red
        }
    }
}

// MARK: - Animation Clip
// A single self-contained animation variant the renderer knows how to draw.
// Clips are tagged with the modes they may be assigned to, and (optionally)
// the busy substate they portray. A clip with `busySubstate == nil` that
// includes `.busy` in `modes` is a "general busy" clip usable for any substate.
public struct AnimationClip: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let description: String
    public let modes: [PetMode]
    public let busySubstate: BusySubstate?

    /// Usable for any `.busy` substate (not tied to a specific tool phase).
    public var isGeneralBusy: Bool { modes.contains(.busy) && busySubstate == nil }

    public init(id: String, name: String, description: String, modes: [PetMode], busySubstate: BusySubstate?) {
        self.id = id
        self.name = name
        self.description = description
        self.modes = modes
        self.busySubstate = busySubstate
    }
}

// MARK: - Animation Library (predefined catalog)
enum AnimationLibrary {

    static let all: [AnimationClip] = [
        // ── Idle (resting — long dwells, lots of variety; wake absorbed here) ──
        AnimationClip(id: "idle_breathe",    name: "Gentle Breathing", description: "Soft squish and bounce with the occasional blink.", modes: [.idle], busySubstate: nil),
        AnimationClip(id: "idle_walker",     name: "Slow Walker",      description: "Drifts side to side with a calm, content bob.", modes: [.idle], busySubstate: nil),
        AnimationClip(id: "idle_yawn",       name: "Big Yawn",         description: "Stretches tall and lets out a yawn.", modes: [.idle], busySubstate: nil),
        AnimationClip(id: "idle_nap",        name: "Power Nap",        description: "Droopy eyes with floating Zzz bubbles.", modes: [.idle], busySubstate: nil),
        AnimationClip(id: "idle_wave",       name: "Little Wave",      description: "Stretches up and waves — a friendly greeting (was wake).", modes: [.idle], busySubstate: nil),
        AnimationClip(id: "idle_lookaround", name: "Looking Around",   description: "Tilts its head and scans the room.", modes: [.idle], busySubstate: nil),
        AnimationClip(id: "idle_stretch",    name: "Morning Stretch",  description: "Reaches up tall with wide, awake eyes.", modes: [.idle], busySubstate: nil),

        // ── Busy (working) ──
        // thinking
        AnimationClip(id: "busy_think_pace",  name: "Think Pace",   description: "Pacing tilt with animated thought dots.", modes: [.busy], busySubstate: .thinking),
        AnimationClip(id: "busy_think_ponder", name: "Ponder",      description: "Slow tilt while scanning pupils side to side.", modes: [.busy], busySubstate: .thinking),
        // reading
        AnimationClip(id: "busy_read_scan",   name: "Read Scan",    description: "Glasses on, pupils scan left and right across the page.", modes: [.busy], busySubstate: .reading),
        AnimationClip(id: "busy_read_deep",   name: "Deep Read",    description: "Slow focused bob with glasses and a squint.", modes: [.busy], busySubstate: .reading),
        // writing
        AnimationClip(id: "busy_write_type",  name: "Type Away",    description: "Keyboard under hand, rhythmic typing bob.", modes: [.busy], busySubstate: .writing),
        AnimationClip(id: "busy_write_burst", name: "Writing Burst", description: "Rapid bob with a serious squint — in the zone.", modes: [.busy], busySubstate: .writing),
        // searching
        AnimationClip(id: "busy_search_lean", name: "Search Lean",  description: "Magnifying glass out, gentle lean left and right.", modes: [.busy], busySubstate: .searching),
        AnimationClip(id: "busy_search_sweep", name: "Sweep Search", description: "Wide-eyed side-to-side sweep looking for clues.", modes: [.busy], busySubstate: .searching),
        // planning
        AnimationClip(id: "busy_plan_lightbulb", name: "Lightbulb", description: "Tilt oscillation with a pulsing exclamation mark.", modes: [.busy], busySubstate: .planning),
        AnimationClip(id: "busy_plan_dots",   name: "Plan Dots",    description: "Wide eyes with animated planning dots overhead.", modes: [.busy], busySubstate: .planning),
        // building
        AnimationClip(id: "busy_build_sweat", name: "Hard Hat",     description: "Rapid squish-bounce wearing a sweatband.", modes: [.busy], busySubstate: .building),
        // running
        AnimationClip(id: "busy_run_dash",    name: "Dash",         description: "Leans forward with speed lines and sweat.", modes: [.busy], busySubstate: .running),
        AnimationClip(id: "busy_run_sprint",  name: "Sprint",       description: "Rapid bounce, wide eyes, and sweat drops.", modes: [.busy], busySubstate: .running),

        // ── Waiting (needs attention) ──
        AnimationClip(id: "waiting_tap",  name: "Foot Tap",   description: "Taps its foot with a glowing question mark.", modes: [.waiting], busySubstate: nil),
        AnimationClip(id: "waiting_look", name: "Expectant",  description: "Wide eyes and a gentle expectant bob.", modes: [.waiting], busySubstate: nil),
        AnimationClip(id: "waiting_blink", name: "Slow Blink", description: "Slow blinks with a tilted, patient head.", modes: [.waiting], busySubstate: nil),

        // ── Completed (transient success) ──
        AnimationClip(id: "done_jump", name: "Happy Jump", description: "High jump with happy eyes and confetti.", modes: [.completed], busySubstate: nil),
        AnimationClip(id: "done_spin", name: "Spin Hop",   description: "A little spin hop with happy eyes.", modes: [.completed], busySubstate: nil),

        // ── Error (transient failure) ──
        AnimationClip(id: "error_shake", name: "Panic Shake", description: "Glitchy side-to-side shake with dead eyes.", modes: [.error], busySubstate: nil),
        AnimationClip(id: "error_trip",  name: "Trip",        description: "Wobbles forward with sweat drops.", modes: [.error], busySubstate: nil),
    ]

    static func clips(for mode: PetMode) -> [AnimationClip] {
        all.filter { $0.modes.contains(mode) }
    }

    static func clip(_ id: String) -> AnimationClip {
        all.first { $0.id == id } ?? all[0]
    }

    /// Default clip used for a mode when the user has no assignment yet.
    static func defaultClip(for mode: PetMode) -> AnimationClip {
        switch mode {
        case .idle:      return clip("idle_breathe")
        case .busy:      return clip("busy_think_pace")
        case .waiting:   return clip("waiting_tap")
        case .completed: return clip("done_jump")
        case .error:     return clip("error_shake")
        }
    }
}

// MARK: - Animation Assignments (persisted user config)
// Maps each PetMode to the ordered list of clip IDs the user wants. At runtime
// we randomly rotate through the list (3–8s, hard cuts) so the pet feels alive.
struct AnimationAssignments: Codable, Equatable {
    public var clipsByMode: [PetMode: [String]]
    public var randomize: Bool

    static let `default` = AnimationAssignments(
        clipsByMode: [
            .idle:      defaultIDs(.idle),
            .busy:      defaultIDs(.busy),
            .waiting:   defaultIDs(.waiting),
            .completed: defaultIDs(.completed),
            .error:     defaultIDs(.error),
        ],
        randomize: true
    )

    static func defaultIDs(_ mode: PetMode) -> [String] {
        switch mode {
        case .idle:
            return ["idle_breathe", "idle_walker", "idle_yawn", "idle_nap", "idle_wave", "idle_lookaround", "idle_stretch"]
        case .busy:
            // One clip per substate → the active substate biases selection.
            return ["busy_think_pace", "busy_read_scan", "busy_write_type", "busy_search_lean", "busy_plan_lightbulb", "busy_build_sweat", "busy_run_dash"]
        case .waiting:
            return ["waiting_tap"]
        case .completed:
            return ["done_jump"]
        case .error:
            return ["error_shake"]
        }
    }

    /// Safe accessor — never returns empty (falls back to the default clip).
    func ids(for mode: PetMode) -> [String] {
        if let list = clipsByMode[mode], !list.isEmpty { return list }
        return [AnimationLibrary.defaultClip(for: mode).id]
    }

    /// Resolved clips for a mode, optionally filtered by a busy substate.
    /// For `.busy` with a substate: prefer substate-specific + general clips.
    func clips(for mode: PetMode, substate: BusySubstate? = nil) -> [AnimationClip] {
        let ids = ids(for: mode)
        var resolved = ids.compactMap { id in AnimationLibrary.all.first { $0.id == id } }

        if mode == .busy, let sub = substate {
            let filtered = resolved.filter { $0.busySubstate == sub || $0.isGeneralBusy }
            if !filtered.isEmpty { resolved = filtered }
        }
        // Guarantee non-empty (defensive — ids(for:) already ensures this).
        if resolved.isEmpty { resolved = [AnimationLibrary.defaultClip(for: mode)] }
        return resolved
    }

    /// Remove a clip from a mode unless it's the last one (delete protection).
    mutating func remove(_ clipID: String, from mode: PetMode) {
        guard var list = clipsByMode[mode], list.count > 1 else { return }
        list.removeAll { $0 == clipID }
        clipsByMode[mode] = list
    }

    mutating func add(_ clipID: String, to mode: PetMode) {
        var list = clipsByMode[mode] ?? []
        if !list.contains(clipID) { list.append(clipID) }
        clipsByMode[mode] = list
    }

    mutating func reset(_ mode: PetMode) {
        clipsByMode[mode] = Self.defaultIDs(mode)
    }

    mutating func resetAll() {
        self = .default
    }
}
