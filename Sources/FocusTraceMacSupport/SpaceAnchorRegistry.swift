@preconcurrency import AppKit
import Foundation
import FocusTraceCore

@MainActor
public final class SpaceAnchorRegistry {
    public enum BindResult: Equatable {
        case created(bindingID: UUID)
        case alreadyBound(bindingID: UUID)
        case occupied(workflowID: UUID)
        case failed
    }

    public struct ActiveAnchor: Equatable {
        public let bindingID: UUID
        public let workflowID: UUID
    }

    private final class AnchorPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private struct Anchor {
        let bindingID: UUID
        let workflowID: UUID
        let restorationID: String
        let window: NSWindow
        let ownsWindow: Bool
    }

    private var anchorsByBindingID: [UUID: Anchor] = [:]

    public init() {}

    public var isEnabled: Bool { !anchorsByBindingID.isEmpty }

    public func bindCurrentSpace(
        workflowID: UUID,
        bindingID: UUID = UUID(),
        restorationID: String = UUID().uuidString
    ) -> BindResult {
        let active = activeAnchors()
        if let same = active.first(where: { $0.workflowID == workflowID }) {
            return .alreadyBound(bindingID: same.bindingID)
        }
        if let occupied = active.first {
            return .occupied(workflowID: occupied.workflowID)
        }

        let panel = makeAnchorPanel(restorationID: restorationID)
        panel.orderFrontRegardless()
        let anchor = Anchor(
            bindingID: bindingID,
            workflowID: workflowID,
            restorationID: restorationID,
            window: panel,
            ownsWindow: true
        )
        anchorsByBindingID[bindingID] = anchor

        // AppKit assigns a newly ordered window to its Space on the next
        // window-server turn. Reading isOnActiveSpace in the same call stack
        // can report a false negative, especially for menu-bar applications.
        let verificationDeadline = Date().addingTimeInterval(0.5)
        repeat {
            panel.displayIfNeeded()
            NSApp.updateWindows()
            if panel.isOnActiveSpace { break }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        } while Date() < verificationDeadline

        guard panel.isOnActiveSpace else {
            anchorsByBindingID.removeValue(forKey: bindingID)
            panel.close()
            return .failed
        }
        // Pin the now-confirmed window to this Space. moveToActiveSpace and
        // fullScreenAuxiliary are needed only while the invisible panel is
        // being created. Keeping fullScreenAuxiliary here would make the
        // anchor follow a same-app window into its full-screen Space and make
        // two distinct Spaces resolve to the same workflow.
        panel.collectionBehavior = [.managed, .ignoresCycle]
        return .created(bindingID: bindingID)
    }

    /// Registers a visible app window as the Space anchor. This is primarily
    /// useful for acceptance harnesses whose full-screen primary windows are
    /// themselves the stable public marker for each Space.
    public func bindCurrentSpace(
        workflowID: UUID,
        using window: NSWindow,
        bindingID: UUID = UUID(),
        restorationID: String = UUID().uuidString
    ) -> BindResult {
        let active = activeAnchors()
        if let same = active.first(where: { $0.workflowID == workflowID }) {
            return .alreadyBound(bindingID: same.bindingID)
        }
        if let occupied = active.first {
            return .occupied(workflowID: occupied.workflowID)
        }
        guard window.isVisible, window.isOnActiveSpace else { return .failed }

        anchorsByBindingID[bindingID] = Anchor(
            bindingID: bindingID,
            workflowID: workflowID,
            restorationID: restorationID,
            window: window,
            ownsWindow: false
        )
        return .created(bindingID: bindingID)
    }

    public func activeAnchors() -> [ActiveAnchor] {
        anchorsByBindingID.values
            .filter { $0.window.isVisible && $0.window.isOnActiveSpace }
            .map { ActiveAnchor(bindingID: $0.bindingID, workflowID: $0.workflowID) }
            .sorted { $0.bindingID.uuidString < $1.bindingID.uuidString }
    }

    public func resolution(registryReady: Bool = true) -> WorkflowSpaceResolution {
        WorkflowSpaceResolutionEngine.resolve(
            activeAnchorWorkflowIDs: activeAnchors().map(\.workflowID),
            registryReady: registryReady
        )
    }

    @discardableResult
    public func releaseCurrentSpace() -> [UUID] {
        let bindingIDs = activeAnchors().map(\.bindingID)
        bindingIDs.forEach(release)
        return bindingIDs
    }

    public func release(bindingID: UUID) {
        guard let anchor = anchorsByBindingID.removeValue(forKey: bindingID) else { return }
        guard anchor.ownsWindow else { return }
        anchor.window.orderOut(nil)
        anchor.window.close()
    }

    public func releaseAll(workflowID: UUID? = nil) {
        let bindingIDs = anchorsByBindingID.values
            .filter { workflowID == nil || $0.workflowID == workflowID }
            .map(\.bindingID)
        bindingIDs.forEach(release)
    }

    public func contains(bindingID: UUID) -> Bool {
        anchorsByBindingID[bindingID] != nil
    }

    private func makeAnchorPanel(restorationID: String) -> NSPanel {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 100, height: 100)
        let frame = NSRect(
            x: visibleFrame.maxX - 2,
            y: visibleFrame.minY + 1,
            width: 1,
            height: 1
        )
        let panel = AnchorPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.identifier = NSUserInterfaceItemIdentifier(restorationID)
        panel.title = ""
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 0.01
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.moveToActiveSpace, .ignoresCycle, .fullScreenAuxiliary]
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        return panel
    }
}
