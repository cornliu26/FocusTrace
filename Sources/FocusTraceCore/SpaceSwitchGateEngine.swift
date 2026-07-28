import Foundation

public enum SpaceSwitchReason: String, Codable, CaseIterable, Sendable {
    case reachedCheckpoint
    case waitingForResult
    case forcedInterruption
    case unstructured
}

public struct SpaceSwitchGateContext: Equatable, Sendable {
    public let origin: WorkflowSpaceResolution
    public let destination: WorkflowSpaceResolution
    public let startedAt: Date
    public let expiresAt: Date

    public init(
        origin: WorkflowSpaceResolution,
        destination: WorkflowSpaceResolution,
        startedAt: Date,
        expiresAt: Date
    ) {
        self.origin = origin
        self.destination = destination
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }
}

public enum SpaceSwitchGateObservation: Equatable, Sendable {
    case returnedToOrigin
    case stayedOnDestination
    case destinationChanged(SpaceSwitchGateContext)
    case cannotResolve(WorkflowSpaceResolution)
}

public struct SpaceSwitchJourney: Equatable, Sendable {
    public let origin: WorkflowSpaceResolution
    public let candidateDestination: WorkflowSpaceResolution?
    public let startedAt: Date
    public let lastChangedAt: Date
    public let eventCount: Int

    public init(
        origin: WorkflowSpaceResolution,
        candidateDestination: WorkflowSpaceResolution?,
        startedAt: Date,
        lastChangedAt: Date,
        eventCount: Int = 1
    ) {
        self.origin = origin
        self.candidateDestination = candidateDestination
        self.startedAt = startedAt
        self.lastChangedAt = lastChangedAt
        self.eventCount = max(1, eventCount)
    }
}

public enum SpaceSwitchJourneyOutcome: Equatable, Sendable {
    case notSettled
    case unresolved(WorkflowSpaceResolution)
    case unchanged(WorkflowSpaceResolution)
    case applyWithoutGate(WorkflowSpaceResolution)
    case presentGate(SpaceSwitchGateContext)
}

/// Coalesces the several macOS Space notifications produced while the user is
/// still navigating. The first verified context remains the origin, and only
/// the final stable destination is allowed to become a workflow switch.
public enum SpaceSwitchJourneyEngine {
    public static let settleDelaySeconds: TimeInterval = 1.2

    public static func beginOrExtend(
        _ existing: SpaceSwitchJourney?,
        origin: WorkflowSpaceResolution,
        candidateDestination: WorkflowSpaceResolution? = nil,
        at date: Date
    ) -> SpaceSwitchJourney? {
        if let existing {
            return SpaceSwitchJourney(
                origin: existing.origin,
                candidateDestination: verified(candidateDestination)
                    ?? existing.candidateDestination,
                startedAt: existing.startedAt,
                lastChangedAt: date,
                eventCount: existing.eventCount + 1
            )
        }
        guard isVerified(origin) else { return nil }
        return SpaceSwitchJourney(
            origin: origin,
            candidateDestination: verified(candidateDestination),
            startedAt: date,
            lastChangedAt: date,
            eventCount: 1
        )
    }

    public static func finish(
        _ journey: SpaceSwitchJourney,
        finalDestination: WorkflowSpaceResolution,
        at date: Date,
        isGateEnabled: Bool
    ) -> SpaceSwitchJourneyOutcome {
        guard date.timeIntervalSince(journey.lastChangedAt)
                >= settleDelaySeconds else {
            return .notSettled
        }
        guard isVerified(finalDestination) else {
            return .unresolved(finalDestination)
        }
        guard finalDestination != journey.origin else {
            return .unchanged(finalDestination)
        }
        if let pending = SpaceSwitchGateEngine.begin(
            origin: journey.origin,
            destination: finalDestination,
            at: date,
            isEnabled: isGateEnabled
        ) {
            return .presentGate(pending)
        }
        return .applyWithoutGate(finalDestination)
    }

    private static func verified(
        _ resolution: WorkflowSpaceResolution?
    ) -> WorkflowSpaceResolution? {
        guard let resolution, isVerified(resolution) else { return nil }
        return resolution
    }

    private static func isVerified(
        _ resolution: WorkflowSpaceResolution
    ) -> Bool {
        switch resolution {
        case .bound, .unbound:
            return true
        case .unknown, .conflict:
            return false
        }
    }
}

/// Keeps the product rule independent from AppKit and the overlay:
/// leaving a bound workflow starts one short decision window, returning to
/// the origin cancels it, and uncertain Space identity is never guessed.
public enum SpaceSwitchGateEngine {
    public static let decisionWindowSeconds: TimeInterval = 10

    public static func begin(
        origin: WorkflowSpaceResolution,
        destination: WorkflowSpaceResolution,
        at date: Date,
        isEnabled: Bool
    ) -> SpaceSwitchGateContext? {
        guard isEnabled,
              isVerified(origin),
              isVerified(destination),
              origin != destination,
              workflowID(in: origin) != nil
                || workflowID(in: destination) != nil
        else {
            return nil
        }
        return SpaceSwitchGateContext(
            origin: origin,
            destination: destination,
            startedAt: date,
            expiresAt: date.addingTimeInterval(decisionWindowSeconds)
        )
    }

    public static func observe(
        _ resolution: WorkflowSpaceResolution,
        while pending: SpaceSwitchGateContext
    ) -> SpaceSwitchGateObservation {
        guard isVerified(resolution) else {
            return .cannotResolve(resolution)
        }
        if resolution == pending.origin {
            return .returnedToOrigin
        }
        if resolution == pending.destination {
            return .stayedOnDestination
        }
        return .destinationChanged(
            SpaceSwitchGateContext(
                origin: pending.origin,
                destination: resolution,
                startedAt: pending.startedAt,
                expiresAt: pending.expiresAt
            )
        )
    }

    /// Reopens a complete decision window after the user's final desktop has
    /// stabilized. This prevents late or repeated macOS Space notifications
    /// from consuming the time in which the user can actually respond.
    public static func refreshed(
        _ pending: SpaceSwitchGateContext,
        destination: WorkflowSpaceResolution,
        at date: Date
    ) -> SpaceSwitchGateContext? {
        guard isVerified(destination), destination != pending.origin else {
            return nil
        }
        return SpaceSwitchGateContext(
            origin: pending.origin,
            destination: destination,
            startedAt: date,
            expiresAt: date.addingTimeInterval(decisionWindowSeconds)
        )
    }

    public static func hasExpired(
        _ pending: SpaceSwitchGateContext,
        at date: Date
    ) -> Bool {
        date >= pending.expiresAt
    }

    public static func originWorkflowID(
        in pending: SpaceSwitchGateContext
    ) -> UUID? {
        workflowID(in: pending.origin)
    }

    public static func destinationWorkflowID(
        in pending: SpaceSwitchGateContext
    ) -> UUID? {
        workflowID(in: pending.destination)
    }

    private static func workflowID(
        in resolution: WorkflowSpaceResolution
    ) -> UUID? {
        guard case let .bound(workflowID) = resolution else { return nil }
        return workflowID
    }

    private static func isVerified(
        _ resolution: WorkflowSpaceResolution
    ) -> Bool {
        switch resolution {
        case .bound, .unbound:
            return true
        case .unknown, .conflict:
            return false
        }
    }
}
