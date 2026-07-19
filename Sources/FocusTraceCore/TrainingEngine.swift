import Foundation

public enum TrainingAdjustment: Equatable, Sendable {
    case increase(toMinutes: Int)
    case decrease(toMinutes: Int)
    case maintain(minutes: Int)
}

public enum TrainingEngine {
    public static func initialFocusMinutes(
        baselineStreaks: [TimeInterval],
        minimumSamples: Int = 10
    ) -> Int {
        guard baselineStreaks.count >= minimumSamples else { return 15 }
        let sorted = baselineStreaks.sorted()
        let middle = sorted.count / 2
        let medianSeconds: Double
        if sorted.count.isMultiple(of: 2) {
            medianSeconds = (sorted[middle - 1] + sorted[middle]) / 2
        } else {
            medianSeconds = sorted[middle]
        }
        let minutes = medianSeconds / 60
        let rounded = Int((minutes / 5).rounded()) * 5
        return min(25, max(10, rounded))
    }

    public static func progression(
        currentMinutes: Int,
        lastFive: [FocusSessionRecord]
    ) -> TrainingAdjustment? {
        guard lastFive.count == 5 else { return nil }
        let successCount = lastFive.filter(\.isSuccessful).count
        if successCount >= 4 {
            return .increase(toMinutes: min(50, currentMinutes + 5))
        }
        if successCount <= 2 {
            return .decrease(toMinutes: max(10, currentMinutes - 5))
        }
        return .maintain(minutes: currentMinutes)
    }

    public static func baselineStreaks(from activities: [ActivityRecord]) -> [TimeInterval] {
        let sorted = activities.sorted { $0.startedAt < $1.startedAt }
        var result: [TimeInterval] = []
        var currentStart: Date?
        var currentEnd: Date?
        var currentTaskID: UUID?

        func isOnTask(_ record: ActivityRecord) -> Bool {
            switch record.classification {
            case .allowed, .necessary, .trackerControl:
                return true
            case .suspectedDistraction, .confirmedDistraction, .taskSwitch, .systemInactive:
                return false
            }
        }

        func appendCurrent() {
            if let start = currentStart, let end = currentEnd, end > start {
                result.append(end.timeIntervalSince(start))
            }
        }

        for record in sorted {
            guard let end = record.endedAt, isOnTask(record), record.taskID != nil else {
                appendCurrent()
                currentStart = nil
                currentEnd = nil
                currentTaskID = nil
                continue
            }

            let isContiguous = currentEnd.map { abs(record.startedAt.timeIntervalSince($0)) <= 1 } ?? false
            if currentTaskID == record.taskID, isContiguous {
                currentEnd = end
            } else {
                appendCurrent()
                currentStart = record.startedAt
                currentEnd = end
                currentTaskID = record.taskID
            }
        }
        appendCurrent()
        return result
    }
}
