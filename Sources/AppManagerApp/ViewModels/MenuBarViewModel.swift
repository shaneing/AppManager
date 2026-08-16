import Foundation
import SwiftUI
import AppKit
import Combine
import AppManagerCore

@MainActor
public final class MenuBarViewModel: ObservableObject {
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
                updated.isRunning = lifecycle.isAppRunning(bundleIdentifier: app.bundleIdentifier)
                updated.pid = lifecycle.pid(for: app.bundleIdentifier)
                updated.customConfig = store.customConfig(for: app.bundleIdentifier)
                return updated
            }

            await MainActor.run {
                self.discoveredApps = mappedApps
                self.isLoading = false
            }
        }
    }

    private func setupLifecycleBindings() {
        lifecycleManager.$runningApps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] runningMap in
                guard let self = self else { return }
                for i in self.discoveredApps.indices {
                    let bundleId = self.discoveredApps[i].bundleIdentifier
                    if let runningApp = runningMap[bundleId] {
                        self.discoveredApps[i].isRunning = true
                        self.discoveredApps[i].pid = runningApp.processIdentifier
                    } else {
                        self.discoveredApps[i].isRunning = false
                        self.discoveredApps[i].pid = nil
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
        launcherService.launchNormally(app: app)
        showMessage("Launched \(app.name)")
    }

    public func launchAppWithProxy(app: AppItem) {
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
        let success = lifecycleManager.terminateApp(bundleIdentifier: app.bundleIdentifier)
        if success {
            showMessage("Terminating \(app.name)...")
        } else {
            showMessage("Could not terminate \(app.name)")
        }
    }

    public func forceKillApp(app: AppItem) {
        lifecycleManager.forceKillApp(bundleIdentifier: app.bundleIdentifier)
        showMessage("Force killed \(app.name)")
    }

    public func toggleGlobalProxy() {
        globalProxy.isEnabled.toggle()
        configStore.update { settings in
            settings.globalProxy.isEnabled = self.globalProxy.isEnabled
        }
    }

    public func updateGlobalProxy(_ config: ProxyConfig) {
        self.globalProxy = config
        configStore.update { settings in
            settings.globalProxy = config
        }
    }

    public func saveAppCustomConfig(_ config: AppCustomProxyConfig?, for app: AppItem) {
        configStore.setCustomConfig(config, for: app.bundleIdentifier)
        if let idx = discoveredApps.firstIndex(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            discoveredApps[idx].customConfig = config
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
