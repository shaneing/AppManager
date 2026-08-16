import AppKit
import SwiftUI

/// Manages the native macOS status bar item and dropdown popover.
@MainActor
public final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?

    public override init() {
        super.init()
        setupPopover()
        setupStatusItem()
        setupEventMonitor()
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
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "bolt.shield.fill", accessibilityDescription: "AppManager")
            button.imagePosition = .imageLeading
            button.title = " AppManager"
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
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
