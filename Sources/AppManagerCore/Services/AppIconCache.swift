import Foundation
import AppKit

/// Thread-safe in-memory cache for macOS application bundle icons.
public final class AppIconCache: @unchecked Sendable {
    public static let shared = AppIconCache()

    private let cache = NSCache<NSURL, NSImage>()
    private let loaderQueue = DispatchQueue(label: "com.appmanager.iconcache.loader", qos: .userInitiated, attributes: .concurrent)

    public init(countLimit: Int = 500) {
        cache.countLimit = countLimit
    }

    /// Synchronously returns a cached icon if available.
    public func cachedIcon(for bundleURL: URL) -> NSImage? {
        return cache.object(forKey: bundleURL as NSURL)
    }

    /// Stores an icon in the memory cache.
    public func setCachedIcon(_ icon: NSImage, for bundleURL: URL) {
        cache.setObject(icon, forKey: bundleURL as NSURL)
    }

    /// Clears all cached icons.
    public func clear() {
        cache.removeAllObjects()
    }

    /// Synchronously fetches icon from cache or disk (and caches it).
    public func icon(for bundleURL: URL) -> NSImage {
        if let cached = cachedIcon(for: bundleURL) {
            return cached
        }
        let image = NSWorkspace.shared.icon(forFile: bundleURL.path)
        setCachedIcon(image, for: bundleURL)
        return image
    }

    /// Asynchronously fetches an icon on a background queue and invokes completion on the main thread.
    public func loadIcon(for bundleURL: URL, completion: @escaping @Sendable (NSImage) -> Void) {
        if let cached = cachedIcon(for: bundleURL) {
            DispatchQueue.main.async {
                completion(cached)
            }
            return
        }

        let path = bundleURL.path
        loaderQueue.async { [weak self] in
            guard let self = self else { return }
            let image = NSWorkspace.shared.icon(forFile: path)
            self.setCachedIcon(image, for: bundleURL)
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    /// Asynchronously loads an icon using Swift Concurrency.
    public func loadIcon(for bundleURL: URL) async -> NSImage {
        if let cached = cachedIcon(for: bundleURL) {
            return cached
        }

        let path = bundleURL.path
        let image: NSImage = await withCheckedContinuation { continuation in
            self.loaderQueue.async {
                let img = NSWorkspace.shared.icon(forFile: path)
                continuation.resume(returning: img)
            }
        }

        setCachedIcon(image, for: bundleURL)
        return image
    }
}
