import Foundation

public struct DailySummary: Equatable, Sendable {
    public let appSwitchCount: Int
    public let taskSwitchCount: Int
    public let workflowSwitchCount: Int
    public let suspectedDistractionCount: Int
    public let confirmedDistractionCount: Int
    public let averageReturnLatency: TimeInterval?
    public let medianFocusStreak: TimeInterval?
    public let taskParkingCount: Int
    public let resumedTaskCount: Int
    public let averageTaskResumeLatency: TimeInterval?
    public let appDurations: [String: TimeInterval]
    public let taskDurations: [UUID: TimeInterval]

    public init(
        appSwitchCount: Int,
        taskSwitchCount: Int,
        workflowSwitchCount: Int = 0,
        suspectedDistractionCount: Int,
        confirmedDistractionCount: Int,
        averageReturnLatency: TimeInterval?,
        medianFocusStreak: TimeInterval?,
        taskParkingCount: Int,
        resumedTaskCount: Int,
        averageTaskResumeLatency: TimeInterval?,
        appDurations: [String: TimeInterval],
        taskDurations: [UUID: TimeInterval]
    ) {
        self.appSwitchCount = appSwitchCount
        self.taskSwitchCount = taskSwitchCount
        self.workflowSwitchCount = workflowSwitchCount
        self.suspectedDistractionCount = suspectedDistractionCount
        self.confirmedDistractionCount = confirmedDistractionCount
        self.averageReturnLatency = averageReturnLatency
        self.medianFocusStreak = medianFocusStreak
        self.taskParkingCount = taskParkingCount
        self.resumedTaskCount = resumedTaskCount
        self.averageTaskResumeLatency = averageTaskResumeLatency
        self.appDurations = appDurations
        self.taskDurations = taskDurations
    }
}

public enum MetricsEngine {
    public static func dailySummary(
        activities: [ActivityRecord],
        taskIntervals: [TaskIntervalRecord],
        interruptions: [InterruptionRecord],
        taskParkings: [TaskParkingRecord] = [],
        now: Date = Date()
    ) -> DailySummary {
        let sorted = activities.sorted { $0.startedAt < $1.startedAt }
        let visible = sorted.filter { $0.classification != .systemInactive }
        var switches = 0
        for pair in zip(visible, visible.dropFirst()) where pair.0.app.bundleID != pair.1.app.bundleID {
            switches += 1
        }

        var appDurations: [String: TimeInterval] = [:]
        var taskDurations: [UUID: TimeInterval] = [:]
        for item in visible where item.classification != .trackerControl {
            let duration = item.duration(relativeTo: now)
            appDurations[item.app.name, default: 0] += duration
            if let taskID = item.taskID {
                taskDurations[taskID, default: 0] += duration
            }
        }

        let suspected = interruptions.filter { $0.resolution == .unresolved }.count
        let confirmed = interruptions.filter {
            $0.resolution == .returnedToTask || $0.resolution == .endedSession
        }.count
        let latencies = interruptions.compactMap { interruption -> TimeInterval? in
            guard interruption.resolution == .returnedToTask, let resolvedAt = interruption.resolvedAt else {
                return nil
            }
            return max(0, resolvedAt.timeIntervalSince(interruption.detectedAt))
        }
        let averageLatency = latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)

        let resumeLatencies = taskParkings.compactMap(\.resumeLatency)
        let averageTaskResumeLatency = resumeLatencies.isEmpty
            ? nil
            : resumeLatencies.reduce(0, +) / Double(resumeLatencies.count)

        let streaks = TrainingEngine.baselineStreaks(from: visible).sorted()
        let median: TimeInterval?
        if streaks.isEmpty {
            median = nil
        } else if streaks.count.isMultiple(of: 2) {
            let middle = streaks.count / 2
            median = (streaks[middle - 1] + streaks[middle]) / 2
        } else {
            median = streaks[streaks.count / 2]
        }

        let orderedTaskIntervals = taskIntervals.sorted { $0.startedAt < $1.startedAt }
        let subsequentTaskIntervals = orderedTaskIntervals.dropFirst()

        return DailySummary(
            appSwitchCount: switches,
            taskSwitchCount: subsequentTaskIntervals.filter {
                $0.effectiveWorkflowSource == .manual
            }.count,
            workflowSwitchCount: subsequentTaskIntervals.filter {
                $0.effectiveWorkflowSource == .space
            }.count,
            suspectedDistractionCount: suspected,
            confirmedDistractionCount: confirmed,
            averageReturnLatency: averageLatency,
            medianFocusStreak: median,
            taskParkingCount: taskParkings.count,
            resumedTaskCount: taskParkings.filter { $0.resumedAt != nil }.count,
            averageTaskResumeLatency: averageTaskResumeLatency,
            appDurations: appDurations,
            taskDurations: taskDurations
        )
    }
}
