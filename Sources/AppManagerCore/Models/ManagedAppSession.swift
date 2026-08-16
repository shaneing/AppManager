import Foundation

/// Represents an active runtime session for an application launched by AppManager.
public struct ManagedAppSession: Sendable, Equatable {
    public let bundleIdentifier: String
    public let pid: pid_t
    public let isProxied: Bool
    public let proxyURLString: String?
    public let strategy: ProxyStrategy?
    public let launchedAt: Date

    public init(
        bundleIdentifier: String,
        pid: pid_t,
        isProxied: Bool,
        proxyURLString: String? = nil,
        strategy: ProxyStrategy? = nil,
        launchedAt: Date = Date()
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.pid = pid
        self.isProxied = isProxied
        self.proxyURLString = proxyURLString
        self.strategy = strategy
        self.launchedAt = launchedAt
    }
}
