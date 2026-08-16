import Foundation
import AppKit

/// Application runtime framework / engine type.
public enum AppEngineType: String, Codable, CaseIterable, Sendable {
    case native = "native"
    case electron = "electron"
    case chromium = "chromium"

    public var displayName: String {
        switch self {
        case .native:
            return "Native"
        case .electron:
            return "Electron"
        case .chromium:
            return "Chromium"
        }
    }
}

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
    public var engineType: AppEngineType
    public var isManagedByAppManager: Bool
    public var activeProxyURLString: String?
    public var activeStrategy: ProxyStrategy?

    public var isChromium: Bool {
        engineType == .chromium
    }

    public var isElectron: Bool {
        engineType == .electron
    }

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
        engineType: AppEngineType = .native,
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
        self.engineType = engineType
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
