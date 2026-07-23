import Foundation
import FocusTraceCore

/// Maintains workflow bindings keyed by the durable identity of a macOS Space.
/// The historical name is retained to keep the app-facing API source-stable;
/// no NSWindow anchor is created anymore.
@MainActor
public final class SpaceAnchorRegistry {
    public enum BindResult: Equatable {
        case created(bindingID: UUID, identity: WorkflowSpaceIdentity)
        case alreadyBound(bindingID: UUID)
        case occupied(workflowID: UUID)
        case failed
    }

    public enum RestoreResult: Equatable {
        case restored
        case missing
        case providerUnavailable
    }

    private struct Binding {
        let bindingID: UUID
        let workflowID: UUID
        let restorationID: String
        let identity: WorkflowSpaceIdentity
    }

    private let identityProvider: ManagedSpaceIdentityProvider
    private var bindingsByID: [UUID: Binding] = [:]
    private var lastObservedCurrentSpaces: [WorkflowSpaceIdentity]?
    public private(set) var lastResolvedIdentity: WorkflowSpaceIdentity?

    public init(identityProvider: ManagedSpaceIdentityProvider = ManagedSpaceIdentityProvider()) {
        self.identityProvider = identityProvider
    }

    public var isEnabled: Bool { !bindingsByID.isEmpty }
    public var isIdentityProviderAvailable: Bool { identityProvider.isAvailable }

    public func currentIdentity() -> WorkflowSpaceIdentity? {
        identityProvider.activeIdentity()
    }

    public func currentInteractionIdentity() -> WorkflowSpaceIdentity? {
        identityProvider.interactionIdentity()
    }

    public func allSpaceIdentities() -> [WorkflowSpaceIdentity]? {
        identityProvider.snapshot()?.allSpaces
    }

    public func seedCurrentSpaceSnapshot() {
        lastObservedCurrentSpaces = identityProvider.snapshot()?.currentSpaces
    }

    public func bindCurrentSpace(
        workflowID: UUID,
        bindingID: UUID = UUID(),
        restorationID: String = UUID().uuidString
    ) -> BindResult {
        guard let identity = identityProvider.interactionIdentity() else { return .failed }
        lastResolvedIdentity = identity
        seedCurrentSpaceSnapshot()
        let existing = bindings(on: identity)
        if let same = existing.first(where: { $0.workflowID == workflowID }) {
            return .alreadyBound(bindingID: same.bindingID)
        }
        if let occupied = existing.first {
            return .occupied(workflowID: occupied.workflowID)
        }
        bindingsByID[bindingID] = Binding(
            bindingID: bindingID,
            workflowID: workflowID,
            restorationID: restorationID,
            identity: identity
        )
        return .created(bindingID: bindingID, identity: identity)
    }

    public func restore(
        bindingID: UUID,
        workflowID: UUID,
        restorationID: String,
        identity: WorkflowSpaceIdentity
    ) -> RestoreResult {
        guard let snapshot = identityProvider.snapshot() else {
            // Keep the binding in memory so a transient provider failure does
            // not silently disable Space mode; resolution remains unknown.
            bindingsByID[bindingID] = Binding(
                bindingID: bindingID,
                workflowID: workflowID,
                restorationID: restorationID,
                identity: identity
            )
            return .providerUnavailable
        }
        guard snapshot.contains(identity) else { return .missing }
        bindingsByID[bindingID] = Binding(
            bindingID: bindingID,
            workflowID: workflowID,
            restorationID: restorationID,
            identity: identity
        )
        return .restored
    }

    /// Resolves the Space of the frontmost application. This is appropriate
    /// for an app-activation event, not for a passive Space-change event on a
    /// multi-display Mac.
    public func resolutionForActiveApplication(
        registryReady: Bool = true
    ) -> WorkflowSpaceResolution {
        guard registryReady, let snapshot = identityProvider.snapshot(),
              let currentIdentity = identityProvider.activeIdentity(in: snapshot) else {
            return .unknown
        }
        return resolution(for: currentIdentity)
    }

    public func resolution(registryReady: Bool = true) -> WorkflowSpaceResolution {
        resolutionForActiveApplication(registryReady: registryReady)
    }

    public func resolutionForInteraction(
        registryReady: Bool = true
    ) -> WorkflowSpaceResolution {
        guard registryReady,
              let currentIdentity = identityProvider.interactionIdentity() else {
            return .unknown
        }
        return resolution(for: currentIdentity)
    }

    public func resolutionAfterSpaceChange(
        registryReady: Bool = true
    ) -> WorkflowSpaceResolution {
        resolutionForChangedDisplay(registryReady: registryReady) ?? .unknown
    }

    /// Returns a resolution only when one display's current Space changed
    /// since the previous snapshot. `nil` means there was no delta; `.unknown`
    /// means the provider failed and callers should fail closed.
    public func resolutionForChangedDisplay(
        registryReady: Bool = true
    ) -> WorkflowSpaceResolution? {
        guard registryReady else { return .unknown }
        guard let snapshot = identityProvider.snapshot() else {
            return .unknown
        }
        let activeIdentity = identityProvider.activeIdentity(in: snapshot)
        let currentIdentity = WorkflowSpaceTransitionSelector.changedIdentity(
            previousCurrentSpaces: lastObservedCurrentSpaces ?? [],
            currentSpaces: snapshot.currentSpaces,
            activeIdentity: activeIdentity
        )
        lastObservedCurrentSpaces = snapshot.currentSpaces
        guard let currentIdentity else { return nil }
        return resolution(for: currentIdentity)
    }

    private func resolution(
        for currentIdentity: WorkflowSpaceIdentity
    ) -> WorkflowSpaceResolution {
        lastResolvedIdentity = currentIdentity
        let records = bindingsByID.values.map { binding in
            WorkflowSpaceBindingRecord(
                id: binding.bindingID,
                workflowID: binding.workflowID,
                anchorRestorationID: binding.restorationID,
                displayHint: binding.identity.displayIdentifier,
                spaceIdentity: binding.identity,
                spaceIdentityVersion: WorkflowSpaceBindingCompatibility.currentIdentityVersion,
                state: .verified
            )
        }
        return WorkflowSpaceResolutionEngine.resolve(
            currentSpaceIdentity: currentIdentity,
            bindings: records,
            registryReady: true
        )
    }

    @discardableResult
    public func releaseCurrentSpace() -> [UUID] {
        guard let identity = identityProvider.interactionIdentity() else { return [] }
        lastResolvedIdentity = identity
        seedCurrentSpaceSnapshot()
        let bindingIDs = bindings(on: identity).map(\.bindingID)
        bindingIDs.forEach { release(bindingID: $0) }
        return bindingIDs.sorted { $0.uuidString < $1.uuidString }
    }

    public func release(bindingID: UUID) {
        bindingsByID.removeValue(forKey: bindingID)
    }

    public func releaseAll(workflowID: UUID? = nil) {
        let bindingIDs = bindingsByID.values
            .filter { workflowID == nil || $0.workflowID == workflowID }
            .map(\.bindingID)
        bindingIDs.forEach { release(bindingID: $0) }
    }

    public func contains(bindingID: UUID) -> Bool {
        bindingsByID[bindingID] != nil
    }

    private func bindings(on identity: WorkflowSpaceIdentity) -> [Binding] {
        bindingsByID.values
            .filter { $0.identity.identifiesSameSpace(as: identity) }
            .sorted { $0.bindingID.uuidString < $1.bindingID.uuidString }
    }
}
