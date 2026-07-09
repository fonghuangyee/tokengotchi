import CoreGraphics
import Foundation

// MARK: - Keyframe Animation Models

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
    
    enum CodingKeys: String, CodingKey {
        case time, rotate, tx, ty, sx, sy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(TimeInterval.self, forKey: .time)
        rotate = try container.decodeIfPresent(Double.self, forKey: .rotate) ?? 0
        tx = try container.decodeIfPresent(Double.self, forKey: .tx) ?? 0
        ty = try container.decodeIfPresent(Double.self, forKey: .ty) ?? 0
        sx = try container.decodeIfPresent(Double.self, forKey: .sx) ?? 1
        sy = try container.decodeIfPresent(Double.self, forKey: .sy) ?? 1
    }

    init(time: TimeInterval, rotate: Double = 0, tx: Double = 0, ty: Double = 0, sx: Double = 1, sy: Double = 1) {
        self.time = time
        self.rotate = rotate
        self.tx = tx
        self.ty = ty
        self.sx = sx
        self.sy = sy
    }
}

/// Represents the evaluated transform for a layer at a specific time.
struct LayerTransform: Equatable {
    var rotate: Double = 0
    var tx: Double = 0
    var ty: Double = 0
    var sx: Double = 1
    var sy: Double = 1
    
    static let identity = LayerTransform()
}
