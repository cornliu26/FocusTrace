import Foundation

/// A stable, explicit endpoint for one workflow transition.
///
/// Conflict details are intentionally not retained: the transition is
/// unresolved and no candidate workflow IDs should leak into analysis.
public enum WorkflowTransitionEndpointKind: String, Codable, CaseIterable, Sendable {
    case workflow
    case unbound
    case unknown
    case conflict
}

public struct WorkflowTransitionEndpoint: Codable, Equatable, Hashable, Sendable {
    public let kind: WorkflowTransitionEndpointKind
    public let workflowID: UUID?

    public init(
        kind: WorkflowTransitionEndpointKind,
        workflowID: UUID? = nil
    ) {
        self.kind = kind
        self.workflowID = kind == .workflow ? workflowID : nil
    }

    public init(resolution: WorkflowSpaceResolution) {
        switch resolution {
        case let .bound(workflowID):
            self.init(kind: .workflow, workflowID: workflowID)
        case .unbound:
            self.init(kind: .unbound)
        case .unknown:
            self.init(kind: .unknown)
        case .conflict:
            self.init(kind: .conflict)
        }
    }

    public var resolution: WorkflowSpaceResolution {
        switch kind {
        case .workflow:
            return workflowID.map {
                .bound(workflowID: $0)
            } ?? .unknown
        case .unbound:
            return .unbound
        case .unknown:
            return .unknown
        case .conflict:
            return .conflict(workflowIDs: [])
        }
    }
}

public enum WorkflowTransitionSource: String, Codable, CaseIterable, Sendable {
    case space
    case manual
}

public enum WorkflowTransitionOutcome: String, Codable, CaseIterable, Sendable {
    /// The user selected one of the structured reasons.
    case confirmed
    /// The decision window expired and FocusTrace safely let the switch proceed.
    case timedOut
    /// The user navigated back to the origin before confirming a switch.
    case cancelled
    /// The workflow changed while the confirmation gate was disabled.
    case automatic
    /// Space identity could not be verified; no behavioral claim may use it.
    case unresolved
}

/// One native semantic unit: the complete navigation burst from its verified
/// origin to its final resolved destination. Raw intermediate Spaces remain
/// available as timeline markers but are never treated as workflow switches.
public struct WorkflowTransitionRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let source: WorkflowTransitionSource
    public let navigationStartedAt: Date
    public let settledAt: Date
    public let resolvedAt: Date
    public let origin: WorkflowTransitionEndpoint
    public let destination: WorkflowTransitionEndpoint
    public let outcome: WorkflowTransitionOutcome
    public let reason: SpaceSwitchReason?
    public let interventionTrigger: WorkflowInterventionTrigger?
    public let navigationEventCount: Int

    public init(
        id: UUID = UUID(),
        source: WorkflowTransitionSource = .space,
        navigationStartedAt: Date,
        settledAt: Date,
        resolvedAt: Date,
        origin: WorkflowTransitionEndpoint,
        destination: WorkflowTransitionEndpoint,
        outcome: WorkflowTransitionOutcome,
        reason: SpaceSwitchReason?,
        interventionTrigger: WorkflowInterventionTrigger? = nil,
        navigationEventCount: Int
    ) {
        self.id = id
        self.source = source
        self.navigationStartedAt = navigationStartedAt
        self.settledAt = settledAt
        self.resolvedAt = resolvedAt
        self.origin = origin
        self.destination = destination
        self.outcome = outcome
        self.reason = reason
        self.interventionTrigger = interventionTrigger
        self.navigationEventCount = max(1, navigationEventCount)
    }
}

/// In-memory context retained while the visible gate is waiting for a reason
/// or following another navigation burst.
public struct PendingWorkflowTransition: Equatable, Sendable {
    public let id: UUID
    public let source: WorkflowTransitionSource
    public let navigationStartedAt: Date
    public let origin: WorkflowTransitionEndpoint
    public let destination: WorkflowTransitionEndpoint
    public let settledAt: Date
    public let interventionTrigger: WorkflowInterventionTrigger?
    public let navigationEventCount: Int

    public init(
        id: UUID = UUID(),
        source: WorkflowTransitionSource = .space,
        navigationStartedAt: Date,
        origin: WorkflowTransitionEndpoint,
        destination: WorkflowTransitionEndpoint,
        settledAt: Date,
        interventionTrigger: WorkflowInterventionTrigger? = nil,
        navigationEventCount: Int
    ) {
        self.id = id
        self.source = source
        self.navigationStartedAt = navigationStartedAt
        self.origin = origin
        self.destination = destination
        self.settledAt = settledAt
        self.interventionTrigger = interventionTrigger
        self.navigationEventCount = max(1, navigationEventCount)
    }

    public func updating(
        destination: WorkflowTransitionEndpoint,
        settledAt: Date,
        additionalNavigationEvents: Int
    ) -> PendingWorkflowTransition {
        PendingWorkflowTransition(
            id: id,
            source: source,
            navigationStartedAt: navigationStartedAt,
            origin: origin,
            destination: destination,
            settledAt: settledAt,
            interventionTrigger: interventionTrigger,
            navigationEventCount: navigationEventCount
                + max(0, additionalNavigationEvents)
        )
    }

    public func resolved(
        at date: Date,
        destination finalDestination: WorkflowTransitionEndpoint? = nil,
        outcome: WorkflowTransitionOutcome,
        reason: SpaceSwitchReason?
    ) -> WorkflowTransitionRecord {
        WorkflowTransitionRecord(
            id: id,
            source: source,
            navigationStartedAt: navigationStartedAt,
            settledAt: settledAt,
            resolvedAt: date,
            origin: origin,
            destination: finalDestination ?? destination,
            outcome: outcome,
            reason: reason,
            interventionTrigger: interventionTrigger,
            navigationEventCount: navigationEventCount
        )
    }
}
