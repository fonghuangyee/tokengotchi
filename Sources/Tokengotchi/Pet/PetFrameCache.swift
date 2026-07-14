import AppKit

/// A centralized cache for rasterized pet animation frames.
/// This drastically reduces CPU usage by preventing SVG parsing and vector
/// drawing on every screen refresh for looping animations.
final class PetFrameCache {
    static let shared = PetFrameCache()

    private let cache = NSCache<NSString, NSImage>()

    init() {
        // A generous limit to hold several animations in memory.
        // Rasterized 128x128 or 256x256 NSImages are relatively small.
        cache.countLimit = 1000
    }

    /// Retrieve a cached frame.
    func getFrame(key: String) -> NSImage? {
        return cache.object(forKey: key as NSString)
    }

    /// Store a newly rasterized frame.
    func setFrame(_ image: NSImage, key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    /// Clear the cache (e.g. on memory warning or pet switch).
    func clear() {
        cache.removeAllObjects()
    }
}
