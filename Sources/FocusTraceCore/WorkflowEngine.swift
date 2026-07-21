import Foundation

public enum WorkflowLifecycle: String, Codable, CaseIterable, Sendable {
    case open
    case completed
    case archived
}

public enum WorkflowPresence: String, Codable, CaseIterable, Sendable {
    case unbound
    case background
    case foreground
    case parked
    case unknown
}

public enum WorkflowSpaceBindingState: String, Codable, CaseIterable, Sendable {
    case verified
    case needsRebind
    case conflict
    case released
}

public enum WorkflowIntervalSource: String, Codable, CaseIterable, Sendable {
    case space
    case manual
    case recovery
}

public enum WorkflowContextConfidence: String, Codable, CaseIterable, Sendable {
    case verified
    case unknown
}

/// A durable macOS Space identity. The display identifier scopes the Space
/// because macOS can keep an independently active Space on every display.
/// The UUID is preferred when present; managedSpaceID is retained as a
/// compatibility fallback for OS versions that omit the UUID.
public struct WorkflowSpaceIdentity: Codable, Equatable, Hashable, Sendable {
    public let displayIdentifier: String
    public let managedSpaceID: UInt64
    public let spaceUUID: String?

    public init(
        displayIdentifier: String,
        managedSpaceID: UInt64,
        spaceUUID: String? = nil
    ) {
        self.displayIdentifier = displayIdentifier
        self.managedSpaceID = managedSpaceID
        self.spaceUUID = spaceUUID
    }

    public func identifiesSameSpace(as other: WorkflowSpaceIdentity) -> Bool {
        guard displayIdentifier == other.displayIdentifier else { return false }
        if let spaceUUID, let otherUUID = other.spaceUUID {
            return spaceUUID == otherUUID
        }
        return managedSpaceID == other.managedSpaceID
    }
}

public enum WorkflowSpaceIdentitySelector {
    /// Resolves the window server's globally active managed Space ID to one
    /// durable identity. Ambiguous IDs deliberately fail closed.
    public static func activeIdentity(
        managedSpaceID: UInt64,
        allSpaces: [WorkflowSpaceIdentity]
    ) -> WorkflowSpaceIdentity? {
        guard managedSpaceID > 0 else { return nil }
        let matches = Array(Set(allSpaces.filter {
            $0.managedSpaceID == managedSpaceID
        }))
        guard matches.count == 1 else { return nil }
        return matches[0]
    }
}

public enum WorkflowSpaceTransitionSelector {
    /// Selects the Space that actually changed on a multi-display desktop.
    /// `activeIdentity` is only a tiebreaker when macOS changes more than one
    /// display at once; it must never override one unambiguous display delta.
    public static func changedIdentity(
        previousCurrentSpaces: [WorkflowSpaceIdentity],
        currentSpaces: [WorkflowSpaceIdentity],
        activeIdentity: WorkflowSpaceIdentity?
    ) -> WorkflowSpaceIdentity? {
        guard !currentSpaces.isEmpty else { return nil }
        var previousByDisplay: [String: WorkflowSpaceIdentity] = [:]
        for identity in previousCurrentSpaces {
            previousByDisplay[identity.displayIdentifier] = identity
        }
        let changed = currentSpaces.filter { current in
            guard let previous = previousByDisplay[current.displayIdentifier] else {
                return true
            }
            return !previous.identifiesSameSpace(as: current)
        }

        if changed.count == 1 { return changed[0] }
        if changed.count > 1, let activeIdentity,
           let activeChanged = changed.first(where: {
               $0.identifiesSameSpace(as: activeIdentity)
           }) {
            return activeChanged
        }
        // No delta means there is nothing to reconcile. Falling back to the
        // global active Space here would periodically select an unrelated
        // display when macOS "Displays have separate Spaces" is enabled.
        return nil
    }
}

public enum WorkflowSpaceBindingCompatibility {
    /// Version 1 used the mouse display for both binding and resolution.
    /// Version 2 used one global active Space, which is ambiguous when several
    /// displays have independent Spaces. Version 3 binds on the interaction
    /// display and resolves Space-change events from per-display deltas.
    public static let currentIdentityVersion = 3

    public static func canRestore(
        identity: WorkflowSpaceIdentity?,
        identityVersion: Int?
    ) -> Bool {
        identity != nil && identityVersion == currentIdentityVersion
    }
}

public struct WorkflowSpaceBindingRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let workflowID: UUID
    public let anchorRestorationID: String
    public var displayHint: String?
    public var spaceIdentity: WorkflowSpaceIdentity?
    public var spaceIdentityVersion: Int?
    public var state: WorkflowSpaceBindingState
    public let boundAt: Date
    public var lastVerifiedAt: Date?

    public init(
        id: UUID = UUID(),
        workflowID: UUID,
        anchorRestorationID: String,
        displayHint: String? = nil,
        spaceIdentity: WorkflowSpaceIdentity? = nil,
        spaceIdentityVersion: Int? = nil,
        state: WorkflowSpaceBindingState = .verified,
        boundAt: Date = Date(),
        lastVerifiedAt: Date? = nil
    ) {
        self.id = id
        self.workflowID = workflowID
        self.anchorRestorationID = anchorRestorationID
        self.displayHint = displayHint
        self.spaceIdentity = spaceIdentity
        self.spaceIdentityVersion = spaceIdentityVersion
        self.state = state
        self.boundAt = boundAt
        self.lastVerifiedAt = lastVerifiedAt
    }
}

public struct WorkflowLifecycleState: Equatable, Sendable {
    public let workflowID: UUID
    public var lifecycle: WorkflowLifecycle
    public var bindingCount: Int
    public var hasCheckpoint: Bool
    public var completedAt: Date?

    public init(
        workflowID: UUID,
        lifecycle: WorkflowLifecycle = .open,
        bindingCount: Int = 0,
        hasCheckpoint: Bool = false,
        completedAt: Date? = nil
    ) {
        self.workflowID = workflowID
        self.lifecycle = lifecycle
        self.bindingCount = max(0, bindingCount)
        self.hasCheckpoint = hasCheckpoint
        self.completedAt = completedAt
    }
}

public enum WorkflowLifecycleEvent: Equatable, Sendable {
    case bindSpace
    case unbindSpace
    case createCheckpoint
    case resolveCheckpoint
    case complete
    case undoCompletion
    case archive
    case reopen
}

public enum WorkflowLifecycleEffect: Equatable, Sendable {
    case releaseAllBindings(workflowID: UUID)
    case closeOpenIntervals(workflowID: UUID)
    case checkpointResolved(workflowID: UUID)
    case requiresRebind(workflowID: UUID)
}

public struct WorkflowLifecycleTransition: Equatable, Sendable {
    public let state: WorkflowLifecycleState
    public let effects: [WorkflowLifecycleEffect]

    public init(state: WorkflowLifecycleState, effects: [WorkflowLifecycleEffect]) {
        self.state = state
        self.effects = effects
    }
}

public enum WorkflowLifecycleError: Error, Equatable, Sendable {
    case workflowNotOpen
    case workflowNotCompleted
    case bindingNotFound
    case checkpointNotFound
}

public enum WorkflowLifecycleEngine {
    public static func transition(
        _ state: WorkflowLifecycleState,
        event: WorkflowLifecycleEvent,
        at date: Date = Date()
    ) throws -> WorkflowLifecycleTransition {
        var next = state
        var effects: [WorkflowLifecycleEffect] = []

        switch event {
        case .bindSpace:
            guard state.lifecycle == .open else { throw WorkflowLifecycleError.workflowNotOpen }
            next.bindingCount += 1

        case .unbindSpace:
            guard state.lifecycle == .open else { throw WorkflowLifecycleError.workflowNotOpen }
            guard state.bindingCount > 0 else { throw WorkflowLifecycleError.bindingNotFound }
            next.bindingCount -= 1

        case .createCheckpoint:
            guard state.lifecycle == .open else { throw WorkflowLifecycleError.workflowNotOpen }
            next.hasCheckpoint = true

        case .resolveCheckpoint:
            guard state.lifecycle == .open else { throw WorkflowLifecycleError.workflowNotOpen }
            guard state.hasCheckpoint else { throw WorkflowLifecycleError.checkpointNotFound }
            next.hasCheckpoint = false
            effects.append(.checkpointResolved(workflowID: state.workflowID))

        case .complete:
            guard state.lifecycle == .open else { throw WorkflowLifecycleError.workflowNotOpen }
            next.lifecycle = .completed
            next.completedAt = date
            next.bindingCount = 0
            next.hasCheckpoint = false
            effects.append(.closeOpenIntervals(workflowID: state.workflowID))
            if state.bindingCount > 0 {
                effects.append(.releaseAllBindings(workflowID: state.workflowID))
            }
            if state.hasCheckpoint {
                effects.append(.checkpointResolved(workflowID: state.workflowID))
            }

        case .undoCompletion:
            guard state.lifecycle == .completed else { throw WorkflowLifecycleError.workflowNotCompleted }
            next.lifecycle = .open
            next.completedAt = nil
            next.bindingCount = 0
            effects.append(.requiresRebind(workflowID: state.workflowID))

        case .archive:
            guard state.lifecycle == .completed else { throw WorkflowLifecycleError.workflowNotCompleted }
            next.lifecycle = .archived

        case .reopen:
            guard state.lifecycle != .open else { throw WorkflowLifecycleError.workflowNotCompleted }
            next.lifecycle = .open
            next.completedAt = nil
            next.bindingCount = 0
            next.hasCheckpoint = false
            effects.append(.requiresRebind(workflowID: state.workflowID))
        }

        return WorkflowLifecycleTransition(state: next, effects: effects)
    }
}

public enum WorkflowLifecycleMigration {
    public static func lifecycle(
        rawValue: String?,
        isArchived: Bool,
        completedAt: Date?
    ) -> WorkflowLifecycle {
        if let rawValue, let lifecycle = WorkflowLifecycle(rawValue: rawValue) {
            return lifecycle
        }
        if isArchived { return .archived }
        if completedAt != nil { return .completed }
        return .open
    }
}

public enum WorkflowContextKind: String, Codable, CaseIterable, Sendable {
    case workflow
    case unbound
    case unknown
    case conflict
}

public struct WorkflowContextSnapshot: Equatable, Sendable {
    public let kind: WorkflowContextKind
    public let workflowID: UUID?
    public let confidence: WorkflowContextConfidence

    public init(
        kind: WorkflowContextKind,
        workflowID: UUID?,
        confidence: WorkflowContextConfidence
    ) {
        self.kind = kind
        self.workflowID = workflowID
        self.confidence = confidence
    }
}

public enum WorkflowSpaceResolution: Equatable, Sendable {
    case bound(workflowID: UUID)
    case unbound
    case unknown
    case conflict(workflowIDs: [UUID])

    public var snapshot: WorkflowContextSnapshot {
        switch self {
        case let .bound(workflowID):
            return WorkflowContextSnapshot(kind: .workflow, workflowID: workflowID, confidence: .verified)
        case .unbound:
            return WorkflowContextSnapshot(kind: .unbound, workflowID: nil, confidence: .verified)
        case .unknown:
            return WorkflowContextSnapshot(kind: .unknown, workflowID: nil, confidence: .unknown)
        case .conflict:
            return WorkflowContextSnapshot(kind: .conflict, workflowID: nil, confidence: .unknown)
        }
    }
}

public enum WorkflowSpaceResolutionEngine {
    public static func resolve(
        activeAnchorWorkflowIDs: [UUID],
        registryReady: Bool
    ) -> WorkflowSpaceResolution {
        guard registryReady else { return .unknown }
        let unique = Array(Set(activeAnchorWorkflowIDs)).sorted {
            $0.uuidString < $1.uuidString
        }
        switch unique.count {
        case 0: return .unbound
        case 1: return .bound(workflowID: unique[0])
        default: return .conflict(workflowIDs: unique)
        }
    }

    public static func resolve(
        currentSpaceIdentity: WorkflowSpaceIdentity?,
        bindings: [WorkflowSpaceBindingRecord],
        registryReady: Bool
    ) -> WorkflowSpaceResolution {
        guard registryReady, let currentSpaceIdentity else { return .unknown }
        let workflowIDs = bindings.compactMap { binding -> UUID? in
            guard binding.state == .verified,
                  let identity = binding.spaceIdentity,
                  identity.identifiesSameSpace(as: currentSpaceIdentity) else {
                return nil
            }
            return binding.workflowID
        }
        return resolve(activeAnchorWorkflowIDs: workflowIDs, registryReady: true)
    }
}

public struct WorkflowContextState: Equatable, Sendable {
    public var context: WorkflowContextSnapshot
    public var intervalStartedAt: Date?

    public init(
        context: WorkflowContextSnapshot = WorkflowSpaceResolution.unknown.snapshot,
        intervalStartedAt: Date? = nil
    ) {
        self.context = context
        self.intervalStartedAt = intervalStartedAt
    }
}

public enum WorkflowContextEffect: Equatable, Sendable {
    case closeInterval(
        context: WorkflowContextSnapshot,
        startedAt: Date,
        endedAt: Date
    )
    case openInterval(
        context: WorkflowContextSnapshot,
        startedAt: Date,
        source: WorkflowIntervalSource
    )
    case workflowBecameBackground(workflowID: UUID)
    case workflowBecameForeground(workflowID: UUID)
}

public struct WorkflowContextTransition: Equatable, Sendable {
    public let state: WorkflowContextState
    public let effects: [WorkflowContextEffect]

    public init(state: WorkflowContextState, effects: [WorkflowContextEffect]) {
        self.state = state
        self.effects = effects
    }
}

public enum WorkflowContextEngine {
    public static func transition(
        _ state: WorkflowContextState,
        to resolution: WorkflowSpaceResolution,
        source: WorkflowIntervalSource = .space,
        at date: Date = Date()
    ) -> WorkflowContextTransition {
        let nextContext = resolution.snapshot
        guard nextContext != state.context else {
            return WorkflowContextTransition(state: state, effects: [])
        }

        var effects: [WorkflowContextEffect] = []
        if let startedAt = state.intervalStartedAt {
            effects.append(.closeInterval(
                context: state.context,
                startedAt: startedAt,
                endedAt: max(startedAt, date)
            ))
        }
        if let workflowID = state.context.workflowID {
            effects.append(.workflowBecameBackground(workflowID: workflowID))
        }

        effects.append(.openInterval(
            context: nextContext,
            startedAt: date,
            source: source
        ))
        if let workflowID = nextContext.workflowID {
            effects.append(.workflowBecameForeground(workflowID: workflowID))
        }

        return WorkflowContextTransition(
            state: WorkflowContextState(context: nextContext, intervalStartedAt: date),
            effects: effects
        )
    }
}

public struct FocusWorkflowDepartureState: Equatable, Sendable {
    public let focusWorkflowID: UUID
    public var pendingDepartureAt: Date?
    public var pausedAt: Date?
    public var accumulatedPausedSeconds: TimeInterval

    public init(
        focusWorkflowID: UUID,
        pendingDepartureAt: Date? = nil,
        pausedAt: Date? = nil,
        accumulatedPausedSeconds: TimeInterval = 0
    ) {
        self.focusWorkflowID = focusWorkflowID
        self.pendingDepartureAt = pendingDepartureAt
        self.pausedAt = pausedAt
        self.accumulatedPausedSeconds = max(0, accumulatedPausedSeconds)
    }
}

public enum FocusWorkflowDepartureEffect: Equatable, Sendable {
    case scheduleGrace(deadline: Date)
    case cancelGrace
    case paused(departedAt: Date)
    case resumed(pausedSeconds: TimeInterval)
}

public struct FocusWorkflowDepartureTransition: Equatable, Sendable {
    public let state: FocusWorkflowDepartureState
    public let effects: [FocusWorkflowDepartureEffect]

    public init(
        state: FocusWorkflowDepartureState,
        effects: [FocusWorkflowDepartureEffect]
    ) {
        self.state = state
        self.effects = effects
    }
}

public enum FocusWorkflowDepartureEngine {
    public static func contextChanged(
        _ state: FocusWorkflowDepartureState,
        to workflowID: UUID?,
        at date: Date,
        graceSeconds: TimeInterval = 10
    ) -> FocusWorkflowDepartureTransition {
        var next = state
        var effects: [FocusWorkflowDepartureEffect] = []

        if workflowID == state.focusWorkflowID {
            if state.pendingDepartureAt != nil {
                next.pendingDepartureAt = nil
                effects.append(.cancelGrace)
            }
            if let pausedAt = state.pausedAt {
                let pausedSeconds = max(0, date.timeIntervalSince(pausedAt))
                next.pausedAt = nil
                next.accumulatedPausedSeconds += pausedSeconds
                effects.append(.resumed(pausedSeconds: pausedSeconds))
            }
            return FocusWorkflowDepartureTransition(state: next, effects: effects)
        }

        guard state.pendingDepartureAt == nil, state.pausedAt == nil else {
            return FocusWorkflowDepartureTransition(state: state, effects: [])
        }
        next.pendingDepartureAt = date
        effects.append(.scheduleGrace(deadline: date.addingTimeInterval(max(0, graceSeconds))))
        return FocusWorkflowDepartureTransition(state: next, effects: effects)
    }

    public static func graceElapsed(
        _ state: FocusWorkflowDepartureState
    ) -> FocusWorkflowDepartureTransition {
        guard let departureAt = state.pendingDepartureAt, state.pausedAt == nil else {
            return FocusWorkflowDepartureTransition(state: state, effects: [])
        }
        var next = state
        next.pendingDepartureAt = nil
        next.pausedAt = departureAt
        return FocusWorkflowDepartureTransition(
            state: next,
            effects: [.paused(departedAt: departureAt)]
        )
    }

    public static func activeElapsedSeconds(
        startedAt: Date,
        endedAt: Date,
        state: FocusWorkflowDepartureState
    ) -> Int {
        let currentPause = state.pausedAt.map {
            max(0, endedAt.timeIntervalSince($0))
        } ?? 0
        return max(
            0,
            Int(endedAt.timeIntervalSince(startedAt)
                - state.accumulatedPausedSeconds
                - currentPause)
        )
    }
}
