import CoreGraphics
import Foundation

struct AnimationEvaluator {
    /// Evaluate all transforms for the given tracks at the specified time.
    /// Returns a dictionary of [layerId: LayerTransform].
    static func evaluate(tracks: [KeyframeTrack], duration: TimeInterval, time: TimeInterval) -> [String: LayerTransform] {
        guard duration > 0 else { return [:] }
        let loopTime = time.truncatingRemainder(dividingBy: duration)
        
        var transforms: [String: LayerTransform] = [:]
        
        for track in tracks {
            transforms[track.targetId] = evaluateTrack(track, time: loopTime, duration: duration)
        }
        
        return transforms
    }
    
    private static func evaluateTrack(_ track: KeyframeTrack, time: TimeInterval, duration: TimeInterval) -> LayerTransform {
        // Sort keyframes by time just to be safe
        let keyframes = track.keyframes.sorted { $0.time < $1.time }
        guard !keyframes.isEmpty else { return .identity }
        if keyframes.count == 1 {
            return transform(from: keyframes[0])
        }
        
        var kf1 = keyframes.last!
        var kf2 = keyframes.first!
        
        for i in 0..<(keyframes.count - 1) {
            if time >= keyframes[i].time && time < keyframes[i+1].time {
                kf1 = keyframes[i]
                kf2 = keyframes[i+1]
                break
            }
        }
        
        if time < keyframes.first!.time {
            kf1 = keyframes.last!
            kf2 = keyframes.first!
            let dt = kf2.time - (kf1.time - duration)
            if dt <= 0 { return transform(from: kf2) }
            let progress = (time - (kf1.time - duration)) / dt
            return interpolate(from: kf1, to: kf2, progress: progress)
        }
        
        if time >= keyframes.last!.time {
            kf1 = keyframes.last!
            kf2 = keyframes.first!
            let dt = (kf2.time + duration) - kf1.time
            if dt <= 0 { return transform(from: kf1) }
            let progress = (time - kf1.time) / dt
            return interpolate(from: kf1, to: kf2, progress: progress)
        }
        
        let dt = kf2.time - kf1.time
        if dt <= 0 { return transform(from: kf1) }
        let progress = (time - kf1.time) / dt
        return interpolate(from: kf1, to: kf2, progress: progress)
    }
    
    private static func transform(from kf: Keyframe) -> LayerTransform {
        return LayerTransform(
            rotate: kf.rotate, 
            tx: kf.tx, 
            ty: kf.ty, 
            sx: kf.sx, 
            sy: kf.sy,
            fill: kf.fill.map { .solid($0) },
            stroke: kf.stroke.map { .solid($0) },
            opacity: kf.opacity
        )
    }
    
    private static func interpolate(from kf1: Keyframe, to kf2: Keyframe, progress: Double) -> LayerTransform {
        let p = max(0, min(1, progress))
        // Smoothstep easing for a nicer animation
        let easeP = p * p * (3.0 - 2.0 * p)
        
        let fill: LayerColor?
        if let f1 = kf1.fill, let f2 = kf2.fill {
            fill = .interpolated(c1: f1, c2: f2, progress: easeP)
        } else {
            fill = kf1.fill.map { .solid($0) } ?? kf2.fill.map { .solid($0) }
        }
        
        let stroke: LayerColor?
        if let s1 = kf1.stroke, let s2 = kf2.stroke {
            stroke = .interpolated(c1: s1, c2: s2, progress: easeP)
        } else {
            stroke = kf1.stroke.map { .solid($0) } ?? kf2.stroke.map { .solid($0) }
        }
        
        let opacity: Double?
        if let o1 = kf1.opacity, let o2 = kf2.opacity {
            opacity = o1 + (o2 - o1) * easeP
        } else {
            opacity = kf1.opacity ?? kf2.opacity
        }
        
        return LayerTransform(
            rotate: kf1.rotate + (kf2.rotate - kf1.rotate) * easeP,
            tx: kf1.tx + (kf2.tx - kf1.tx) * easeP,
            ty: kf1.ty + (kf2.ty - kf1.ty) * easeP,
            sx: kf1.sx + (kf2.sx - kf1.sx) * easeP,
            sy: kf1.sy + (kf2.sy - kf1.sy) * easeP,
            fill: fill,
            stroke: stroke,
            opacity: opacity
        )
    }
}
