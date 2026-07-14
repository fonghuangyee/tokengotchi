import CoreGraphics
import Foundation

// MARK: - Keyframe Animation Models

/// Represents a color state (either solid or interpolating between two colors)
enum LayerColor: Equatable {
    case solid(String)
    case interpolated(c1: String, c2: String, progress: Double)
}

/// A sequence of keyframes targeting a specific SVG layer (by ID).
struct KeyframeTrack: Codable, Equatable {
    let targetId: String
    let keyframes: [Keyframe]
}

/// A single animation state at a specific point in time.
struct Keyframe: Codable, Equatable {
    let time: TimeInterval
    var rotate: Double = 0
    var tx: Double = 0
    var ty: Double = 0
    var sx: Double = 1
    var sy: Double = 1
    var fill: String? = nil
    var stroke: String? = nil
    var opacity: Double? = nil
    
    enum CodingKeys: String, CodingKey {
        case time, rotate, tx, ty, sx, sy, fill, stroke, opacity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(TimeInterval.self, forKey: .time)
        rotate = try container.decodeIfPresent(Double.self, forKey: .rotate) ?? 0
        tx = try container.decodeIfPresent(Double.self, forKey: .tx) ?? 0
        ty = try container.decodeIfPresent(Double.self, forKey: .ty) ?? 0
        sx = try container.decodeIfPresent(Double.self, forKey: .sx) ?? 1
        sy = try container.decodeIfPresent(Double.self, forKey: .sy) ?? 1
        fill = try container.decodeIfPresent(String.self, forKey: .fill)
        stroke = try container.decodeIfPresent(String.self, forKey: .stroke)
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity)
    }

    init(time: TimeInterval, rotate: Double = 0, tx: Double = 0, ty: Double = 0, sx: Double = 1, sy: Double = 1, fill: String? = nil, stroke: String? = nil, opacity: Double? = nil) {
        self.time = time
        self.rotate = rotate
        self.tx = tx
        self.ty = ty
        self.sx = sx
        self.sy = sy
        self.fill = fill
        self.stroke = stroke
        self.opacity = opacity
    }
}

/// Represents the evaluated transform for a layer at a specific time.
struct LayerTransform: Equatable {
    var rotate: Double = 0
    var tx: Double = 0
    var ty: Double = 0
    var sx: Double = 1
    var sy: Double = 1
    var fill: LayerColor? = nil
    var stroke: LayerColor? = nil
    var opacity: Double? = nil
    
    static let identity = LayerTransform()
}
