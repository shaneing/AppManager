import Foundation
import AppKit
import Combine

/// Monitors active macOS applications and manages process termination.
public final class AppLifecycleManager: ObservableObject, @unchecked Sendable {
    public static let shared = AppLifecycleManager()

    @Published public private(set) var runningApps: [String: NSRunningApplication] = [:]
    @Published public private(set) var managedSessions: [String: ManagedAppSession] = [:]
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
            // Clean up managed sessions whose processes are no longer alive
            for (bundleId, session) in self.managedSessions {
                if kill(session.pid, 0) != 0 && self.runningApps[bundleId] == nil {
                    self.managedSessions.removeValue(forKey: bundleId)
                }
            }
        }
    }

    // MARK: - Managed Sessions

    /// Registers a session for an application launched by AppManager.
    public func registerManagedSession(_ session: ManagedAppSession) {
        DispatchQueue.main.async {
            self.managedSessions[session.bundleIdentifier] = session
        }
    }

    /// Removes a managed session when an application terminates.
    public func unregisterManagedSession(bundleIdentifier: String) {
        DispatchQueue.main.async {
            self.managedSessions.removeValue(forKey: bundleIdentifier)
        }
    }

    /// Returns the managed session for a bundle identifier if active.
    public func managedSession(for bundleIdentifier: String) -> ManagedAppSession? {
        return managedSessions[bundleIdentifier]
    }

    /// Checks if an application with the given bundle identifier is currently running.
    public func isAppRunning(bundleIdentifier: String) -> Bool {
        return runningApps[bundleIdentifier] != nil || managedSessions[bundleIdentifier] != nil
    }

    /// Retrieves the PID of a running application.
    public func pid(for bundleIdentifier: String) -> pid_t? {
        return managedSessions[bundleIdentifier]?.pid ?? runningApps[bundleIdentifier]?.processIdentifier
    }

    /// Gracefully terminates an application (`NSRunningApplication.terminate()` or `SIGTERM`).
    @discardableResult
    public func terminateApp(bundleIdentifier: String) -> Bool {
        let managed = managedSessions[bundleIdentifier]
        if let runningApp = runningApps[bundleIdentifier] ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            let success = runningApp.terminate()
            if !success, let pid = managed?.pid ?? Optional(runningApp.processIdentifier) {
                kill(pid, SIGTERM)
            }
            unregisterManagedSession(bundleIdentifier: bundleIdentifier)
            return true
        } else if let managed = managed {
            kill(managed.pid, SIGTERM)
            unregisterManagedSession(bundleIdentifier: bundleIdentifier)
            return true
        }
        return false
    }

    /// Force terminates an application (`NSRunningApplication.forceTerminate()` or `SIGKILL`).
    @discardableResult
    public func forceKillApp(bundleIdentifier: String) -> Bool {
        let managed = managedSessions[bundleIdentifier]
        if let runningApp = runningApps[bundleIdentifier] ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            let success = runningApp.forceTerminate()
            if !success, let pid = managed?.pid ?? Optional(runningApp.processIdentifier) {
                kill(pid, SIGKILL)
            }
            unregisterManagedSession(bundleIdentifier: bundleIdentifier)
            return true
        } else if let managed = managed {
            kill(managed.pid, SIGKILL)
            unregisterManagedSession(bundleIdentifier: bundleIdentifier)
            return true
        }
        return false
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
            self.managedSessions.removeValue(forKey: bundleId)
        }
    }
}
