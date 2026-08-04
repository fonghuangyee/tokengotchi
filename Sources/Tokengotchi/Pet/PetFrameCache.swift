import AppKit

/// A centralized cache for rasterized pet animation frames.
/// This drastically reduces CPU usage by preventing SVG parsing and vector
/// drawing on every screen refresh for looping animations.
final class PetFrameCache {
    static let shared = PetFrameCache()

    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 300
        cache.totalCostLimit = 100_000_000 // ~100MB
    }

    /// Retrieve a cached frame.
    func getFrame(key: String) -> NSImage? {
        return cache.object(forKey: key as NSString)
    }

    /// Store a newly rasterized frame.
    func setFrame(_ image: NSImage, key: String) {
        let w = Int(image.size.width)
        let h = Int(image.size.height)
        let scale = Int(NSScreen.main?.backingScaleFactor ?? 2)
        let cost = w * h * 4 * scale * scale
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    /// Clear the cache (e.g. on memory warning or pet switch).
    func clear() {
        cache.removeAllObjects()
    }
}
