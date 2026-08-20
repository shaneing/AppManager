import Foundation
import AppKit

/// Service responsible for launching macOS applications with configured proxy strategies.
public final class AppLauncherService: @unchecked Sendable {
    public static let shared = AppLauncherService()

    private let configStore: ConfigurationStore
    private let lifecycleManager: AppLifecycleManager
    private let netExtManager: NetworkExtensionManager

    public init(
        configStore: ConfigurationStore = .shared,
        lifecycleManager: AppLifecycleManager = .shared,
        netExtManager: NetworkExtensionManager = .shared
    ) {
        self.configStore = configStore
        self.lifecycleManager = lifecycleManager
        self.netExtManager = netExtManager
    }

    /// Launches an application normally using default system routing.
    @discardableResult
    public func launchNormally(
        app: AppItem,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true

        executeOpenApplication(
            app: app,
            configuration: configuration,
            sessionStrategy: nil,
            proxyURLString: nil,
            completion: completion
        )
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
            launchNormally(app: app, completion: completion)
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
        case .dynamicLibHook:
            launchWithStrategyD(app: app, proxy: proxy, completion: completion)
        case .auto:
            if app.isChromium {
                launchWithStrategyB(app: app, proxy: proxy, completion: completion)
            } else {
                launchWithStrategyA(app: app, proxy: proxy, completion: completion)
            }
        }
    }

    // MARK: - Multi-Tier Resilient Application Launcher

    private func executeOpenApplication(
        app: AppItem,
        configuration: NSWorkspace.OpenConfiguration,
        sessionStrategy: ProxyStrategy?,
        proxyURLString: String?,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        NSWorkspace.shared.openApplication(
            at: app.bundleURL,
            configuration: configuration
        ) { runningApp, error in
            if let error = error {
                print("[AppLauncherService] Tier 1 openApplication failed for \(app.name): \(error.localizedDescription). Retrying with createsNewApplicationInstance=false...")

                // Fallback Tier 2: Retry without createsNewApplicationInstance (for apps that reject multi-instance spawning)
                let retryConfig = NSWorkspace.OpenConfiguration()
                retryConfig.activates = true
                retryConfig.createsNewApplicationInstance = false
                retryConfig.environment = configuration.environment
                retryConfig.arguments = configuration.arguments

                NSWorkspace.shared.openApplication(
                    at: app.bundleURL,
                    configuration: retryConfig
                ) { retryApp, retryError in
                    if let retryError = retryError {
                        print("[AppLauncherService] Tier 2 openApplication failed for \(app.name): \(retryError.localizedDescription). Executing CLI open fallback...")

                        // Fallback Tier 3: CLI /usr/bin/open with --env and --args
                        self.executeOpenCliFallback(
                            app: app,
                            environment: configuration.environment,
                            arguments: configuration.arguments,
                            sessionStrategy: sessionStrategy,
                            proxyURLString: proxyURLString,
                            completion: completion
                        )
                    } else {
                        if let runningApp = retryApp {
                            let session = ManagedAppSession(
                                bundleIdentifier: app.bundleIdentifier,
                                pid: runningApp.processIdentifier,
                                isProxied: proxyURLString != nil,
                                proxyURLString: proxyURLString,
                                strategy: sessionStrategy
                            )
                            self.lifecycleManager.registerManagedSession(session)
                        }
                        completion?(.success(()))
                    }
                }
            } else {
                if let runningApp = runningApp {
                    let session = ManagedAppSession(
                        bundleIdentifier: app.bundleIdentifier,
                        pid: runningApp.processIdentifier,
                        isProxied: proxyURLString != nil,
                        proxyURLString: proxyURLString,
                        strategy: sessionStrategy
                    )
                    self.lifecycleManager.registerManagedSession(session)
                }
                completion?(.success(()))
            }
        }
    }

    private func executeOpenCliFallback(
        app: AppItem,
        environment: [String: String],
        arguments: [String],
        sessionStrategy: ProxyStrategy?,
        proxyURLString: String?,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        var openArgs = ["-a", app.bundleURL.path]

        // Pass environment variables using --env KEY=VALUE
        for (k, v) in environment {
            openArgs.append("--env")
            openArgs.append("\(k)=\(v)")
        }

        if !arguments.isEmpty {
            openArgs.append("--args")
            openArgs.append(contentsOf: arguments)
        }

        process.arguments = openArgs

        do {
            try process.run()
            let session = ManagedAppSession(
                bundleIdentifier: app.bundleIdentifier,
                pid: process.processIdentifier,
                isProxied: proxyURLString != nil,
                proxyURLString: proxyURLString,
                strategy: sessionStrategy
            )
            self.lifecycleManager.registerManagedSession(session)
            completion?(.success(()))
        } catch {
            print("[AppLauncherService] CLI open fallback failed: \(error)")
            // Final Fallback Tier 4: standard system open
            if NSWorkspace.shared.open(app.bundleURL) {
                completion?(.success(()))
            } else {
                completion?(.failure(error))
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

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.environment = env
        if let custom = configStore.customConfig(for: app.bundleIdentifier) {
            configuration.arguments = custom.extraLaunchArgs
        }
        configuration.createsNewApplicationInstance = true
        configuration.activates = true

        executeOpenApplication(
            app: app,
            configuration: configuration,
            sessionStrategy: .environmentVar,
            proxyURLString: proxyUrl,
            completion: completion
        )
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

        executeOpenApplication(
            app: app,
            configuration: configuration,
            sessionStrategy: .launchFlags,
            proxyURLString: proxy.urlString,
            completion: completion
        )
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
                self.launchNormally(app: app, completion: completion)
            case .success:
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                configuration.createsNewApplicationInstance = true
                self.executeOpenApplication(
                    app: app,
                    configuration: configuration,
                    sessionStrategy: .networkExtension,
                    proxyURLString: proxy.urlString,
                    completion: completion
                )
            }
        }
    }

    // MARK: - Strategy D (Dynamic Library Hook / DYLD)

    /// Locates the compiled `libAppProxyHook.dylib` from bundle resources, build directories, or system locations.
    public func locateHookLibrary() -> String? {
        let fileManager = FileManager.default

        // 1. Check in Bundle Resources (Production .app)
        if let resourcePath = Bundle.main.path(forResource: "libAppProxyHook", ofType: "dylib"),
           fileManager.fileExists(atPath: resourcePath) {
            return resourcePath
        }

        // 2. Check relative to current executable in .app bundle
        let bundleResources = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/libAppProxyHook.dylib").path
        if fileManager.fileExists(atPath: bundleResources) {
            return bundleResources
        }

        // 3. Check development / workspace build directories
        let devPaths = [
            "build/libAppProxyHook.dylib",
            ".build/debug/libAppProxyHook.dylib",
            ".build/release/libAppProxyHook.dylib",
            "/tmp/libAppProxyHook.dylib"
        ]

        for path in devPaths {
            if fileManager.fileExists(atPath: path) {
                return (path as NSString).expandingTildeInPath
            }
            // Check relative to current working directory
            let cwdPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path).path
            if fileManager.fileExists(atPath: cwdPath) {
                return cwdPath
            }
        }

        return nil
    }

    private func launchWithStrategyD(
        app: AppItem,
        proxy: ProxyConfig,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        guard let dylibPath = locateHookLibrary() else {
            print("[AppLauncherService] Strategy D error: libAppProxyHook.dylib not found, falling back to Strategy A")
            launchWithStrategyA(app: app, proxy: proxy, completion: completion)
            return
        }

        var env = ProcessInfo.processInfo.environment

        // Inject dynamic library hook
        env["DYLD_INSERT_LIBRARIES"] = dylibPath
        env["APPMANAGER_PROXY_HOST"] = proxy.host
        env["APPMANAGER_PROXY_PORT"] = String(proxy.port)
        env["APPMANAGER_PROXY_PROTO"] = proxy.proxyProtocol.rawValue
        if let user = proxy.authUsername, let pass = proxy.authPassword, !user.isEmpty, !pass.isEmpty {
            env["APPMANAGER_PROXY_AUTH"] = "\(user):\(pass)"
        }

        // Also populate standard env vars as complementary fallback
        env["HTTP_PROXY"] = proxy.urlString
        env["http_proxy"] = proxy.urlString
        env["HTTPS_PROXY"] = proxy.urlString
        env["https_proxy"] = proxy.urlString
        env["ALL_PROXY"] = proxy.urlString
        env["all_proxy"] = proxy.urlString

        // Custom env overrides
        if let custom = configStore.customConfig(for: app.bundleIdentifier) {
            for (key, val) in custom.extraEnvVars {
                env[key] = val
            }
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.environment = env
        if let custom = configStore.customConfig(for: app.bundleIdentifier) {
            configuration.arguments = custom.extraLaunchArgs
        }
        configuration.createsNewApplicationInstance = true
        configuration.activates = true

        executeOpenApplication(
            app: app,
            configuration: configuration,
            sessionStrategy: .dynamicLibHook,
            proxyURLString: proxy.urlString,
            completion: completion
        )
    }
}
