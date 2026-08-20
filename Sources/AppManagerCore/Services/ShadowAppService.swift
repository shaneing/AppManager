import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Metadata tracking for user-space shadow app copies.
public struct ShadowMetadata: Codable, Equatable, Sendable {
    public let bundleIdentifier: String
    public let sourceBundlePath: String
    public let sourceModificationTimestamp: Double
    public let sourceVersion: String?
    public let shadowCreatedAt: Date

    public init(
        bundleIdentifier: String,
        sourceBundlePath: String,
        sourceModificationTimestamp: Double,
        sourceVersion: String?,
        shadowCreatedAt: Date = Date()
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.sourceBundlePath = sourceBundlePath
        self.sourceModificationTimestamp = sourceModificationTimestamp
        self.sourceVersion = sourceVersion
        self.shadowCreatedAt = shadowCreatedAt
    }
}

public enum ShadowAppError: LocalizedError {
    case sourceNotFound(String)
    case cloningFailed(String)
    case reSigningFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sourceNotFound(let path):
            return "Source application bundle not found at: \(path)"
        case .cloningFailed(let msg):
            return "Failed to clone application bundle to shadow storage: \(msg)"
        case .reSigningFailed(let msg):
            return "Failed to re-sign shadow application copy: \(msg)"
        }
    }
}

/// Service to manage non-destructive, user-space shadow application copies for dynamic library injection.
public final class ShadowAppService: Sendable {
    public static let shared = ShadowAppService()

    public let baseShadowsDirectory: URL

    public init(baseShadowsDirectory: URL? = nil) {
        if let customDir = baseShadowsDirectory {
            self.baseShadowsDirectory = customDir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseShadowsDirectory = appSupport
                .appendingPathComponent("AppManager", isDirectory: true)
                .appendingPathComponent("Shadows", isDirectory: true)
        }
    }

    /// Resolves the storage folder URL for a specific app's shadow copy.
    public func shadowFolderURL(for bundleIdentifier: String) -> URL {
        return baseShadowsDirectory.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    /// Resolves the `.app` bundle URL for a specific app inside its shadow folder.
    public func shadowAppURL(for app: AppItem) -> URL {
        let folder = shadowFolderURL(for: app.bundleIdentifier)
        let appBundleName = app.bundleURL.lastPathComponent
        return folder.appendingPathComponent(appBundleName, isDirectory: true)
    }

    private func metadataFileURL(for bundleIdentifier: String) -> URL {
        return shadowFolderURL(for: bundleIdentifier).appendingPathComponent("shadow_metadata.json")
    }

    /// Checks if a valid, up-to-date shadow copy exists for the given application.
    public func isShadowValid(for app: AppItem) -> Bool {
        let shadowURL = shadowAppURL(for: app)
        guard FileManager.default.fileExists(atPath: shadowURL.path) else {
            return false
        }

        let metaURL = metadataFileURL(for: app.bundleIdentifier)
        guard let data = try? Data(contentsOf: metaURL),
              let metadata = try? JSONDecoder().decode(ShadowMetadata.self, from: data) else {
            return false
        }

        guard metadata.sourceBundlePath == app.bundleURL.path else {
            return false
        }

        // Verify source modification time and version
        let sourceMTime = sourceModificationTimestamp(for: app.bundleURL)
        let sourceVer = sourceVersionString(for: app.bundleURL)

        if abs(sourceMTime - metadata.sourceModificationTimestamp) > 1.0 {
            return false
        }

        if sourceVer != metadata.sourceVersion {
            return false
        }

        return true
    }

    /// Returns the valid shadow copy URL, preparing, cloning, and re-signing if necessary.
    public func getOrPrepareShadowApp(for app: AppItem) async throws -> URL {
        guard FileManager.default.fileExists(atPath: app.bundleURL.path) else {
            throw ShadowAppError.sourceNotFound(app.bundleURL.path)
        }

        let shadowURL = shadowAppURL(for: app)
        if isShadowValid(for: app) {
            return shadowURL
        }

        let folder = shadowFolderURL(for: app.bundleIdentifier)

        // Clean up previous stale shadow if exists
        if FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.removeItem(at: folder)
        }

        // Ensure parent directory exists
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Clone source app bundle into shadow folder using APFS clone with fallback
        try cloneBundle(source: app.bundleURL, destination: shadowURL)

        // Perform ad-hoc re-signing on the user-space shadow copy
        do {
            try await CodeSigningService.shared.performAdHocResign(bundleURL: shadowURL)
        } catch {
            // If resigning fails, clean up shadow copy and throw
            try? FileManager.default.removeItem(at: folder)
            throw ShadowAppError.reSigningFailed(error.localizedDescription)
        }

        // Save metadata
        let metadata = ShadowMetadata(
            bundleIdentifier: app.bundleIdentifier,
            sourceBundlePath: app.bundleURL.path,
            sourceModificationTimestamp: sourceModificationTimestamp(for: app.bundleURL),
            sourceVersion: sourceVersionString(for: app.bundleURL)
        )

        if let encoded = try? JSONEncoder().encode(metadata) {
            try? encoded.write(to: metadataFileURL(for: app.bundleIdentifier))
        }

        return shadowURL
    }

    /// Clones an app bundle using APFS copy-on-write `copyfile` / `clonefile`, falling back to `FileManager.copyItem`.
    public func cloneBundle(source: URL, destination: URL) throws {
        // Ensure destination does not exist before cloning
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        #if canImport(Darwin)
        let srcPath = (source.path as NSString).fileSystemRepresentation
        let dstPath = (destination.path as NSString).fileSystemRepresentation

        // Try clonefile first for APFS instant copy-on-write
        if clonefile(srcPath, dstPath, 0) == 0 {
            return
        }

        // Try copyfile with COPYFILE_CLONE fallback
        if copyfile(srcPath, dstPath, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_CLONE)) == 0 {
            return
        }
        #endif

        // Standard fallback copy
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw ShadowAppError.cloningFailed(error.localizedDescription)
        }
    }

    /// Cleans up shadow copy for a specific application.
    public func clearShadow(for bundleIdentifier: String) {
        let folder = shadowFolderURL(for: bundleIdentifier)
        try? FileManager.default.removeItem(at: folder)
    }

    /// Cleans up all shadow copies.
    public func clearAllShadows() {
        try? FileManager.default.removeItem(at: baseShadowsDirectory)
    }

    private func sourceModificationTimestamp(for bundleURL: URL) -> Double {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: bundleURL.path),
           let date = attrs[.modificationDate] as? Date {
            return date.timeIntervalSince1970
        }
        return 0
    }

    private func sourceVersionString(for bundleURL: URL) -> String? {
        if let bundle = Bundle(url: bundleURL) {
            return (bundle.infoDictionary?["CFBundleShortVersionString"] as? String)
                ?? (bundle.infoDictionary?["CFBundleVersion"] as? String)
        }
        return nil
    }
}
