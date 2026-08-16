import Foundation
import AppKit

/// Discovers installed applications across standard macOS directories.
public final class AppDiscoveryService: @unchecked Sendable {
    public static let shared = AppDiscoveryService()

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Default directories scanned for applications on macOS.
    public var defaultScanDirectories: [URL] {
        var urls: [URL] = []

        // 1. /Applications
        urls.append(URL(fileURLWithPath: "/Applications", isDirectory: true))

        // 2. /System/Applications
        urls.append(URL(fileURLWithPath: "/System/Applications", isDirectory: true))

        // 3. ~/Applications (User applications directory)
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let userApps = homeDir.appendingPathComponent("Applications", isDirectory: true)
        urls.append(userApps)

        return urls
    }

    /// Scans all configured directories and returns discovered `AppItem`s.
    public func discoverApplications(
        scanUserApps: Bool = true,
        scanSystemApps: Bool = true,
        additionalDirectories: [String] = []
    ) -> [AppItem] {
        var searchURLs: [URL] = [URL(fileURLWithPath: "/Applications", isDirectory: true)]

        if scanSystemApps {
            searchURLs.append(URL(fileURLWithPath: "/System/Applications", isDirectory: true))
        }

        if scanUserApps {
            let userApps = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
            searchURLs.append(userApps)
        }

        for path in additionalDirectories {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if fileManager.fileExists(atPath: url.path) {
                searchURLs.append(url)
            }
        }

        var appsByBundleId: [String: AppItem] = [:]

        for baseURL in searchURLs {
            guard fileManager.fileExists(atPath: baseURL.path) else { continue }
            scanDirectory(baseURL, results: &appsByBundleId)
        }

        return Array(appsByBundleId.values).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func scanDirectory(_ directoryURL: URL, results: inout [String: AppItem]) {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "app" else { continue }

            if let item = parseAppBundle(at: fileURL) {
                // If not already discovered or user app overrides system app
                if results[item.bundleIdentifier] == nil {
                    results[item.bundleIdentifier] = item
                }
            }
        }
    }

    /// Parses an `.app` bundle directory into an `AppItem`.
    public func parseAppBundle(at bundleURL: URL) -> AppItem? {
        guard let bundle = Bundle(url: bundleURL) else { return nil }

        let bundleIdentifier = bundle.bundleIdentifier ?? bundleURL.deletingPathExtension().lastPathComponent
        guard !bundleIdentifier.isEmpty else { return nil }

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent

        let executablePath = bundle.executablePath

        let isElectronOrChromium = checkIfElectronOrChromium(bundleURL: bundleURL, bundleId: bundleIdentifier)

        return AppItem(
            name: displayName,
            bundleIdentifier: bundleIdentifier,
            bundleURL: bundleURL,
            executablePath: executablePath,
            isPinned: false,
            isRunning: false,
            pid: nil,
            customConfig: nil,
            isElectronOrChromium: isElectronOrChromium
        )
    }

    private func checkIfElectronOrChromium(bundleURL: URL, bundleId: String) -> Bool {
        let frameworksURL = bundleURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)

        let electronFramework = frameworksURL.appendingPathComponent("Electron Framework.framework")
        let cefFramework = frameworksURL.appendingPathComponent("Chromium Embedded Framework.framework")

        if fileManager.fileExists(atPath: electronFramework.path) || fileManager.fileExists(atPath: cefFramework.path) {
            return true
        }

        let lowerId = bundleId.lowercased()
        if lowerId.contains("chrome") || lowerId.contains("brave") || lowerId.contains("edge") ||
            lowerId.contains("slack") || lowerId.contains("discord") || lowerId.contains("vscode") ||
            lowerId.contains("postman") || lowerId.contains("vscodium") {
            return true
        }

        return false
    }
}
