import Foundation

public struct DailySummary: Equatable, Sendable {
    public let appSwitchCount: Int
    public let taskSwitchCount: Int
    public let suspectedDistractionCount: Int
    public let confirmedDistractionCount: Int
    public let averageReturnLatency: TimeInterval?
    public let medianFocusStreak: TimeInterval?
    public let appDurations: [String: TimeInterval]
    public let taskDurations: [UUID: TimeInterval]

    public init(
        appSwitchCount: Int,
        taskSwitchCount: Int,
        suspectedDistractionCount: Int,
        confirmedDistractionCount: Int,
        averageReturnLatency: TimeInterval?,
        medianFocusStreak: TimeInterval?,
        appDurations: [String: TimeInterval],
        taskDurations: [UUID: TimeInterval]
    ) {
        self.appSwitchCount = appSwitchCount
        self.taskSwitchCount = taskSwitchCount
        self.suspectedDistractionCount = suspectedDistractionCount
        self.confirmedDistractionCount = confirmedDistractionCount
        self.averageReturnLatency = averageReturnLatency
        self.medianFocusStreak = medianFocusStreak
        self.appDurations = appDurations
        self.taskDurations = taskDurations
    }
}

public enum MetricsEngine {
    public static func dailySummary(
        activities: [ActivityRecord],
        taskIntervals: [TaskIntervalRecord],
        interruptions: [InterruptionRecord],
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

        return DailySummary(
            appSwitchCount: switches,
            taskSwitchCount: max(0, taskIntervals.count - 1),
            suspectedDistractionCount: suspected,
            confirmedDistractionCount: confirmed,
            averageReturnLatency: averageLatency,
            medianFocusStreak: median,
            appDurations: appDurations,
            taskDurations: taskDurations
        )
    }
}
