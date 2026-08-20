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
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).filter { !$0.isTerminated }
        if !instances.isEmpty { return true }
        if let running = runningApps[bundleIdentifier], !running.isTerminated { return true }
        if managedSessions[bundleIdentifier] != nil {
            return true
        }
        return false
    }

    /// Retrieves the PID of a running application.
    public func pid(for bundleIdentifier: String) -> pid_t? {
        if let sessionPid = managedSessions[bundleIdentifier]?.pid {
            return sessionPid
        }
        if let activeApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first(where: { !$0.isTerminated }) {
            return activeApp.processIdentifier
        }
        if let running = runningApps[bundleIdentifier], !running.isTerminated {
            return running.processIdentifier
        }
        return nil
    }

    /// Gracefully terminates an application (`NSRunningApplication.terminate()` or `SIGTERM`) across all matching instances.
    @discardableResult
    public func terminateApp(bundleIdentifier: String) -> Bool {
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        var didAttempt = false

        for app in instances {
            let success = app.terminate()
            if !success {
                kill(app.processIdentifier, SIGTERM)
            }
            didAttempt = true
        }

        if let runningApp = runningApps[bundleIdentifier], !instances.contains(runningApp) {
            let success = runningApp.terminate()
            if !success {
                kill(runningApp.processIdentifier, SIGTERM)
            }
            didAttempt = true
        }

        if let managed = managedSessions[bundleIdentifier] {
            kill(managed.pid, SIGTERM)
            didAttempt = true
        }

        unregisterManagedSession(bundleIdentifier: bundleIdentifier)
        return didAttempt
    }

    /// Force terminates an application (`NSRunningApplication.forceTerminate()` or `SIGKILL`) across all matching instances.
    @discardableResult
    public func forceKillApp(bundleIdentifier: String) -> Bool {
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        var didAttempt = false

        for app in instances {
            _ = app.forceTerminate()
            kill(app.processIdentifier, SIGKILL)
            didAttempt = true
        }

        if let runningApp = runningApps[bundleIdentifier], !instances.contains(runningApp) {
            _ = runningApp.forceTerminate()
            kill(runningApp.processIdentifier, SIGKILL)
            didAttempt = true
        }

        if let managed = managedSessions[bundleIdentifier] {
            kill(managed.pid, SIGKILL)
            didAttempt = true
        }

        unregisterManagedSession(bundleIdentifier: bundleIdentifier)
        DispatchQueue.main.async {
            self.runningApps.removeValue(forKey: bundleIdentifier)
        }

        return didAttempt
    }

    /// Gracefully terminates all active managed sessions that were launched with a proxy.
    /// Direct applications (`isProxied == false`) are left running.
    public func terminateAllProxiedManagedSessions() {
        let proxiedBundleIds = managedSessions.values
            .filter { $0.isProxied }
            .map { $0.bundleIdentifier }

        for bundleId in proxiedBundleIds {
            terminateApp(bundleIdentifier: bundleId)
        }
    }

    /// Asynchronously terminates an application with a 3-stage escalating pipeline:
    /// Stage 1: Graceful `terminate()` / `SIGTERM`
    /// Stage 2: Verification polling with timeout
    /// Stage 3: Automatic escalation to `forceTerminate()` / `SIGKILL` if still alive.
    @discardableResult
    public func terminateAppAndWait(bundleIdentifier: String, timeout: TimeInterval = 1.2) async -> Bool {
        terminateApp(bundleIdentifier: bundleIdentifier)

        let pollInterval: UInt64 = 80_000_000 // 80ms
        let start = Date()

        while Date().timeIntervalSince(start) < timeout {
            if !isAppRunning(bundleIdentifier: bundleIdentifier) {
                DispatchQueue.main.async {
                    self.runningApps.removeValue(forKey: bundleIdentifier)
                    self.managedSessions.removeValue(forKey: bundleIdentifier)
                }
                return true
            }
            try? await Task.sleep(nanoseconds: pollInterval)
        }

        // If still running after timeout, escalate to force kill (Stage 3)
        if isAppRunning(bundleIdentifier: bundleIdentifier) {
            forceKillApp(bundleIdentifier: bundleIdentifier)
            try? await Task.sleep(nanoseconds: pollInterval)
        }

        let isExited = !isAppRunning(bundleIdentifier: bundleIdentifier)
        if isExited {
            DispatchQueue.main.async {
                self.runningApps.removeValue(forKey: bundleIdentifier)
                self.managedSessions.removeValue(forKey: bundleIdentifier)
            }
        }
        return isExited
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
