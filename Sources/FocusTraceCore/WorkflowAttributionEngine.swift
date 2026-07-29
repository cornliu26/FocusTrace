import Foundation

public struct WorkflowAttributionSummary: Codable, Equatable, Sendable {
    public let recordedMinutes: Double
    public let directMinutes: Double
    public let intervalRecoveredMinutes: Double
    public let focusSessionRecoveredMinutes: Double
    public let unresolvedMinutes: Double

    public init(
        recordedMinutes: Double,
        directMinutes: Double,
        intervalRecoveredMinutes: Double,
        focusSessionRecoveredMinutes: Double,
        unresolvedMinutes: Double
    ) {
        self.recordedMinutes = max(0, recordedMinutes)
        self.directMinutes = max(0, directMinutes)
        self.intervalRecoveredMinutes = max(0, intervalRecoveredMinutes)
        self.focusSessionRecoveredMinutes = max(0, focusSessionRecoveredMinutes)
        self.unresolvedMinutes = max(0, unresolvedMinutes)
    }

    public var attributedMinutes: Double {
        directMinutes + intervalRecoveredMinutes + focusSessionRecoveredMinutes
    }

    public var attributedRatio: Double {
        recordedMinutes > 0 ? min(1, attributedMinutes / recordedMinutes) : 0
    }

    public var recoveredMinutes: Double {
        intervalRecoveredMinutes + focusSessionRecoveredMinutes
    }
}

/// Reconciles missing activity workflow IDs from explicit local traces only.
///
/// Direct activity attribution always wins. A missing ID may be recovered from
/// one unambiguous workflow interval or from the activity's own focus-session
/// ID. The engine never carries a nearby workflow across an unbound gap and
/// never guesses from application names, workflow titles, or semantic
/// similarity.
public enum WorkflowAttributionEngine {
    public static func summarize(
        activities: [ActivityRecord],
        taskIntervals: [TaskIntervalRecord],
        focusSessions: [FocusSessionRecord],
        now: Date = Date()
    ) -> WorkflowAttributionSummary {
        let visible = activities
            .filter {
                ![.systemInactive, .trackerControl].contains($0.classification)
                    && ($0.endedAt ?? now) > $0.startedAt
            }
            .sorted { $0.startedAt < $1.startedAt }
        let intervals = taskIntervals
            .compactMap { interval -> ClosedWorkflowInterval? in
                let end = interval.endedAt ?? now
                guard end > interval.startedAt else { return nil }
                return ClosedWorkflowInterval(
                    taskID: interval.taskID,
                    start: interval.startedAt,
                    end: end
                )
            }
            .sorted { $0.start < $1.start }
        let sessionsByID: [UUID: ClosedWorkflowInterval] = Dictionary(
            uniqueKeysWithValues: focusSessions.compactMap {
                session -> (UUID, ClosedWorkflowInterval)? in
                guard let end = session.endedAt, end > session.startedAt else {
                    return nil
                }
                return (
                    session.id,
                    ClosedWorkflowInterval(
                        taskID: session.taskID,
                        start: session.startedAt,
                        end: end
                    )
                )
            }
        )

        var directSeconds: TimeInterval = 0
        var intervalSeconds: TimeInterval = 0
        var focusSeconds: TimeInterval = 0
        var unresolvedSeconds: TimeInterval = 0
        var firstCandidateIndex = 0

        for activity in visible {
            let end = activity.endedAt ?? now
            let duration = max(0, end.timeIntervalSince(activity.startedAt))
            guard duration > 0 else { continue }
            if activity.taskID != nil {
                directSeconds += duration
                continue
            }

            while firstCandidateIndex < intervals.count,
                  intervals[firstCandidateIndex].end <= activity.startedAt {
                firstCandidateIndex += 1
            }
            var overlappingIntervals: [ClosedWorkflowInterval] = []
            var candidateIndex = firstCandidateIndex
            while candidateIndex < intervals.count,
                  intervals[candidateIndex].start < end {
                let candidate = intervals[candidateIndex]
                if candidate.end > activity.startedAt {
                    overlappingIntervals.append(candidate)
                }
                candidateIndex += 1
            }
            let focusInterval = activity.focusSessionID.flatMap {
                sessionsByID[$0]
            }
            let allocation = allocate(
                activityStart: activity.startedAt,
                activityEnd: end,
                intervals: overlappingIntervals,
                focusInterval: focusInterval
            )
            intervalSeconds += allocation.interval
            focusSeconds += allocation.focus
            unresolvedSeconds += allocation.unresolved
        }

        let recordedSeconds = directSeconds
            + intervalSeconds
            + focusSeconds
            + unresolvedSeconds
        return WorkflowAttributionSummary(
            recordedMinutes: recordedSeconds / 60,
            directMinutes: directSeconds / 60,
            intervalRecoveredMinutes: intervalSeconds / 60,
            focusSessionRecoveredMinutes: focusSeconds / 60,
            unresolvedMinutes: unresolvedSeconds / 60
        )
    }

    private struct ClosedWorkflowInterval {
        let taskID: UUID
        let start: Date
        let end: Date

        func contains(_ date: Date) -> Bool {
            start <= date && date < end
        }
    }

    private struct Allocation {
        var interval: TimeInterval = 0
        var focus: TimeInterval = 0
        var unresolved: TimeInterval = 0
    }

    private static func allocate(
        activityStart: Date,
        activityEnd: Date,
        intervals: [ClosedWorkflowInterval],
        focusInterval: ClosedWorkflowInterval?
    ) -> Allocation {
        var boundaries = [activityStart, activityEnd]
        for interval in intervals {
            boundaries.append(max(activityStart, interval.start))
            boundaries.append(min(activityEnd, interval.end))
        }
        if let focusInterval,
           focusInterval.end > activityStart,
           focusInterval.start < activityEnd {
            boundaries.append(max(activityStart, focusInterval.start))
            boundaries.append(min(activityEnd, focusInterval.end))
        }
        boundaries = Array(Set(boundaries)).sorted()

        var result = Allocation()
        for index in 0..<(max(0, boundaries.count - 1)) {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            let seconds = end.timeIntervalSince(start)
            guard seconds > 0 else { continue }
            let midpoint = start.addingTimeInterval(seconds / 2)
            let intervalTaskIDs = Set(
                intervals.filter { $0.contains(midpoint) }.map(\.taskID)
            )
            let focusTaskID = focusInterval.flatMap {
                $0.contains(midpoint) ? $0.taskID : nil
            }
            var allTaskIDs = intervalTaskIDs
            if let focusTaskID {
                allTaskIDs.insert(focusTaskID)
            }

            guard allTaskIDs.count == 1 else {
                result.unresolved += seconds
                continue
            }
            if focusTaskID != nil {
                result.focus += seconds
            } else {
                result.interval += seconds
            }
        }
        return result
    }
}
