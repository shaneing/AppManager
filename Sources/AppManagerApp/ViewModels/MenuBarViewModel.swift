import Foundation
import SwiftUI
import AppKit
import Combine
import AppManagerCore

public enum PopoverScreen: Equatable {
    case mainList
    case globalSettings
    case appConfig(AppItem)
}

@MainActor
public final class MenuBarViewModel: ObservableObject {
    @Published public var activeScreen: PopoverScreen = .mainList
    @Published public var searchText: String = ""
    @Published public var discoveredApps: [AppItem] = []
    @Published public var pinnedAppBundleIds: Set<String> = []
    @Published public var globalProxy: ProxyConfig = ProxyConfig()
    @Published public var selectedAppForConfig: AppItem? = nil
    @Published public var isShowingSettings: Bool = false
    @Published public var statusMessage: String? = nil
    @Published public var isLoading: Bool = false

    private let discoveryService = AppDiscoveryService.shared
    private let lifecycleManager = AppLifecycleManager.shared
    private let configStore = ConfigurationStore.shared
    private let launcherService = AppLauncherService.shared
    private var cancellables = Set<AnyCancellable>()

    public init() {
        loadSettings()
        reloadApplications()
        setupLifecycleBindings()
    }

    public func loadSettings() {
        let settings = configStore.settings
        self.globalProxy = settings.globalProxy
        self.pinnedAppBundleIds = Set(settings.pinnedBundleIdentifiers)
    }

    public func reloadApplications() {
        self.isLoading = true
        let settings = configStore.settings
        let discovery = self.discoveryService
        let pinnedIds = self.pinnedAppBundleIds
        let lifecycle = self.lifecycleManager
        let store = self.configStore

        Task.detached(priority: .userInitiated) {
            let rawApps = discovery.discoverApplications(
                scanUserApps: settings.scanUserApplications,
                scanSystemApps: settings.scanSystemApplications,
                additionalDirectories: settings.scanAdditionalDirectories
            )

            let mappedApps = rawApps.map { app -> AppItem in
                var updated = app
                updated.isPinned = pinnedIds.contains(app.bundleIdentifier)
                let isRunning = lifecycle.isAppRunning(bundleIdentifier: app.bundleIdentifier)
                updated.isRunning = isRunning
                updated.pid = lifecycle.pid(for: app.bundleIdentifier)
                updated.customConfig = store.customConfig(for: app.bundleIdentifier)
                if let session = lifecycle.managedSession(for: app.bundleIdentifier) {
                    updated.isManagedByAppManager = true
                    updated.activeProxyURLString = session.isProxied ? session.proxyURLString : nil
                    updated.activeStrategy = session.strategy
                } else {
                    updated.isManagedByAppManager = false
                    updated.activeProxyURLString = nil
                    updated.activeStrategy = nil
                }
                return updated
            }

            await MainActor.run {
                self.discoveredApps = mappedApps
                self.isLoading = false
            }
        }
    }

    private func setupLifecycleBindings() {
        Publishers.CombineLatest(lifecycleManager.$runningApps, lifecycleManager.$managedSessions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] runningMap, managedMap in
                guard let self = self else { return }
                for i in self.discoveredApps.indices {
                    let bundleId = self.discoveredApps[i].bundleIdentifier
                    let runningApp = runningMap[bundleId]
                    let session = managedMap[bundleId]

                    let isRunning = runningApp != nil || session != nil
                    self.discoveredApps[i].isRunning = isRunning
                    self.discoveredApps[i].pid = session?.pid ?? runningApp?.processIdentifier

                    if let session = session {
                        self.discoveredApps[i].isManagedByAppManager = true
                        self.discoveredApps[i].activeProxyURLString = session.isProxied ? session.proxyURLString : nil
                        self.discoveredApps[i].activeStrategy = session.strategy
                    } else {
                        self.discoveredApps[i].isManagedByAppManager = false
                        self.discoveredApps[i].activeProxyURLString = nil
                        self.discoveredApps[i].activeStrategy = nil
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Computed Properties

    public var filteredApps: [AppItem] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return discoveredApps
        }
        let query = searchText.lowercased()
        return discoveredApps.filter {
            $0.name.lowercased().contains(query) || $0.bundleIdentifier.lowercased().contains(query)
        }
    }

    public var pinnedApps: [AppItem] {
        filteredApps.filter { $0.isPinned }
    }

    public var runningApps: [AppItem] {
        filteredApps.filter { $0.isRunning && !$0.isPinned }
    }

    public var unpinnedInstalledApps: [AppItem] {
        filteredApps.filter { !$0.isPinned && !$0.isRunning }
    }

    // MARK: - Actions

    public func togglePin(app: AppItem) {
        let isPinned = configStore.togglePin(bundleIdentifier: app.bundleIdentifier)
        if isPinned {
            pinnedAppBundleIds.insert(app.bundleIdentifier)
        } else {
            pinnedAppBundleIds.remove(app.bundleIdentifier)
        }
        if let idx = discoveredApps.firstIndex(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            discoveredApps[idx].isPinned = isPinned
        }
    }

    public func launchAppNormally(app: AppItem) {
        if app.isRunning {
            NSWorkspace.shared.open(app.bundleURL)
            showMessage("ℹ️ \(app.name) is already running")
            return
        }
        launcherService.launchNormally(app: app) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.showMessage("Launched \(app.name)")
                case .failure(let error):
                    self?.showMessage("Launch Error: \(error.localizedDescription)")
                }
            }
        }
    }

    public func launchAppWithProxy(app: AppItem) {
        if app.isRunning {
            if let proxyURL = app.activeProxyURLString {
                showMessage("ℹ️ \(app.name) is already running with Proxy (\(proxyURL))")
            } else {
                showMessage("⚠️ \(app.name) is already running unproxied. Stop it first to apply HTTP Proxy.")
            }
            return
        }

        launcherService.launchWithProxy(app: app) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.showMessage("Launched \(app.name) over proxy")
                case .failure(let error):
                    self?.showMessage("Proxy Launch Error: \(error.localizedDescription)")
                }
            }
        }
    }

    public func stopApp(app: AppItem) {
        showMessage("Terminating \(app.name)...")
        Task {
            let success = await lifecycleManager.terminateAppAndWait(bundleIdentifier: app.bundleIdentifier, timeout: 1.2)
            await MainActor.run {
                if success {
                    showMessage("Stopped \(app.name)")
                } else {
                    showMessage("Could not terminate \(app.name)")
                }
            }
        }
    }

    public func forceKillApp(app: AppItem) {
        let success = lifecycleManager.forceKillApp(bundleIdentifier: app.bundleIdentifier)
        if success {
            showMessage("Force killed \(app.name)")
        } else {
            showMessage("Could not force kill \(app.name)")
        }
    }

    public func toggleGlobalProxy() {
        globalProxy.isEnabled.toggle()
        let updatedProxy = globalProxy
        configStore.update { settings in
            settings.globalProxy.isEnabled = updatedProxy.isEnabled
        }
        relaunchProxiedAppsInheritingGlobalProxy(newProxy: updatedProxy)
    }

    public func updateGlobalProxy(_ config: ProxyConfig) {
        self.globalProxy = config
        configStore.update { settings in
            settings.globalProxy = config
        }
        relaunchProxiedAppsInheritingGlobalProxy(newProxy: config)
    }

    public func relaunchProxiedAppsInheritingGlobalProxy(newProxy: ProxyConfig) {
        guard configStore.settings.relaunchProxiedAppsOnProxyChange else { return }

        let candidates = discoveredApps.filter { app in
            guard app.isRunning,
                  app.isManagedByAppManager,
                  app.activeProxyURLString != nil else {
                return false
            }
            let mode = app.customConfig?.mode ?? .inheritGlobal
            return mode == .inheritGlobal
        }

        guard !candidates.isEmpty else { return }

        let count = candidates.count
        showMessage("Relaunching \(count) proxied app\(count > 1 ? "s" : "") with updated proxy...")

        Task {
            for app in candidates {
                await lifecycleManager.terminateAppAndWait(bundleIdentifier: app.bundleIdentifier)

                if newProxy.isEnabled {
                    launcherService.launchWithProxy(app: app, overrideProxy: newProxy)
                } else {
                    launcherService.launchNormally(app: app)
                }
            }
        }
    }

    public func saveAppCustomConfig(_ config: AppCustomProxyConfig?, for app: AppItem) {
        configStore.setCustomConfig(config, for: app.bundleIdentifier)
        if let idx = discoveredApps.firstIndex(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            discoveredApps[idx].customConfig = config
        }
    }

    public func openGlobalSettings() {
        self.activeScreen = .globalSettings
    }

    public func openAppConfig(for app: AppItem) {
        self.activeScreen = .appConfig(app)
    }

    public func navigateBack() {
        self.activeScreen = .mainList
    }

    public func checkCodeSigning(for app: AppItem) -> CodeSigningInfo {
        return CodeSigningService.shared.inspectCodeSigning(bundleURL: app.bundleURL)
    }

    public func resignAppAdHoc(app: AppItem) async -> Result<Void, Error> {
        showMessage("Re-signing \(app.name) ad-hoc...")
        do {
            try await CodeSigningService.shared.performAdHocResign(bundleURL: app.bundleURL)
            showMessage("✅ Successfully re-signed \(app.name)")
            return .success(())
        } catch {
            showMessage("❌ Failed to re-sign \(app.name): \(error.localizedDescription)")
            return .failure(error)
        }
    }

    private func showMessage(_ msg: String) {
        self.statusMessage = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.statusMessage == msg {
                self.statusMessage = nil
            }
        }
    }
}
