import Foundation

public enum FragmentationLevel: String, Codable, CaseIterable, Sendable {
    case quiet
    case steady
    case fragmented
    case intense

    public static func classify(switchCount: Int, bucketMinutes: Int = 5) -> FragmentationLevel {
        let normalized = Double(max(0, switchCount)) * 5 / Double(max(1, bucketMinutes))
        switch normalized {
        case ..<3: return .quiet
        case ..<6: return .steady
        case ..<11: return .fragmented
        default: return .intense
        }
    }
}

public struct TimelineBucket: Identifiable, Equatable, Sendable {
    public var id: Date { start }
    public let start: Date
    public let end: Date
    public let dominantApp: AppIdentity?
    public let activeSeconds: TimeInterval
    public let switchCount: Int
    public let spaceSwitchCount: Int
    public let uniqueAppCount: Int
    public let fragmentationLevel: FragmentationLevel

    public init(
        start: Date,
        end: Date,
        dominantApp: AppIdentity?,
        activeSeconds: TimeInterval,
        switchCount: Int,
        spaceSwitchCount: Int,
        uniqueAppCount: Int,
        fragmentationLevel: FragmentationLevel
    ) {
        self.start = start
        self.end = end
        self.dominantApp = dominantApp
        self.activeSeconds = activeSeconds
        self.switchCount = switchCount
        self.spaceSwitchCount = spaceSwitchCount
        self.uniqueAppCount = uniqueAppCount
        self.fragmentationLevel = fragmentationLevel
    }
}

public enum TimelineAggregationEngine {
    private struct MutableBucket {
        var durations: [AppIdentity: TimeInterval] = [:]
        var switchCount = 0
        var spaceSwitchCount = 0
        var apps = Set<AppIdentity>()
    }

    public static func buckets(
        activities: [ActivityRecord],
        markers: [TimelineMarkerRecord],
        range: DateInterval,
        bucketMinutes: Int = 5,
        now: Date = Date()
    ) -> [TimelineBucket] {
        let bucketSeconds = TimeInterval(max(1, bucketMinutes) * 60)
        let count = max(1, Int(ceil(range.duration / bucketSeconds)))
        var mutable = Array(repeating: MutableBucket(), count: count)
        let visibleActivities = activities
            .filter { ![.systemInactive, .trackerControl].contains($0.classification) }
            .sorted {
                if $0.startedAt == $1.startedAt { return $0.id.uuidString < $1.id.uuidString }
                return $0.startedAt < $1.startedAt
            }

        for activity in visibleActivities {
            let activityEnd = min(activity.endedAt ?? now, range.end)
            let activityStart = max(activity.startedAt, range.start)
            guard activityEnd > activityStart else { continue }

            let firstIndex = bucketIndex(for: activityStart, range: range, bucketSeconds: bucketSeconds, count: count)
            let lastMoment = activityEnd.addingTimeInterval(-0.000_001)
            let lastIndex = bucketIndex(for: lastMoment, range: range, bucketSeconds: bucketSeconds, count: count)
            for index in firstIndex...lastIndex {
                let bucketStart = range.start.addingTimeInterval(Double(index) * bucketSeconds)
                let bucketEnd = min(range.end, bucketStart.addingTimeInterval(bucketSeconds))
                let overlap = min(activityEnd, bucketEnd).timeIntervalSince(max(activityStart, bucketStart))
                guard overlap > 0 else { continue }
                mutable[index].durations[activity.app, default: 0] += overlap
                mutable[index].apps.insert(activity.app)
            }
        }

        var previousBundleID: String?
        for activity in visibleActivities {
            let activityEnd = min(activity.endedAt ?? now, range.end)
            guard activity.startedAt < range.end, activityEnd > range.start else { continue }
            if let previousBundleID, previousBundleID != activity.app.bundleID {
                let switchDate = max(activity.startedAt, range.start)
                let index = bucketIndex(for: switchDate, range: range, bucketSeconds: bucketSeconds, count: count)
                mutable[index].switchCount += 1
            }
            previousBundleID = activity.app.bundleID
        }

        for marker in markers where marker.kind == .activeSpaceChanged && range.contains(marker.date) {
            let index = bucketIndex(for: marker.date, range: range, bucketSeconds: bucketSeconds, count: count)
            mutable[index].spaceSwitchCount += 1
        }

        return mutable.enumerated().map { index, item in
            let start = range.start.addingTimeInterval(Double(index) * bucketSeconds)
            let end = min(range.end, start.addingTimeInterval(bucketSeconds))
            let dominant = item.durations.max { left, right in
                if left.value == right.value { return left.key.bundleID > right.key.bundleID }
                return left.value < right.value
            }?.key
            return TimelineBucket(
                start: start,
                end: end,
                dominantApp: dominant,
                activeSeconds: item.durations.values.reduce(0, +),
                switchCount: item.switchCount,
                spaceSwitchCount: item.spaceSwitchCount,
                uniqueAppCount: item.apps.count,
                fragmentationLevel: FragmentationLevel.classify(
                    switchCount: item.switchCount,
                    bucketMinutes: bucketMinutes
                )
            )
        }
    }

    private static func bucketIndex(
        for date: Date,
        range: DateInterval,
        bucketSeconds: TimeInterval,
        count: Int
    ) -> Int {
        let offset = max(0, date.timeIntervalSince(range.start))
        return min(count - 1, max(0, Int(offset / bucketSeconds)))
    }
}

public struct TimelineEventBucket: Identifiable, Equatable, Sendable {
    public var id: Date { start }
    public let start: Date
    public let end: Date
    public let kinds: [TimelineMarkerKind]

    public init(start: Date, end: Date, kinds: [TimelineMarkerKind]) {
        self.start = start
        self.end = end
        self.kinds = kinds
    }

    public var eventCount: Int { kinds.count }

    public var countsByKind: [TimelineMarkerKind: Int] {
        kinds.reduce(into: [:]) { result, kind in
            result[kind, default: 0] += 1
        }
    }
}

public enum TimelineEventAggregationEngine {
    public static func buckets(
        markers: [TimelineMarkerRecord],
        range: DateInterval,
        bucketMinutes: Int = 15
    ) -> [TimelineEventBucket] {
        let bucketSeconds = TimeInterval(max(1, bucketMinutes) * 60)
        let count = max(1, Int(ceil(range.duration / bucketSeconds)))
        var grouped = Array(repeating: [TimelineMarkerKind](), count: count)

        for marker in markers
            .filter({ $0.kind != .activeSpaceChanged && range.contains($0.date) })
            .sorted(by: { $0.date < $1.date }) {
            let offset = max(0, marker.date.timeIntervalSince(range.start))
            let index = min(count - 1, max(0, Int(offset / bucketSeconds)))
            grouped[index].append(marker.kind)
        }

        return grouped.enumerated().compactMap { index, kinds in
            guard !kinds.isEmpty else { return nil }
            let start = range.start.addingTimeInterval(Double(index) * bucketSeconds)
            return TimelineEventBucket(
                start: start,
                end: min(range.end, start.addingTimeInterval(bucketSeconds)),
                kinds: kinds
            )
        }
    }
}
