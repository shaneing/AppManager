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

    public var quitProxiedAppsOnExit: Bool
    public var relaunchProxiedAppsOnProxyChange: Bool

    public init(
        globalProxy: ProxyConfig = ProxyConfig(host: "127.0.0.1", port: 7890, proxyProtocol: .http, isEnabled: true),
        pinnedBundleIdentifiers: [String] = [],
        customAppConfigs: [String: AppCustomProxyConfig] = [:],
        launchAtLogin: Bool = false,
        scanUserApplications: Bool = true,
        scanSystemApplications: Bool = true,
        scanAdditionalDirectories: [String] = [],
        quitProxiedAppsOnExit: Bool = true,
        relaunchProxiedAppsOnProxyChange: Bool = true
    ) {
        self.globalProxy = globalProxy
        self.pinnedBundleIdentifiers = pinnedBundleIdentifiers
        self.customAppConfigs = customAppConfigs
        self.launchAtLogin = launchAtLogin
        self.scanUserApplications = scanUserApplications
        self.scanSystemApplications = scanSystemApplications
        self.scanAdditionalDirectories = scanAdditionalDirectories
        self.quitProxiedAppsOnExit = quitProxiedAppsOnExit
        self.relaunchProxiedAppsOnProxyChange = relaunchProxiedAppsOnProxyChange
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.globalProxy = try container.decodeIfPresent(ProxyConfig.self, forKey: .globalProxy) ?? ProxyConfig(host: "127.0.0.1", port: 7890, proxyProtocol: .http, isEnabled: true)
        self.pinnedBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .pinnedBundleIdentifiers) ?? []
        self.customAppConfigs = try container.decodeIfPresent([String: AppCustomProxyConfig].self, forKey: .customAppConfigs) ?? [:]
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.scanUserApplications = try container.decodeIfPresent(Bool.self, forKey: .scanUserApplications) ?? true
        self.scanSystemApplications = try container.decodeIfPresent(Bool.self, forKey: .scanSystemApplications) ?? true
        self.scanAdditionalDirectories = try container.decodeIfPresent([String].self, forKey: .scanAdditionalDirectories) ?? []
        self.quitProxiedAppsOnExit = try container.decodeIfPresent(Bool.self, forKey: .quitProxiedAppsOnExit) ?? true
        self.relaunchProxiedAppsOnProxyChange = try container.decodeIfPresent(Bool.self, forKey: .relaunchProxiedAppsOnProxyChange) ?? true
    }
}
