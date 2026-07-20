import Foundation
import FocusTraceCore

final class FocusTaskModel: Codable, Identifiable {
    var id: UUID
    var title: String
    var expectedOutcome: String
    var allowedBundleIDs: [String]
    var createdAt: Date
    var isArchived: Bool
    var workflowLifecycleRaw: String?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        expectedOutcome: String = "",
        allowedBundleIDs: [String] = [],
        createdAt: Date = Date(),
        isArchived: Bool = false,
        workflowLifecycle: WorkflowLifecycle = .open,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.expectedOutcome = expectedOutcome
        self.allowedBundleIDs = allowedBundleIDs
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.workflowLifecycleRaw = workflowLifecycle.rawValue
        self.completedAt = completedAt
    }

    var workflowLifecycle: WorkflowLifecycle {
        WorkflowLifecycleMigration.lifecycle(
            rawValue: workflowLifecycleRaw,
            isArchived: isArchived,
            completedAt: completedAt
        )
    }
}

final class TaskIntervalModel: Codable, Identifiable {
    var id: UUID
    var taskID: UUID
    var startedAt: Date
    var endedAt: Date?
    var workflowSourceRaw: String?

    init(
        id: UUID = UUID(),
        taskID: UUID,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        workflowSource: WorkflowIntervalSource = .manual
    ) {
        self.id = id
        self.taskID = taskID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.workflowSourceRaw = workflowSource.rawValue
    }

    var workflowSource: WorkflowIntervalSource {
        get { workflowSourceRaw.flatMap(WorkflowIntervalSource.init(rawValue:)) ?? .manual }
        set { workflowSourceRaw = newValue.rawValue }
    }
}

final class ActivitySegmentModel: Codable, Identifiable {
    var id: UUID
    var appName: String
    var bundleID: String
    var startedAt: Date
    var endedAt: Date?
    var taskID: UUID?
    var focusSessionID: UUID?
    var classificationRaw: String
    var sourceRaw: String
    var isAllowedApp: Bool
    var crossedReminderThreshold: Bool

    init(
        id: UUID = UUID(),
        appName: String,
        bundleID: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        taskID: UUID? = nil,
        focusSessionID: UUID? = nil,
        classification: ActivityClassification = .allowed,
        source: ActivityEventSource = .appActivation,
        isAllowedApp: Bool = true,
        crossedReminderThreshold: Bool = false
    ) {
        self.id = id
        self.appName = appName
        self.bundleID = bundleID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.taskID = taskID
        self.focusSessionID = focusSessionID
        self.classificationRaw = classification.rawValue
        self.sourceRaw = source.rawValue
        self.isAllowedApp = isAllowedApp
        self.crossedReminderThreshold = crossedReminderThreshold
    }

    var classification: ActivityClassification {
        get { ActivityClassification(rawValue: classificationRaw) ?? .allowed }
        set { classificationRaw = newValue.rawValue }
    }

    var source: ActivityEventSource {
        get { ActivityEventSource(rawValue: sourceRaw) ?? .appActivation }
        set { sourceRaw = newValue.rawValue }
    }
}

final class FocusSessionModel: Codable, Identifiable {
    var id: UUID
    var taskID: UUID
    var startedAt: Date
    var endedAt: Date?
    var targetSeconds: Int
    var outcomeRaw: String
    var difficulty: Int?
    var confirmedDistractionCount: Int
    var targetNotificationSent: Bool
    var pausedAt: Date?
    var accumulatedPausedSeconds: TimeInterval?

    init(
        id: UUID = UUID(),
        taskID: UUID,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        targetSeconds: Int,
        outcome: FocusOutcome = .pending,
        difficulty: Int? = nil,
        confirmedDistractionCount: Int = 0,
        targetNotificationSent: Bool = false,
        pausedAt: Date? = nil,
        accumulatedPausedSeconds: TimeInterval? = 0
    ) {
        self.id = id
        self.taskID = taskID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.targetSeconds = targetSeconds
        self.outcomeRaw = outcome.rawValue
        self.difficulty = difficulty
        self.confirmedDistractionCount = confirmedDistractionCount
        self.targetNotificationSent = targetNotificationSent
        self.pausedAt = pausedAt
        self.accumulatedPausedSeconds = accumulatedPausedSeconds
    }

    var outcome: FocusOutcome {
        get { FocusOutcome(rawValue: outcomeRaw) ?? .pending }
        set { outcomeRaw = newValue.rawValue }
    }
}

final class InterruptionModel: Codable, Identifiable {
    var id: UUID
    var activityID: UUID
    var focusSessionID: UUID
    var taskID: UUID
    var appName: String
    var bundleID: String
    var detectedAt: Date
    var resolvedAt: Date?
    var resolutionRaw: String

    init(
        id: UUID = UUID(),
        activityID: UUID,
        focusSessionID: UUID,
        taskID: UUID,
        appName: String,
        bundleID: String,
        detectedAt: Date = Date(),
        resolvedAt: Date? = nil,
        resolution: InterruptionResolution = .unresolved
    ) {
        self.id = id
        self.activityID = activityID
        self.focusSessionID = focusSessionID
        self.taskID = taskID
        self.appName = appName
        self.bundleID = bundleID
        self.detectedAt = detectedAt
        self.resolvedAt = resolvedAt
        self.resolutionRaw = resolution.rawValue
    }

    var resolution: InterruptionResolution {
        get { InterruptionResolution(rawValue: resolutionRaw) ?? .unresolved }
        set { resolutionRaw = newValue.rawValue }
    }
}

final class TrainingPlanModel: Codable, Identifiable {
    var id: UUID
    var version: Int
    var effectiveAt: Date
    var focusMinutes: Int
    var sessionsPerDay: Int
    var breakMinutes: Int
    var reminderThresholdSeconds: Int
    var reason: String
    var previousPlanID: UUID?

    init(
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

final class TimelineMarkerModel: Codable, Identifiable {
    var id: UUID
    var date: Date
    var kindRaw: String
    var taskID: UUID?

    init(id: UUID = UUID(), date: Date = Date(), kind: TimelineMarkerKind, taskID: UUID? = nil) {
        self.id = id
        self.date = date
        self.kindRaw = kind.rawValue
        self.taskID = taskID
    }

    var kind: TimelineMarkerKind {
        get { TimelineMarkerKind(rawValue: kindRaw) ?? .activeSpaceChanged }
        set { kindRaw = newValue.rawValue }
    }
}

final class TaskParkingModel: Codable, Identifiable {
    var id: UUID
    var taskID: UUID
    var parkedAt: Date
    var resumeCue: String
    var remindAt: Date?
    var switchedToTaskID: UUID?
    var resumedAt: Date?
    var dismissedAt: Date?
    var reminderSentAt: Date?

    init(
        id: UUID = UUID(),
        taskID: UUID,
        parkedAt: Date = Date(),
        resumeCue: String,
        remindAt: Date? = nil,
        switchedToTaskID: UUID? = nil,
        resumedAt: Date? = nil,
        dismissedAt: Date? = nil,
        reminderSentAt: Date? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.parkedAt = parkedAt
        self.resumeCue = resumeCue
        self.remindAt = remindAt
        self.switchedToTaskID = switchedToTaskID
        self.resumedAt = resumedAt
        self.dismissedAt = dismissedAt
        self.reminderSentAt = reminderSentAt
    }

    var isActive: Bool {
        resumedAt == nil && dismissedAt == nil
    }
}

final class WorkflowSpaceBindingModel: Codable, Identifiable {
    var id: UUID
    var workflowID: UUID
    var anchorRestorationID: String
    var displayHint: String?
    var stateRaw: String
    var boundAt: Date
    var lastVerifiedAt: Date?

    init(
        id: UUID = UUID(),
        workflowID: UUID,
        anchorRestorationID: String,
        displayHint: String? = nil,
        state: WorkflowSpaceBindingState = .verified,
        boundAt: Date = Date(),
        lastVerifiedAt: Date? = nil
    ) {
        self.id = id
        self.workflowID = workflowID
        self.anchorRestorationID = anchorRestorationID
        self.displayHint = displayHint
        self.stateRaw = state.rawValue
        self.boundAt = boundAt
        self.lastVerifiedAt = lastVerifiedAt
    }

    var state: WorkflowSpaceBindingState {
        get { WorkflowSpaceBindingState(rawValue: stateRaw) ?? .needsRebind }
        set { stateRaw = newValue.rawValue }
    }
}

@MainActor
final class FocusTraceStore {
    private struct Snapshot: Codable {
        var tasks: [FocusTaskModel]
        var taskIntervals: [TaskIntervalModel]
        var activities: [ActivitySegmentModel]
        var focusSessions: [FocusSessionModel]
        var interruptions: [InterruptionModel]
        var trainingPlans: [TrainingPlanModel]
        var markers: [TimelineMarkerModel]
        var taskParkings: [TaskParkingModel]
        var workflowSpaceBindings: [WorkflowSpaceBindingModel]

        init(
            tasks: [FocusTaskModel],
            taskIntervals: [TaskIntervalModel],
            activities: [ActivitySegmentModel],
            focusSessions: [FocusSessionModel],
            interruptions: [InterruptionModel],
            trainingPlans: [TrainingPlanModel],
            markers: [TimelineMarkerModel],
            taskParkings: [TaskParkingModel],
            workflowSpaceBindings: [WorkflowSpaceBindingModel]
        ) {
            self.tasks = tasks
            self.taskIntervals = taskIntervals
            self.activities = activities
            self.focusSessions = focusSessions
            self.interruptions = interruptions
            self.trainingPlans = trainingPlans
            self.markers = markers
            self.taskParkings = taskParkings
            self.workflowSpaceBindings = workflowSpaceBindings
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tasks = try container.decodeIfPresent([FocusTaskModel].self, forKey: .tasks) ?? []
            taskIntervals = try container.decodeIfPresent([TaskIntervalModel].self, forKey: .taskIntervals) ?? []
            activities = try container.decodeIfPresent([ActivitySegmentModel].self, forKey: .activities) ?? []
            focusSessions = try container.decodeIfPresent([FocusSessionModel].self, forKey: .focusSessions) ?? []
            interruptions = try container.decodeIfPresent([InterruptionModel].self, forKey: .interruptions) ?? []
            trainingPlans = try container.decodeIfPresent([TrainingPlanModel].self, forKey: .trainingPlans) ?? []
            markers = try container.decodeIfPresent([TimelineMarkerModel].self, forKey: .markers) ?? []
            taskParkings = try container.decodeIfPresent([TaskParkingModel].self, forKey: .taskParkings) ?? []
            workflowSpaceBindings = try container.decodeIfPresent(
                [WorkflowSpaceBindingModel].self,
                forKey: .workflowSpaceBindings
            ) ?? []
        }
    }

    private(set) var tasks: [FocusTaskModel] = []
    private(set) var taskIntervals: [TaskIntervalModel] = []
    private(set) var activities: [ActivitySegmentModel] = []
    private(set) var focusSessions: [FocusSessionModel] = []
    private(set) var interruptions: [InterruptionModel] = []
    private(set) var trainingPlans: [TrainingPlanModel] = []
    private(set) var markers: [TimelineMarkerModel] = []
    private(set) var taskParkings: [TaskParkingModel] = []
    private(set) var workflowSpaceBindings: [WorkflowSpaceBindingModel] = []
    private(set) var loadWarning: String?

    private let fileURL: URL?
    private var pendingSave: Task<Void, Never>?

    init(inMemory: Bool = false) throws {
        if inMemory {
            fileURL = nil
            return
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("FocusTrace", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("store.json")
        fileURL = url
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(Snapshot.self, from: Data(contentsOf: url))
            tasks = snapshot.tasks
            taskIntervals = snapshot.taskIntervals
            activities = snapshot.activities
            focusSessions = snapshot.focusSessions
            interruptions = snapshot.interruptions
            trainingPlans = snapshot.trainingPlans
            markers = snapshot.markers
            taskParkings = snapshot.taskParkings
            workflowSpaceBindings = snapshot.workflowSpaceBindings
        } catch {
            let backup = directory.appendingPathComponent("store-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            loadWarning = "本地数据文件无法读取，已保留备份：\(backup.lastPathComponent)"
        }
    }

    func save() throws {
        guard let fileURL else { return }
        pendingSave?.cancel()
        let data = try encodedSnapshot()
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func flush() throws {
        pendingSave?.cancel()
        pendingSave = nil
        guard let fileURL else { return }
        try encodedSnapshot().write(to: fileURL, options: .atomic)
    }

    func insert(_ value: FocusTaskModel) { tasks.append(value) }
    func insert(_ value: TaskIntervalModel) { taskIntervals.append(value) }
    func insert(_ value: ActivitySegmentModel) { activities.append(value) }
    func insert(_ value: FocusSessionModel) { focusSessions.append(value) }
    func insert(_ value: InterruptionModel) { interruptions.append(value) }
    func insert(_ value: TrainingPlanModel) { trainingPlans.append(value) }
    func insert(_ value: TimelineMarkerModel) { markers.append(value) }
    func insert(_ value: TaskParkingModel) { taskParkings.append(value) }
    func insert(_ value: WorkflowSpaceBindingModel) { workflowSpaceBindings.append(value) }

    func delete(_ value: FocusTaskModel) { tasks.removeAll { $0.id == value.id } }
    func delete(_ value: TaskIntervalModel) { taskIntervals.removeAll { $0.id == value.id } }
    func delete(_ value: ActivitySegmentModel) { activities.removeAll { $0.id == value.id } }
    func delete(_ value: FocusSessionModel) { focusSessions.removeAll { $0.id == value.id } }
    func delete(_ value: InterruptionModel) { interruptions.removeAll { $0.id == value.id } }
    func delete(_ value: TrainingPlanModel) { trainingPlans.removeAll { $0.id == value.id } }
    func delete(_ value: TimelineMarkerModel) { markers.removeAll { $0.id == value.id } }
    func delete(_ value: TaskParkingModel) { taskParkings.removeAll { $0.id == value.id } }
    func delete(_ value: WorkflowSpaceBindingModel) { workflowSpaceBindings.removeAll { $0.id == value.id } }

    private func encodedSnapshot() throws -> Data {
        let snapshot = Snapshot(
            tasks: tasks,
            taskIntervals: taskIntervals,
            activities: activities,
            focusSessions: focusSessions,
            interruptions: interruptions,
            trainingPlans: trainingPlans,
            markers: markers,
            taskParkings: taskParkings,
            workflowSpaceBindings: workflowSpaceBindings
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }
}

extension FocusTaskModel {
    var record: TaskRecord {
        TaskRecord(
            id: id,
            title: title,
            expectedOutcome: expectedOutcome,
            allowedBundleIDs: Set(allowedBundleIDs)
        )
    }
}

extension TaskIntervalModel {
    var record: TaskIntervalRecord {
        TaskIntervalRecord(
            id: id,
            taskID: taskID,
            startedAt: startedAt,
            endedAt: endedAt,
            workflowSource: workflowSource
        )
    }
}

extension ActivitySegmentModel {
    var record: ActivityRecord {
        ActivityRecord(
            id: id,
            app: AppIdentity(bundleID: bundleID, name: appName),
            startedAt: startedAt,
            endedAt: endedAt,
            taskID: taskID,
            focusSessionID: focusSessionID,
            classification: classification,
            source: source
        )
    }
}

extension FocusSessionModel {
    var record: FocusSessionRecord {
        FocusSessionRecord(
            id: id,
            taskID: taskID,
            startedAt: startedAt,
            endedAt: endedAt,
            targetSeconds: targetSeconds,
            outcome: outcome,
            difficulty: difficulty,
            confirmedDistractionCount: confirmedDistractionCount,
            pausedSeconds: accumulatedPausedSeconds
        )
    }
}

extension InterruptionModel {
    var record: InterruptionRecord {
        InterruptionRecord(
            id: id,
            activityID: activityID,
            focusSessionID: focusSessionID,
            taskID: taskID,
            app: AppIdentity(bundleID: bundleID, name: appName),
            detectedAt: detectedAt,
            resolvedAt: resolvedAt,
            resolution: resolution
        )
    }
}

extension TrainingPlanModel {
    var record: TrainingPlanRecord {
        TrainingPlanRecord(
            id: id,
            version: version,
            effectiveAt: effectiveAt,
            focusMinutes: focusMinutes,
            sessionsPerDay: sessionsPerDay,
            breakMinutes: breakMinutes,
            reminderThresholdSeconds: reminderThresholdSeconds,
            reason: reason,
            previousPlanID: previousPlanID
        )
    }
}

extension TimelineMarkerModel {
    var record: TimelineMarkerRecord {
        TimelineMarkerRecord(id: id, date: date, kind: kind, taskID: taskID)
    }
}

extension TaskParkingModel {
    var record: TaskParkingRecord {
        TaskParkingRecord(
            id: id,
            taskID: taskID,
            parkedAt: parkedAt,
            resumeCue: resumeCue,
            remindAt: remindAt,
            switchedToTaskID: switchedToTaskID,
            resumedAt: resumedAt,
            dismissedAt: dismissedAt,
            reminderSentAt: reminderSentAt
        )
    }
}

extension WorkflowSpaceBindingModel {
    var record: WorkflowSpaceBindingRecord {
        WorkflowSpaceBindingRecord(
            id: id,
            workflowID: workflowID,
            anchorRestorationID: anchorRestorationID,
            displayHint: displayHint,
            state: state,
            boundAt: boundAt,
            lastVerifiedAt: lastVerifiedAt
        )
    }
}
