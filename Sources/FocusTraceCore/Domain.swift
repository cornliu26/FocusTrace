import Foundation

public enum ActivityClassification: String, Codable, CaseIterable, Sendable {
    case allowed
    case necessary
    case suspectedDistraction
    case confirmedDistraction
    case taskSwitch
    case systemInactive
    case trackerControl
}

public enum ActivityEventSource: String, Codable, CaseIterable, Sendable {
    case appActivation
    case activeSpaceChange
    case screenSleep
    case screenWake
    case sessionInactive
    case sessionActive
    case recovery
}

public enum InterruptionResolution: String, Codable, CaseIterable, Sendable {
    case unresolved
    case returnedToTask
    case markedNecessary
    case switchedTask
    case endedSession
}

public enum FocusOutcome: String, Codable, CaseIterable, Sendable {
    case pending
    case completed
    case partial
    case notCompleted
}

public enum TimelineMarkerKind: String, Codable, CaseIterable, Sendable {
    case activeSpaceChanged
    case screenSlept
    case screenWoke
    case sessionBecameInactive
    case sessionBecameActive
    case taskChanged
    case reminderSent
}

public struct AppIdentity: Codable, Equatable, Hashable, Sendable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public struct TaskRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var expectedOutcome: String
    public var allowedBundleIDs: Set<String>

    public init(
        id: UUID = UUID(),
        title: String,
        expectedOutcome: String = "",
        allowedBundleIDs: Set<String> = []
    ) {
        self.id = id
        self.title = title
        self.expectedOutcome = expectedOutcome
        self.allowedBundleIDs = allowedBundleIDs
    }
}

public struct TaskIntervalRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let taskID: UUID
    public let startedAt: Date
    public let endedAt: Date?

    public init(id: UUID = UUID(), taskID: UUID, startedAt: Date, endedAt: Date?) {
        self.id = id
        self.taskID = taskID
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct ActivityRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let app: AppIdentity
    public let startedAt: Date
    public let endedAt: Date?
    public let taskID: UUID?
    public let focusSessionID: UUID?
    public let classification: ActivityClassification
    public let source: ActivityEventSource

    public init(
        id: UUID = UUID(),
        app: AppIdentity,
        startedAt: Date,
        endedAt: Date?,
        taskID: UUID?,
        focusSessionID: UUID?,
        classification: ActivityClassification,
        source: ActivityEventSource = .appActivation
    ) {
        self.id = id
        self.app = app
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.taskID = taskID
        self.focusSessionID = focusSessionID
        self.classification = classification
        self.source = source
    }

    public func duration(relativeTo now: Date = Date()) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }
}

public struct FocusSessionRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let taskID: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let targetSeconds: Int
    public let outcome: FocusOutcome
    public let difficulty: Int?
    public let confirmedDistractionCount: Int

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        startedAt: Date,
        endedAt: Date?,
        targetSeconds: Int,
        outcome: FocusOutcome,
        difficulty: Int?,
        confirmedDistractionCount: Int
    ) {
        self.id = id
        self.taskID = taskID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.targetSeconds = targetSeconds
        self.outcome = outcome
        self.difficulty = difficulty
        self.confirmedDistractionCount = confirmedDistractionCount
    }

    public var reachedTarget: Bool {
        guard let endedAt else { return false }
        return endedAt.timeIntervalSince(startedAt) >= Double(targetSeconds)
    }

    public var isSuccessful: Bool {
        reachedTarget && outcome == .completed && confirmedDistractionCount == 0
    }
}

public struct InterruptionRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let activityID: UUID
    public let focusSessionID: UUID
    public let taskID: UUID
    public let app: AppIdentity
    public let detectedAt: Date
    public let resolvedAt: Date?
    public let resolution: InterruptionResolution

    public init(
        id: UUID = UUID(),
        activityID: UUID,
        focusSessionID: UUID,
        taskID: UUID,
        app: AppIdentity,
        detectedAt: Date,
        resolvedAt: Date?,
        resolution: InterruptionResolution
    ) {
        self.id = id
        self.activityID = activityID
        self.focusSessionID = focusSessionID
        self.taskID = taskID
        self.app = app
        self.detectedAt = detectedAt
        self.resolvedAt = resolvedAt
        self.resolution = resolution
    }
}

public struct TrainingPlanRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let version: Int
    public let effectiveAt: Date
    public let focusMinutes: Int
    public let sessionsPerDay: Int
    public let breakMinutes: Int
    public let reminderThresholdSeconds: Int
    public let reason: String
    public let previousPlanID: UUID?

    public init(
        id: UUID = UUID(),
        version: Int,
        effectiveAt: Date = Date(),
        focusMinutes: Int,
        sessionsPerDay: Int = 2,
        breakMinutes: Int = 5,
        reminderThresholdSeconds: Int = 20,
        reason: String,
        previousPlanID: UUID? = nil
    ) {
        self.id = id
        self.version = version
        self.effectiveAt = effectiveAt
        self.focusMinutes = focusMinutes
        self.sessionsPerDay = sessionsPerDay
        self.breakMinutes = breakMinutes
        self.reminderThresholdSeconds = reminderThresholdSeconds
        self.reason = reason
        self.previousPlanID = previousPlanID
    }
}

public struct TimelineMarkerRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let kind: TimelineMarkerKind
    public let taskID: UUID?

    public init(id: UUID = UUID(), date: Date, kind: TimelineMarkerKind, taskID: UUID? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.taskID = taskID
    }
}
