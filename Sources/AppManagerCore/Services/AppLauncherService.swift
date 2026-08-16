import Foundation
import AppKit

/// Orchestrates application launching with normal routing or multi-strategy proxy injection.
public final class AppLauncherService: @unchecked Sendable {
    public static let shared = AppLauncherService()

    private let configStore: ConfigurationStore
    private let netExtManager: NetworkExtensionManager
    private let lifecycleManager: AppLifecycleManager

    public init(
        configStore: ConfigurationStore = .shared,
        netExtManager: NetworkExtensionManager = .shared,
        lifecycleManager: AppLifecycleManager = .shared
    ) {
        self.configStore = configStore
        self.netExtManager = netExtManager
        self.lifecycleManager = lifecycleManager
    }

    /// Launches an application normally using default system routing.
    @discardableResult
    public func launchNormally(app: AppItem) -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(
            at: app.bundleURL,
            configuration: configuration
        ) { runningApp, _ in
            if let runningApp = runningApp {
                let session = ManagedAppSession(
                    bundleIdentifier: app.bundleIdentifier,
                    pid: runningApp.processIdentifier,
                    isProxied: false,
                    proxyURLString: nil,
                    strategy: nil
                )
                self.lifecycleManager.registerManagedSession(session)
            }
        }
        return true
    }

    /// Resolves the effective proxy configuration and strategy for an application.
    public func resolveEffectiveProxy(for app: AppItem) -> (proxy: ProxyConfig, strategy: ProxyStrategy)? {
        let globalSettings = configStore.settings

        if let customConfig = app.customConfig ?? configStore.customConfig(for: app.bundleIdentifier) {
            switch customConfig.mode {
            case .direct:
                return nil
            case .customProxy:
                if let custom = customConfig.customProxy, custom.isEnabled {
                    let strategy = resolveStrategy(customConfig.strategy, engineType: app.engineType)
                    return (custom, strategy)
                }
            case .inheritGlobal:
                if globalSettings.globalProxy.isEnabled {
                    let strategy = resolveStrategy(customConfig.strategy, engineType: app.engineType)
                    return (globalSettings.globalProxy, strategy)
                }
            }
        }

        if globalSettings.globalProxy.isEnabled {
            let strategy = resolveStrategy(.auto, engineType: app.engineType)
            return (globalSettings.globalProxy, strategy)
        }

        return nil
    }

    private func resolveStrategy(_ strategy: ProxyStrategy, engineType: AppEngineType) -> ProxyStrategy {
        if strategy == .auto {
            return engineType == .chromium ? .launchFlags : .environmentVar
        }
        return strategy
    }

    /// Launches an application with proxy routing.
    public func launchWithProxy(
        app: AppItem,
        overrideProxy: ProxyConfig? = nil,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let effective = resolveEffectiveProxy(for: app)
        guard let proxy = overrideProxy ?? effective?.proxy else {
            // No proxy active, launch normally
            launchNormally(app: app)
            completion?(.success(()))
            return
        }

        let strategy = effective?.strategy ?? (app.isChromium ? .launchFlags : .environmentVar)

        switch strategy {
        case .launchFlags:
            launchWithStrategyB(app: app, proxy: proxy, completion: completion)
        case .environmentVar:
            launchWithStrategyA(app: app, proxy: proxy, completion: completion)
        case .networkExtension:
            launchWithStrategyC(app: app, proxy: proxy, completion: completion)
        case .auto:
            if app.isChromium {
                launchWithStrategyB(app: app, proxy: proxy, completion: completion)
            } else {
                launchWithStrategyA(app: app, proxy: proxy, completion: completion)
            }
        }
    }

    // MARK: - Strategy A (Environment Variables)

    private func launchWithStrategyA(
        app: AppItem,
        proxy: ProxyConfig,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        let proxyUrl = proxy.urlString
        var env = ProcessInfo.processInfo.environment

        env["HTTP_PROXY"] = proxyUrl
        env["http_proxy"] = proxyUrl
        env["HTTPS_PROXY"] = proxyUrl
        env["https_proxy"] = proxyUrl
        env["ALL_PROXY"] = proxyUrl
        env["all_proxy"] = proxyUrl

        // Custom env overrides
        if let custom = configStore.customConfig(for: app.bundleIdentifier) {
            for (key, val) in custom.extraEnvVars {
                env[key] = val
            }
        }

        // If executable exists, execute directly with env
        if let execPath = app.executablePath, FileManager.default.isExecutableFile(atPath: execPath) {
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: execPath)
                process.environment = env
                if let custom = self.configStore.customConfig(for: app.bundleIdentifier) {
                    process.arguments = custom.extraLaunchArgs
                }

                do {
                    try process.run()
                    let pid = process.processIdentifier
                    let session = ManagedAppSession(
                        bundleIdentifier: app.bundleIdentifier,
                        pid: pid,
                        isProxied: true,
                        proxyURLString: proxyUrl,
                        strategy: .environmentVar
                    )
                    self.lifecycleManager.registerManagedSession(session)

                    process.terminationHandler = { [weak self] _ in
                        self?.lifecycleManager.unregisterManagedSession(bundleIdentifier: app.bundleIdentifier)
                    }

                    DispatchQueue.main.async {
                        completion?(.success(()))
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion?(.failure(error))
                    }
                }
            }
        } else {
            // Fallback: spawn via open command
            let openProcess = Process()
            openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            openProcess.arguments = ["-n", "-a", app.bundleURL.path]
            openProcess.environment = env

            do {
                try openProcess.run()
                let session = ManagedAppSession(
                    bundleIdentifier: app.bundleIdentifier,
                    pid: openProcess.processIdentifier,
                    isProxied: true,
                    proxyURLString: proxyUrl,
                    strategy: .environmentVar
                )
                self.lifecycleManager.registerManagedSession(session)
                completion?(.success(()))
            } catch {
                completion?(.failure(error))
            }
        }
    }

    // MARK: - Strategy B (Launch Arguments)

    private func launchWithStrategyB(
        app: AppItem,
        proxy: ProxyConfig,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        let proxyServerArg = "--proxy-server=\(proxy.urlString)"
        var arguments = [proxyServerArg]

        if let custom = configStore.customConfig(for: app.bundleIdentifier) {
            arguments.append(contentsOf: custom.extraLaunchArgs)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = true
        configuration.activates = true

        NSWorkspace.shared.openApplication(
            at: app.bundleURL,
            configuration: configuration
        ) { runningApp, error in
            if let error = error {
                completion?(.failure(error))
            } else {
                if let runningApp = runningApp {
                    let session = ManagedAppSession(
                        bundleIdentifier: app.bundleIdentifier,
                        pid: runningApp.processIdentifier,
                        isProxied: true,
                        proxyURLString: proxy.urlString,
                        strategy: .launchFlags
                    )
                    self.lifecycleManager.registerManagedSession(session)
                }
                completion?(.success(()))
            }
        }
    }

    // MARK: - Strategy C (Network Extension)

    private func launchWithStrategyC(
        app: AppItem,
        proxy: ProxyConfig,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        netExtManager.configureProxy(
            proxy: proxy,
            targetBundleIdentifiers: [app.bundleIdentifier]
        ) { result in
            switch result {
            case .failure(let error):
                print("[AppLauncherService] Strategy C configure error: \(error)")
                // Fallback to normal launch after error
                self.launchNormally(app: app)
                completion?(.failure(error))
            case .success:
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(
                    at: app.bundleURL,
                    configuration: configuration
                ) { runningApp, error in
                    if let runningApp = runningApp {
                        let session = ManagedAppSession(
                            bundleIdentifier: app.bundleIdentifier,
                            pid: runningApp.processIdentifier,
                            isProxied: true,
                            proxyURLString: proxy.urlString,
                            strategy: .networkExtension
                        )
                        self.lifecycleManager.registerManagedSession(session)
                    }
                    if let error = error {
                        completion?(.failure(error))
                    } else {
                        completion?(.success(()))
                    }
                }
            }
        }
    }
}
