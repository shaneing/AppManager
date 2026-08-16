import Foundation
import AppKit
import Combine

/// Monitors active macOS applications and manages process termination.
public final class AppLifecycleManager: ObservableObject, @unchecked Sendable {
    public static let shared = AppLifecycleManager()

    @Published public private(set) var runningApps: [String: NSRunningApplication] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let queue = DispatchQueue(label: "com.appmanager.lifecyclemanager", attributes: .concurrent)

    public init() {
        refreshRunningApplications()
        setupWorkspaceNotifications()
    }

    /// Reloads all currently running regular GUI applications.
    public func refreshRunningApplications() {
        let apps = NSWorkspace.shared.runningApplications
        var appMap: [String: NSRunningApplication] = [:]

        for app in apps {
            guard let bundleId = app.bundleIdentifier else { continue }
            // Prefer standard GUI apps
            if app.activationPolicy == .regular || app.activationPolicy == .accessory {
                appMap[bundleId] = app
            }
        }

        DispatchQueue.main.async {
            self.runningApps = appMap
        }
    }

    /// Checks if an application with the given bundle identifier is currently running.
    public func isAppRunning(bundleIdentifier: String) -> Bool {
        return runningApps[bundleIdentifier] != nil
    }

    /// Retrieves the PID of a running application.
    public func pid(for bundleIdentifier: String) -> pid_t? {
        return runningApps[bundleIdentifier]?.processIdentifier
    }

    /// Gracefully terminates an application (`NSRunningApplication.terminate()`).
    @discardableResult
    public func terminateApp(bundleIdentifier: String) -> Bool {
        guard let runningApp = runningApps[bundleIdentifier] ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return false
        }
        return runningApp.terminate()
    }

    /// Force terminates an application (`NSRunningApplication.forceTerminate()` or `SIGKILL`).
    @discardableResult
    public func forceKillApp(bundleIdentifier: String) -> Bool {
        guard let runningApp = runningApps[bundleIdentifier] ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return false
        }
        let success = runningApp.forceTerminate()
        if !success {
            kill(runningApp.processIdentifier, SIGKILL)
        }
        return true
    }

    // MARK: - Notifications

    private func setupWorkspaceNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        notificationCenter.addObserver(
            self,
            selector: #selector(handleAppLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(handleAppTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    @objc private func handleAppLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }

        DispatchQueue.main.async {
            self.runningApps[bundleId] = app
        }
    }

    @objc private func handleAppTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }

        DispatchQueue.main.async {
            self.runningApps.removeValue(forKey: bundleId)
        }
    }
}
