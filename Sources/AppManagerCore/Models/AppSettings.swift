import Foundation

/// Persistent user settings and preferences.
public struct AppSettings: Codable, Equatable, Sendable {
    public var globalProxy: ProxyConfig
    public var pinnedBundleIdentifiers: [String]
    public var customAppConfigs: [String: AppCustomProxyConfig]
    public var launchAtLogin: Bool
    public var scanUserApplications: Bool
    public var scanSystemApplications: Bool
    public var scanAdditionalDirectories: [String]

    public init(
        globalProxy: ProxyConfig = ProxyConfig(host: "127.0.0.1", port: 7890, proxyProtocol: .http, isEnabled: true),
        pinnedBundleIdentifiers: [String] = [],
        customAppConfigs: [String: AppCustomProxyConfig] = [:],
        launchAtLogin: Bool = false,
        scanUserApplications: Bool = true,
        scanSystemApplications: Bool = true,
        scanAdditionalDirectories: [String] = []
    ) {
        self.globalProxy = globalProxy
        self.pinnedBundleIdentifiers = pinnedBundleIdentifiers
        self.customAppConfigs = customAppConfigs
        self.launchAtLogin = launchAtLogin
        self.scanUserApplications = scanUserApplications
        self.scanSystemApplications = scanSystemApplications
        self.scanAdditionalDirectories = scanAdditionalDirectories
    }
}
