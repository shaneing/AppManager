import AppKit
import SwiftUI
import Combine
import AppManagerCore

/// Manages the native macOS status bar item and dropdown popover.
@MainActor
public final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    public override init() {
        super.init()
        setupPopover()
        setupStatusItem()
        setupEventMonitor()
        setupConfigurationObservation()
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupPopover() {
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 380, height: 480)
        pop.behavior = .transient
        pop.animates = true
        pop.contentViewController = NSHostingController(rootView: MenuBarPopoverView())
        self.popover = pop
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.title = ""
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
        
        let initialSettings = ConfigurationStore.shared.settings
        updateStatusItem(
            isProxyEnabled: initialSettings.globalProxy.isEnabled,
            proxyUrl: initialSettings.globalProxy.urlString
        )
    }

    private func setupConfigurationObservation() {
        ConfigurationStore.shared.settingsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                self?.updateStatusItem(
                    isProxyEnabled: settings.globalProxy.isEnabled,
                    proxyUrl: settings.globalProxy.urlString
                )
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(isProxyEnabled: Bool, proxyUrl: String) {
        guard let button = statusItem?.button else { return }
        let symbolName = isProxyEnabled ? "bolt.shield.fill" : "bolt.shield"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AppManager") {
            image.isTemplate = true
            button.image = image
        }
        button.toolTip = isProxyEnabled ? "AppManager (Proxy Enabled: \(proxyUrl))" : "AppManager (Proxy Disabled)"
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let pop = self.popover, pop.isShown else { return }
            pop.performClose(event)
        }
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let pop = popover, let button = statusItem?.button else { return }

        if pop.isShown {
            pop.performClose(sender)
        } else {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            pop.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
