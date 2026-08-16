import Foundation

/// Defines how network proxying is injected into an application.
public enum ProxyStrategy: String, Codable, CaseIterable, Sendable {
    /// Automatically selects Strategy B (flags) for Chromium browsers, and Strategy A (env vars) for Electron and native apps.
    case auto = "auto"
    /// Strategy A: Injects HTTP_PROXY, HTTPS_PROXY, ALL_PROXY into process environment variables.
    case environmentVar = "environmentVar"
    /// Strategy B: Injects `--proxy-server="<url>"` launch arguments for Chromium browsers.
    case launchFlags = "launchFlags"
    /// Strategy C: Native NEAppProxyProvider Network Extension socket-level routing.
    case networkExtension = "networkExtension"

    public var displayName: String {
        switch self {
        case .auto:
            return "Automatic (Smart Detect)"
        case .environmentVar:
            return "Strategy A (Environment Variables)"
        case .launchFlags:
            return "Strategy B (Launch Arguments)"
        case .networkExtension:
            return "Strategy C (Network Extension)"
        }
    }
}

/// Supported proxy network protocols.
public enum ProxyProtocol: String, Codable, CaseIterable, Sendable {
    case http = "http"
    case https = "https"
    case socks5 = "socks5"
}

/// Global or per-application proxy endpoint settings.
public struct ProxyConfig: Codable, Equatable, Sendable {
    public var host: String
    public var port: Int
    public var proxyProtocol: ProxyProtocol
    public var isEnabled: Bool
    public var authUsername: String?
    public var authPassword: String?

    public init(
        host: String = "127.0.0.1",
        port: Int = 7890,
        proxyProtocol: ProxyProtocol = .http,
        isEnabled: Bool = true,
        authUsername: String? = nil,
        authPassword: String? = nil
    ) {
        self.host = host
        self.port = port
        self.proxyProtocol = proxyProtocol
        self.isEnabled = isEnabled
        self.authUsername = authUsername
        self.authPassword = authPassword
    }

    /// Formatted proxy URL string (e.g. `http://127.0.0.1:7890` or `http://user:pass@127.0.0.1:7890`).
    public var urlString: String {
        let authString: String
        if let user = authUsername, !user.isEmpty, let pass = authPassword, !pass.isEmpty {
            authString = "\(user):\(pass)@"
        } else {
            authString = ""
        }
        return "\(proxyProtocol.rawValue)://\(authString)\(host):\(port)"
    }

    /// Parses a URL string (e.g. `http://127.0.0.1:7890` or `127.0.0.1:7890`) into a `ProxyConfig`.
    public static func parse(from rawString: String) -> ProxyConfig? {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: withScheme), let host = url.host else {
            return nil
        }

        let port = url.port ?? (url.scheme == "https" ? 443 : 80)
        let proto: ProxyProtocol
        switch url.scheme?.lowercased() {
        case "https":
            proto = .https
        case "socks5", "socks":
            proto = .socks5
        default:
            proto = .http
        }

        return ProxyConfig(
            host: host,
            port: port,
            proxyProtocol: proto,
            isEnabled: true,
            authUsername: url.user,
            authPassword: url.password
        )
    }
}

/// Per-application custom proxy configuration override.
public struct AppCustomProxyConfig: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case inheritGlobal = "inheritGlobal"
        case customProxy = "customProxy"
        case direct = "direct"
    }

    public var mode: Mode
    public var customProxy: ProxyConfig?
    public var strategy: ProxyStrategy
    public var extraLaunchArgs: [String]
    public var extraEnvVars: [String: String]

    public init(
        mode: Mode = .inheritGlobal,
        customProxy: ProxyConfig? = nil,
        strategy: ProxyStrategy = .auto,
        extraLaunchArgs: [String] = [],
        extraEnvVars: [String: String] = [:]
    ) {
        self.mode = mode
        self.customProxy = customProxy
        self.strategy = strategy
        self.extraLaunchArgs = extraLaunchArgs
        self.extraEnvVars = extraEnvVars
    }
}
