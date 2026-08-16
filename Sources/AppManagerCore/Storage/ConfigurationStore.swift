import Foundation

/// Manages loading, saving, and observing application configuration settings to disk.
public final class ConfigurationStore: @unchecked Sendable {
    public static let shared = ConfigurationStore()

    private let fileManager: FileManager
    private let storageURL: URL
    private let queue = DispatchQueue(label: "com.appmanager.configurationstore", attributes: .concurrent)
    private var cachedSettings: AppSettings

    public init(
        fileManager: FileManager = .default,
        customStorageURL: URL? = nil
    ) {
        self.fileManager = fileManager

        if let customURL = customStorageURL {
            self.storageURL = customURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appFolder = appSupport.appendingPathComponent("AppManager", isDirectory: true)
            self.storageURL = appFolder.appendingPathComponent("config.json")
        }

        self.cachedSettings = ConfigurationStore.loadFromDisk(url: self.storageURL, fileManager: fileManager)
    }

    /// Current application settings in memory.
    public var settings: AppSettings {
        get {
            queue.sync { cachedSettings }
        }
        set {
            queue.async(flags: .barrier) {
                self.cachedSettings = newValue
                self.saveToDisk(newValue)
            }
        }
    }

    /// Thread-safe update closure.
    public func update(_ transform: (inout AppSettings) -> Void) {
        queue.sync(flags: .barrier) {
            transform(&self.cachedSettings)
            self.saveToDisk(self.cachedSettings)
        }
    }

    /// Toggle pin status for a bundle identifier.
    public func togglePin(bundleIdentifier: String) -> Bool {
        var isNowPinned = false
        update { settings in
            if let index = settings.pinnedBundleIdentifiers.firstIndex(of: bundleIdentifier) {
                settings.pinnedBundleIdentifiers.remove(at: index)
                isNowPinned = false
            } else {
                settings.pinnedBundleIdentifiers.append(bundleIdentifier)
                isNowPinned = true
            }
        }
        return isNowPinned
    }

    /// Check if a bundle identifier is pinned.
    public func isPinned(bundleIdentifier: String) -> Bool {
        queue.sync {
            cachedSettings.pinnedBundleIdentifiers.contains(bundleIdentifier)
        }
    }

    /// Set custom proxy config for an app.
    public func setCustomConfig(_ config: AppCustomProxyConfig?, for bundleIdentifier: String) {
        update { settings in
            if let config = config {
                settings.customAppConfigs[bundleIdentifier] = config
            } else {
                settings.customAppConfigs.removeValue(forKey: bundleIdentifier)
            }
        }
    }

    /// Get custom proxy config for an app.
    public func customConfig(for bundleIdentifier: String) -> AppCustomProxyConfig? {
        queue.sync {
            cachedSettings.customAppConfigs[bundleIdentifier]
        }
    }

    // MARK: - Disk I/O

    private static func loadFromDisk(url: URL, fileManager: FileManager) -> AppSettings {
        guard fileManager.fileExists(atPath: url.path) else {
            return AppSettings()
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            print("[ConfigurationStore] Warning: Failed to load config from \(url.path), using defaults: \(error)")
            return AppSettings()
        }
    }

    private func saveToDisk(_ settings: AppSettings) {
        do {
            let directory = storageURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[ConfigurationStore] Error: Failed to save config to \(storageURL.path): \(error)")
        }
    }
}
