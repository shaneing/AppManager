import Foundation
import AppKit

/// Represents an application on macOS discovered from the filesystem or running processes.
public struct AppItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let bundleIdentifier: String
    public let bundleURL: URL
    public let executablePath: String?
    public var isPinned: Bool
    public var isRunning: Bool
    public var pid: pid_t?
    public var customConfig: AppCustomProxyConfig?
    public var isElectronOrChromium: Bool
    public var isManagedByAppManager: Bool
    public var activeProxyURLString: String?
    public var activeStrategy: ProxyStrategy?

    public init(
        id: String? = nil,
        name: String,
        bundleIdentifier: String,
        bundleURL: URL,
        executablePath: String? = nil,
        isPinned: Bool = false,
        isRunning: Bool = false,
        pid: pid_t? = nil,
        customConfig: AppCustomProxyConfig? = nil,
        isElectronOrChromium: Bool = false,
        isManagedByAppManager: Bool = false,
        activeProxyURLString: String? = nil,
        activeStrategy: ProxyStrategy? = nil
    ) {
        self.id = id ?? bundleIdentifier
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.executablePath = executablePath
        self.isPinned = isPinned
        self.isRunning = isRunning
        self.pid = pid
        self.customConfig = customConfig
        self.isElectronOrChromium = isElectronOrChromium
        self.isManagedByAppManager = isManagedByAppManager
        self.activeProxyURLString = activeProxyURLString
        self.activeStrategy = activeStrategy
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.isRunning == rhs.isRunning &&
        lhs.pid == rhs.pid &&
        lhs.isPinned == rhs.isPinned &&
        lhs.customConfig == rhs.customConfig &&
        lhs.isManagedByAppManager == rhs.isManagedByAppManager &&
        lhs.activeProxyURLString == rhs.activeProxyURLString &&
        lhs.activeStrategy == rhs.activeStrategy
    }
}
