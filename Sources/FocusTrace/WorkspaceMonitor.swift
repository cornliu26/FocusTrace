@preconcurrency import AppKit
import Foundation
import FocusTraceCore

@MainActor
final class WorkspaceMonitor: NSObject {
    typealias AppHandler = (AppIdentity, Date) -> Void
    typealias EventHandler = (Date) -> Void

    var onAppActivated: AppHandler?
    var onSpaceChanged: EventHandler?
    var onSystemInactive: ((ActivityEventSource, Date) -> Void)?
    var onSystemActive: ((ActivityEventSource, AppIdentity?, Date) -> Void)?

    private let workspace = NSWorkspace.shared
    private var isStarted = false

    var frontmostApp: AppIdentity? {
        Self.identity(for: workspace.frontmostApplication)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let center = workspace.notificationCenter
        center.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(spaceChanged(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(screenSlept(_:)),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(screenWoke(_:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionInactive(_:)),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionActive(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(willSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(didWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func stop() {
        guard isStarted else { return }
        workspace.notificationCenter.removeObserver(self)
        isStarted = false
    }

    @objc private func appActivated(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let identity = Self.identity(for: app) {
            onAppActivated?(identity, Date())
        }
    }

    @objc private func spaceChanged(_ notification: Notification) {
        onSpaceChanged?(Date())
    }

    @objc private func screenSlept(_ notification: Notification) {
        onSystemInactive?(.screenSleep, Date())
    }

    @objc private func screenWoke(_ notification: Notification) {
        onSystemActive?(.screenWake, frontmostApp, Date())
    }

    @objc private func sessionInactive(_ notification: Notification) {
        onSystemInactive?(.sessionInactive, Date())
    }

    @objc private func sessionActive(_ notification: Notification) {
        onSystemActive?(.sessionActive, frontmostApp, Date())
    }

    @objc private func willSleep(_ notification: Notification) {
        onSystemInactive?(.screenSleep, Date())
    }

    @objc private func didWake(_ notification: Notification) {
        onSystemActive?(.screenWake, frontmostApp, Date())
    }

    static func runningApps() -> [AppIdentity] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .compactMap(identity(for:))
            .filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func identity(for app: NSRunningApplication?) -> AppIdentity? {
        guard let app,
              let bundleID = app.bundleIdentifier,
              !bundleID.isEmpty else {
            return nil
        }
        return AppIdentity(bundleID: bundleID, name: app.localizedName ?? bundleID)
    }
}
