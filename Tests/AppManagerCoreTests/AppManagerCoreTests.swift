import XCTest
import Combine
@testable import AppManagerCore

final class AppManagerCoreTests: XCTestCase {
    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - ProxyConfig Tests

    func testProxyConfigUrlFormatting() {
        let config = ProxyConfig(host: "127.0.0.1", port: 7890, proxyProtocol: .http)
        XCTAssertEqual(config.urlString, "http://127.0.0.1:7890")

        let configWithAuth = ProxyConfig(
            host: "proxy.example.com",
            port: 8080,
            proxyProtocol: .socks5,
            authUsername: "admin",
            authPassword: "secretpassword"
        )
        XCTAssertEqual(configWithAuth.urlString, "socks5://admin:secretpassword@proxy.example.com:8080")
    }

    func testProxyConfigParsing() {
        let parsed = ProxyConfig.parse(from: "http://127.0.0.1:7890")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.host, "127.0.0.1")
        XCTAssertEqual(parsed?.port, 7890)
        XCTAssertEqual(parsed?.proxyProtocol, .http)

        let parsedNoScheme = ProxyConfig.parse(from: " 127.0.0.1:7890 \n")
        XCTAssertNotNil(parsedNoScheme)
        XCTAssertEqual(parsedNoScheme?.host, "127.0.0.1")
        XCTAssertEqual(parsedNoScheme?.port, 7890)
        XCTAssertEqual(parsedNoScheme?.proxyProtocol, .http)

        let parsedLocalhost = ProxyConfig.parse(from: "localhost:8080")
        XCTAssertNotNil(parsedLocalhost)
        XCTAssertEqual(parsedLocalhost?.host, "localhost")
        XCTAssertEqual(parsedLocalhost?.port, 8080)
        XCTAssertEqual(parsedLocalhost?.proxyProtocol, .http)

        let parsedSocks = ProxyConfig.parse(from: "socks5://user:pass@192.168.1.1:1080")
        XCTAssertNotNil(parsedSocks)
        XCTAssertEqual(parsedSocks?.host, "192.168.1.1")
        XCTAssertEqual(parsedSocks?.port, 1080)
        XCTAssertEqual(parsedSocks?.proxyProtocol, .socks5)
        XCTAssertEqual(parsedSocks?.authUsername, "user")
        XCTAssertEqual(parsedSocks?.authPassword, "pass")

        XCTAssertNil(ProxyConfig.parse(from: ""))
        XCTAssertNil(ProxyConfig.parse(from: "   "))
    }

    // MARK: - ConfigurationStore Tests

    func testConfigurationStorePersistence() {
        let testConfigURL = tempDirectory.appendingPathComponent("test-config.json")
        let store = ConfigurationStore(customStorageURL: testConfigURL)

        XCTAssertEqual(store.settings.pinnedBundleIdentifiers, [])

        // Pin an app
        let pinned = store.togglePin(bundleIdentifier: "com.google.Chrome")
        XCTAssertTrue(pinned)
        XCTAssertTrue(store.isPinned(bundleIdentifier: "com.google.Chrome"))

        // Add custom app proxy config
        let customProxy = ProxyConfig(host: "10.0.0.1", port: 8888, proxyProtocol: .http)
        let customConfig = AppCustomProxyConfig(
            mode: .customProxy,
            customProxy: customProxy,
            strategy: .launchFlags,
            extraLaunchArgs: ["--incognito"],
            extraEnvVars: [:]
        )
        store.setCustomConfig(customConfig, for: "com.google.Chrome")

        // Reload store from disk
        let reloadedStore = ConfigurationStore(customStorageURL: testConfigURL)
        XCTAssertTrue(reloadedStore.isPinned(bundleIdentifier: "com.google.Chrome"))

        let savedConfig = reloadedStore.customConfig(for: "com.google.Chrome")
        XCTAssertNotNil(savedConfig)
        XCTAssertEqual(savedConfig?.mode, .customProxy)
        XCTAssertEqual(savedConfig?.customProxy?.host, "10.0.0.1")
        XCTAssertEqual(savedConfig?.customProxy?.port, 8888)
        XCTAssertEqual(savedConfig?.extraLaunchArgs, ["--incognito"])
    }

    func testConfigurationStorePublisher() {
        let testConfigURL = tempDirectory.appendingPathComponent("publisher-config.json")
        let store = ConfigurationStore(customStorageURL: testConfigURL)
        var receivedSettings: [AppSettings] = []
        var cancellables = Set<AnyCancellable>()

        let expectation = expectation(description: "Receive settings update")
        expectation.expectedFulfillmentCount = 2 // initial value + 1 update

        store.settingsPublisher
            .sink { settings in
                receivedSettings.append(settings)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        store.update { settings in
            settings.globalProxy.isEnabled = false
        }

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(receivedSettings.count, 2)
        XCTAssertTrue(receivedSettings[0].globalProxy.isEnabled)
        XCTAssertFalse(receivedSettings[1].globalProxy.isEnabled)
    }

    // MARK: - AppDiscoveryService Tests

    func testDiscoveryServiceReturnsApplications() {
        let discovery = AppDiscoveryService.shared
        let apps = discovery.discoverApplications(scanUserApps: true, scanSystemApps: true)

        XCTAssertFalse(apps.isEmpty, "Should discover installed macOS applications")
        XCTAssertTrue(apps.contains { !$0.name.isEmpty && !$0.bundleIdentifier.isEmpty })
    }

    // MARK: - AppLauncherService Strategy Resolution Tests

    func testLauncherStrategyResolution() {
        let testConfigURL = tempDirectory.appendingPathComponent("launcher-config.json")
        let store = ConfigurationStore(customStorageURL: testConfigURL)
        let launcher = AppLauncherService(configStore: store)

        let chromeApp = AppItem(
            name: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            engineType: .chromium
        )

        let antigravityApp = AppItem(
            name: "Antigravity",
            bundleIdentifier: "com.google.antigravity",
            bundleURL: URL(fileURLWithPath: "/Applications/Antigravity.app"),
            engineType: .electron
        )

        let terminalApp = AppItem(
            name: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            bundleURL: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            engineType: .native
        )

        // With default global proxy enabled
        let resolvedChrome = launcher.resolveEffectiveProxy(for: chromeApp)
        XCTAssertNotNil(resolvedChrome)
        XCTAssertEqual(resolvedChrome?.strategy, .launchFlags, "Chromium browser apps should resolve to launchFlags by default")

        let resolvedAntigravity = launcher.resolveEffectiveProxy(for: antigravityApp)
        XCTAssertNotNil(resolvedAntigravity)
        XCTAssertEqual(resolvedAntigravity?.strategy, .environmentVar, "Electron apps should resolve to environmentVar by default")

        let resolvedTerminal = launcher.resolveEffectiveProxy(for: terminalApp)
        XCTAssertNotNil(resolvedTerminal)
        XCTAssertEqual(resolvedTerminal?.strategy, .environmentVar, "Standard native apps should resolve to environmentVar by default")
    }

    // MARK: - Managed Session & Lifecycle Tests

    func testManagedAppSessionModel() {
        let session = ManagedAppSession(
            bundleIdentifier: "com.example.app",
            pid: 12345,
            isProxied: true,
            proxyURLString: "http://127.0.0.1:7890",
            strategy: .environmentVar
        )

        XCTAssertEqual(session.bundleIdentifier, "com.example.app")
        XCTAssertEqual(session.pid, 12345)
        XCTAssertTrue(session.isProxied)
        XCTAssertEqual(session.proxyURLString, "http://127.0.0.1:7890")
        XCTAssertEqual(session.strategy, .environmentVar)
    }

    func testAppLifecycleManagerManagedSessionRegistration() {
        let lifecycle = AppLifecycleManager()
        let testBundleId = "com.test.managedapp"

        XCTAssertFalse(lifecycle.isAppRunning(bundleIdentifier: testBundleId))
        XCTAssertNil(lifecycle.pid(for: testBundleId))
        XCTAssertNil(lifecycle.managedSession(for: testBundleId))

        let session = ManagedAppSession(
            bundleIdentifier: testBundleId,
            pid: 99999,
            isProxied: true,
            proxyURLString: "http://127.0.0.1:7890",
            strategy: .launchFlags
        )

        let registerExpectation = expectation(description: "Register managed session")
        lifecycle.registerManagedSession(session)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(lifecycle.isAppRunning(bundleIdentifier: testBundleId))
            XCTAssertEqual(lifecycle.pid(for: testBundleId), 99999)
            XCTAssertEqual(lifecycle.managedSession(for: testBundleId)?.proxyURLString, "http://127.0.0.1:7890")
            registerExpectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        let unregisterExpectation = expectation(description: "Unregister managed session")
        lifecycle.unregisterManagedSession(bundleIdentifier: testBundleId)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(lifecycle.isAppRunning(bundleIdentifier: testBundleId))
            XCTAssertNil(lifecycle.pid(for: testBundleId))
            XCTAssertNil(lifecycle.managedSession(for: testBundleId))
            unregisterExpectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testAppItemProxyStateInitialization() {
        let app = AppItem(
            name: "Proxied App",
            bundleIdentifier: "com.example.proxied",
            bundleURL: URL(fileURLWithPath: "/Applications/Test.app"),
            isRunning: true,
            pid: 54321,
            isManagedByAppManager: true,
            activeProxyURLString: "http://127.0.0.1:7890",
            activeStrategy: .launchFlags
        )

        XCTAssertTrue(app.isRunning)
        XCTAssertEqual(app.pid, 54321)
        XCTAssertTrue(app.isManagedByAppManager)
        XCTAssertEqual(app.activeProxyURLString, "http://127.0.0.1:7890")
        XCTAssertEqual(app.activeStrategy, .launchFlags)
    }
}
