import Foundation

// MARK: - Busy Submode
// Antigravity's transcript reports fine-grained tool phases. We keep them as
// optional submodes under `.busy` so the renderer/UI can bias clip selection.
// Other providers that can't report submodes just emit `.busy` alone.
public enum BusySubMode: String, CaseIterable, Codable, Hashable {
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
        case .idle: return "Idle"
        case .busy: return "Busy"
        case .waiting: return "Waiting"
        case .completed: return "Completed"
        case .error: return "Error"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .idle: return "pawprint.fill"
        case .busy: return "gearshape.2.fill"
        case .waiting: return "person.fill.questionmark"
        case .completed: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    public var accentColorHex: String {
        switch self {
        case .idle: return "#8E8E93"  // gray
        case .busy: return "#BF5AF2"  // purple
        case .waiting: return "#FFD60A"  // yellow
        case .completed: return "#30D158"  // green
        case .error: return "#FF453A"  // red
        }
    }
}

// MARK: - Animation Clip
// A single self-contained animation variant the renderer knows how to draw.
// Clips are tagged with the modes they may be assigned to, and (optionally)
// the busy submode they portray. A clip with `busySubMode == nil` that
// includes `.busy` in `modes` is a "general busy" clip usable for any submode.
public struct AnimationClip: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let description: String
    public let duration: TimeInterval
    public let modes: [PetMode]
    public let busySubMode: BusySubMode?

    /// Usable for any `.busy` submode (not tied to a specific tool phase).
    public var isGeneralBusy: Bool { modes.contains(.busy) && busySubMode == nil }

    public init(
        id: String, name: String, description: String, duration: TimeInterval, modes: [PetMode], busySubMode: BusySubMode?
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.duration = duration
        self.modes = modes
        self.busySubMode = busySubMode
    }
}

// MARK: - Default Fallback
extension AnimationClip {
    static func defaultClip(for mode: PetMode) -> AnimationClip {
        AnimationClip(
            id: "fallback",
            name: "Fallback",
            description: "Default fallback clip",
            duration: 1.0,
            modes: [mode],
            busySubMode: nil
        )
    }
}

