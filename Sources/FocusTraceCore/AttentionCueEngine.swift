import Foundation

public enum AttentionCueLevel: Int, Equatable, Sendable {
    case none = 0
    case gentle = 1
    case strong = 2
}

public struct AttentionCueDecision: Equatable, Sendable {
    public let level: AttentionCueLevel
    public let switchCount: Int
    public let gentleThreshold: Int
    public let strongThreshold: Int

    public init(
        level: AttentionCueLevel,
        switchCount: Int,
        gentleThreshold: Int,
        strongThreshold: Int
    ) {
        self.level = level
        self.switchCount = switchCount
        self.gentleThreshold = gentleThreshold
        self.strongThreshold = strongThreshold
    }
}

/// Pure policy for the screen-edge attention cue. It deliberately operates on
/// task intervals instead of raw Space notifications so display refresh noise
/// can never become a behavioral warning.
public enum AttentionCueEngine {
    public static let windowSeconds: TimeInterval = 10 * 60
    public static let minimumStableTaskSeconds: TimeInterval = 30
    public static let gentleSwitchThreshold = 3
    public static let strongSwitchThreshold = 5

    private struct StableSpan {
        let taskID: UUID
        let startedAt: Date
        var endedAt: Date
    }

    public static func stableTaskSwitchCount(
        intervals: [TaskIntervalRecord],
        parkings: [TaskParkingRecord],
        at now: Date,
        window: TimeInterval = windowSeconds,
        minimumStableDuration: TimeInterval = minimumStableTaskSeconds
    ) -> Int {
        let windowStart = now.addingTimeInterval(-max(1, window))
        let stable = intervals
            .filter { interval in
                let end = min(interval.endedAt ?? now, now)
                return end >= windowStart
                    && interval.startedAt <= now
                    && end.timeIntervalSince(interval.startedAt) >= minimumStableDuration
            }
            .sorted { $0.startedAt < $1.startedAt }
            .reduce(into: [StableSpan]()) { spans, interval in
                let end = min(interval.endedAt ?? now, now)
                if let lastIndex = spans.indices.last,
                   spans[lastIndex].taskID == interval.taskID,
                   interval.startedAt.timeIntervalSince(spans[lastIndex].endedAt) <= 5 {
                    spans[lastIndex].endedAt = max(spans[lastIndex].endedAt, end)
                } else {
                    spans.append(StableSpan(
                        taskID: interval.taskID,
                        startedAt: interval.startedAt,
                        endedAt: end
                    ))
                }
            }

        guard stable.count >= 2 else { return 0 }
        var count = 0
        for index in 1..<stable.count {
            let previous = stable[index - 1]
            let current = stable[index]
            guard previous.taskID != current.taskID,
                  current.startedAt >= windowStart,
                  current.startedAt.timeIntervalSince(previous.endedAt) <= 60,
                  !isPlannedTransition(
                    from: previous.taskID,
                    to: current.taskID,
                    at: current.startedAt,
                    parkings: parkings
                  ) else { continue }
            count += 1
        }
        return count
    }

    public static func switchDecision(
        intervals: [TaskIntervalRecord],
        parkings: [TaskParkingRecord],
        at now: Date,
        gentleThreshold: Int = gentleSwitchThreshold,
        strongThreshold: Int = strongSwitchThreshold
    ) -> AttentionCueDecision {
        let gentle = max(2, gentleThreshold)
        let strong = max(gentle + 1, strongThreshold)
        let count = stableTaskSwitchCount(
            intervals: intervals,
            parkings: parkings,
            at: now
        )
        let level: AttentionCueLevel
        if count >= strong {
            level = .strong
        } else if count >= gentle {
            level = .gentle
        } else {
            level = .none
        }
        return AttentionCueDecision(
            level: level,
            switchCount: count,
            gentleThreshold: gentle,
            strongThreshold: strong
        )
    }

    /// A five-minute milestone is frequent enough to feel immediate while
    /// remaining much less disruptive than per-minute badges or animations.
    public static func continuityMilestoneMinutes(
        elapsedSeconds: TimeInterval
    ) -> Int {
        guard elapsedSeconds >= 5 * 60 else { return 0 }
        return Int(elapsedSeconds / (5 * 60)) * 5
    }

    public static func continuousTaskSeconds(
        intervals: [TaskIntervalRecord],
        taskID: UUID,
        at now: Date,
        maximumSameTaskGap: TimeInterval = 5
    ) -> TimeInterval {
        let ordered = intervals
            .filter { $0.taskID == taskID && $0.startedAt <= now }
            .sorted { $0.startedAt < $1.startedAt }
        guard let latest = ordered.last,
              (latest.endedAt ?? now).timeIntervalSince(now) >= -maximumSameTaskGap else {
            return 0
        }

        var earliest = latest.startedAt
        var nextStart = latest.startedAt
        for interval in ordered.dropLast().reversed() {
            let end = min(interval.endedAt ?? now, now)
            guard nextStart.timeIntervalSince(end) <= maximumSameTaskGap else { break }
            earliest = interval.startedAt
            nextStart = interval.startedAt
        }
        return max(0, now.timeIntervalSince(earliest))
    }

    private static func isPlannedTransition(
        from previousTaskID: UUID,
        to currentTaskID: UUID,
        at transitionDate: Date,
        parkings: [TaskParkingRecord]
    ) -> Bool {
        let tolerance: TimeInterval = 45
        return parkings.contains { parking in
            let parkedSwitch = parking.taskID == previousTaskID
                && parking.switchedToTaskID == currentTaskID
                && abs(parking.parkedAt.timeIntervalSince(transitionDate)) <= tolerance
            let plannedReturn = parking.taskID == currentTaskID
                && parking.resumedAt.map {
                    abs($0.timeIntervalSince(transitionDate)) <= tolerance
                } == true
            return parkedSwitch || plannedReturn
        }
    }
}
