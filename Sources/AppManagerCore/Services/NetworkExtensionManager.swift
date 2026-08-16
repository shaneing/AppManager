import Foundation
import NetworkExtension

/// Manages macOS NETransparentProxyManager / NETunnelProviderManager configuration for Strategy C socket-level proxy routing.
public final class NetworkExtensionManager: @unchecked Sendable {
    public static let shared = NetworkExtensionManager()

    private var transparentProxyManager: NETransparentProxyManager?

    public init() {}

    /// Loads the current NETransparentProxyManager preferences from the system.
    public func loadManager(completion: @escaping (Result<NETransparentProxyManager, Error>) -> Void) {
        NETransparentProxyManager.loadAllFromPreferences { managers, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            let manager = managers?.first ?? NETransparentProxyManager()
            self.transparentProxyManager = manager
            completion(.success(manager))
        }
    }

    /// Configures NETransparentProxyManager with target bundle IDs and the designated proxy server.
    public func configureProxy(
        proxy: ProxyConfig,
        targetBundleIdentifiers: [String],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        loadManager { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let manager):
                let providerProtocol = NETunnelProviderProtocol()
                providerProtocol.providerBundleIdentifier = "com.appmanager.macos.AppProxyExtension"
                providerProtocol.serverAddress = "\(proxy.host):\(proxy.port)"
                providerProtocol.providerConfiguration = [
                    "proxyHost": proxy.host,
                    "proxyPort": proxy.port,
                    "proxyProtocol": proxy.proxyProtocol.rawValue,
                    "targetBundleIds": targetBundleIdentifiers
                ]

                manager.protocolConfiguration = providerProtocol
                manager.localizedDescription = "AppManager Proxy Extension"
                manager.isEnabled = proxy.isEnabled

                manager.saveToPreferences { error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }

                    if proxy.isEnabled {
                        do {
                            try (manager.connection as? NETunnelProviderSession)?.startTunnel()
                            completion(.success(()))
                        } catch {
                            completion(.failure(error))
                        }
                    } else {
                        (manager.connection as? NETunnelProviderSession)?.stopTunnel()
                        completion(.success(()))
                    }
                }
            }
        }
    }

    /// Stops the Network Extension transparent proxy tunnel.
    public func stopProxy(completion: @escaping (Error?) -> Void) {
        guard let manager = transparentProxyManager else {
            completion(nil)
            return
        }
        (manager.connection as? NETunnelProviderSession)?.stopTunnel()
        manager.isEnabled = false
        manager.saveToPreferences(completionHandler: completion)
    }
}
