@preconcurrency import AppKit
import CoreGraphics
import Darwin
import Foundation
import FocusTraceCore

/// Reads the stable identities used by the macOS window server for managed
/// Spaces. SkyLight is not a public SDK, so every lookup is dynamic and the
/// provider fails closed when the symbols or response shape are unavailable.
@MainActor
public final class ManagedSpaceIdentityProvider {
    public struct Snapshot: Equatable, Sendable {
        public let currentSpaces: [WorkflowSpaceIdentity]
        public let allSpaces: [WorkflowSpaceIdentity]

        public func currentSpace(onDisplay displayIdentifier: String) -> WorkflowSpaceIdentity? {
            currentSpaces.first { $0.displayIdentifier == displayIdentifier }
        }

        public func contains(_ identity: WorkflowSpaceIdentity) -> Bool {
            allSpaces.contains { $0.identifiesSameSpace(as: identity) }
        }
    }

    private typealias MainConnectionFunction = @convention(c) () -> UInt32
    private typealias CopyManagedDisplaySpacesFunction = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias GetActiveSpaceFunction = @convention(c) (UInt32) -> UInt64

    private let frameworkHandle: UnsafeMutableRawPointer?
    private let mainConnection: MainConnectionFunction?
    private let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFunction?
    private let getActiveSpace: GetActiveSpaceFunction?

    public init() {
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY | RTLD_LOCAL
        )
        frameworkHandle = handle
        mainConnection = Self.loadSymbol(
            from: handle,
            names: ["SLSMainConnectionID", "CGSMainConnectionID"],
            as: MainConnectionFunction.self
        )
        copyManagedDisplaySpaces = Self.loadSymbol(
            from: handle,
            names: ["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"],
            as: CopyManagedDisplaySpacesFunction.self
        )
        getActiveSpace = Self.loadSymbol(
            from: handle,
            names: ["SLSGetActiveSpace", "CGSGetActiveSpace"],
            as: GetActiveSpaceFunction.self
        )
    }

    public var isAvailable: Bool {
        frameworkHandle != nil
            && mainConnection != nil
            && copyManagedDisplaySpaces != nil
            && getActiveSpace != nil
    }

    public func snapshot() -> Snapshot? {
        guard let mainConnection, let copyManagedDisplaySpaces else { return nil }
        let connectionID = mainConnection()
        guard let rawSpaces = copyManagedDisplaySpaces(connectionID)?.takeRetainedValue() else {
            return nil
        }

        var currentSpaces: [WorkflowSpaceIdentity] = []
        var allSpaces: [WorkflowSpaceIdentity] = []
        let displays = rawSpaces as NSArray
        for case let display as NSDictionary in displays {
            guard let displayIdentifier = display["Display Identifier"] as? String else { continue }
            if let current = display["Current Space"] as? NSDictionary,
               let identity = Self.identity(from: current, displayIdentifier: displayIdentifier) {
                currentSpaces.append(identity)
            }
            if let spaces = display["Spaces"] as? [NSDictionary] {
                allSpaces.append(contentsOf: spaces.compactMap {
                    Self.identity(from: $0, displayIdentifier: displayIdentifier)
                })
            } else if let spaces = display["Spaces"] as? NSArray {
                for case let space as NSDictionary in spaces {
                    if let identity = Self.identity(from: space, displayIdentifier: displayIdentifier) {
                        allSpaces.append(identity)
                    }
                }
            }
        }
        guard !currentSpaces.isEmpty else { return nil }
        return Snapshot(currentSpaces: currentSpaces, allSpaces: allSpaces)
    }

    public func activeIdentity() -> WorkflowSpaceIdentity? {
        guard let snapshot = snapshot() else {
            return nil
        }
        return activeIdentity(in: snapshot)
    }

    public func activeIdentity(in snapshot: Snapshot) -> WorkflowSpaceIdentity? {
        guard let mainConnection, let getActiveSpace else { return nil }
        return WorkflowSpaceIdentitySelector.activeIdentity(
            managedSpaceID: getActiveSpace(mainConnection()),
            allSpaces: snapshot.allSpaces
        )
    }

    /// Resolves an explicit bind/unbind action on the display where the user
    /// clicked. This is intentionally separate from passive Space-change
    /// resolution: a pointer can stay on another display while Spaces change.
    public func interactionIdentity() -> WorkflowSpaceIdentity? {
        guard let snapshot = snapshot() else { return nil }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSApp.keyWindow?.screen
            ?? NSScreen.main
        guard let screen,
              let displayIdentifier = Self.displayIdentifier(for: screen) else {
            return activeIdentity(in: snapshot)
        }
        return snapshot.currentSpace(onDisplay: displayIdentifier)
            ?? activeIdentity(in: snapshot)
    }

    private static func identity(
        from dictionary: NSDictionary,
        displayIdentifier: String
    ) -> WorkflowSpaceIdentity? {
        let numericID = (dictionary["id64"] as? NSNumber)?.uint64Value
            ?? (dictionary["ManagedSpaceID"] as? NSNumber)?.uint64Value
        guard let numericID, numericID > 0 else { return nil }
        let uuid = (dictionary["uuid"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return WorkflowSpaceIdentity(
            displayIdentifier: displayIdentifier,
            managedSpaceID: numericID,
            spaceUUID: uuid
        )
    }

    private static func displayIdentifier(for screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
              let value = CFUUIDCreateString(nil, uuid) else {
            return nil
        }
        return value as String
    }

    private static func loadSymbol<T>(
        from handle: UnsafeMutableRawPointer?,
        names: [String],
        as type: T.Type
    ) -> T? {
        guard let handle else { return nil }
        for name in names {
            if let symbol = dlsym(handle, name) {
                return unsafeBitCast(symbol, to: type)
            }
        }
        return nil
    }
}
