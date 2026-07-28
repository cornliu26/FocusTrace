import Foundation

public enum AutomationWorkflowSwitchReason: String, Codable, CaseIterable, Sendable {
    case checkpoint
    case waitingForResult
    case forcedInterruption
    case unstructured
}

public struct AutomationWorkflowContextArtifact: Codable, Equatable, Sendable {
    public let workflowTitle: String
    public let activeMinutes: Double
    public let openRequirementTitles: [String]

    public init(
        workflowTitle: String,
        activeMinutes: Double,
        openRequirementTitles: [String]
    ) {
        self.workflowTitle = workflowTitle
        self.activeMinutes = activeMinutes
        self.openRequirementTitles = openRequirementTitles
    }
}

public struct AutomationWorkflowTransitionRouteArtifact: Codable, Equatable, Sendable {
    public let fromWorkflow: String
    public let toWorkflow: String
    public let count: Int
    public let reasonCounts: [String: Int]
    public let medianDestinationMinutes: Double?
    public let returnedWithin30Minutes: Int
    public let timeBucketCounts: [String: Int]
    public let outcomeCounts: [String: Int]?

    public init(
        fromWorkflow: String,
        toWorkflow: String,
        count: Int,
        reasonCounts: [String: Int],
        medianDestinationMinutes: Double?,
        returnedWithin30Minutes: Int,
        timeBucketCounts: [String: Int],
        outcomeCounts: [String: Int]? = nil
    ) {
        self.fromWorkflow = fromWorkflow
        self.toWorkflow = toWorkflow
        self.count = count
        self.reasonCounts = reasonCounts
        self.medianDestinationMinutes = medianDestinationMinutes
        self.returnedWithin30Minutes = returnedWithin30Minutes
        self.timeBucketCounts = timeBucketCounts
        self.outcomeCounts = outcomeCounts
    }
}

public struct AutomationWorkflowTransitionAuditArtifact: Codable, Equatable, Sendable {
    public let protocolVersion: Int?
    public let dataSource: String?
    public let finalSwitches: Int?
    public let explicitReasonSwitches: Int?
    public let timedOutSwitches: Int?
    public let automaticSwitches: Int?
    public let unresolvedNavigations: Int?
    public let explicitReasonCoverage: Double?
    public let interventionPolicy: String?
    public let frequentSwitchEpisodes: Int?
    public let interventionPrompts: Int?
    public let assessedInterventionPrompts: Int?
    public let postPromptQuietRate: Double?
    public let reasonedSwitches: Int
    public let unreasonedSwitches: Int
    public let cancelledNavigations: Int
    public let reasonCounts: [String: Int]
    public let routes: [AutomationWorkflowTransitionRouteArtifact]

    public init(
        protocolVersion: Int? = nil,
        dataSource: String? = nil,
        finalSwitches: Int? = nil,
        explicitReasonSwitches: Int? = nil,
        timedOutSwitches: Int? = nil,
        automaticSwitches: Int? = nil,
        unresolvedNavigations: Int? = nil,
        explicitReasonCoverage: Double? = nil,
        interventionPolicy: String? = nil,
        frequentSwitchEpisodes: Int? = nil,
        interventionPrompts: Int? = nil,
        assessedInterventionPrompts: Int? = nil,
        postPromptQuietRate: Double? = nil,
        reasonedSwitches: Int,
        unreasonedSwitches: Int,
        cancelledNavigations: Int,
        reasonCounts: [String: Int],
        routes: [AutomationWorkflowTransitionRouteArtifact]
    ) {
        self.protocolVersion = protocolVersion
        self.dataSource = dataSource
        self.finalSwitches = finalSwitches
        self.explicitReasonSwitches = explicitReasonSwitches
        self.timedOutSwitches = timedOutSwitches
        self.automaticSwitches = automaticSwitches
        self.unresolvedNavigations = unresolvedNavigations
        self.explicitReasonCoverage = explicitReasonCoverage
        self.interventionPolicy = interventionPolicy
        self.frequentSwitchEpisodes = frequentSwitchEpisodes
        self.interventionPrompts = interventionPrompts
        self.assessedInterventionPrompts = assessedInterventionPrompts
        self.postPromptQuietRate = postPromptQuietRate
        self.reasonedSwitches = reasonedSwitches
        self.unreasonedSwitches = unreasonedSwitches
        self.cancelledNavigations = cancelledNavigations
        self.reasonCounts = reasonCounts
        self.routes = routes
    }
}

public enum WorkflowTransitionAuditEngine {
    public static let maximumWorkflowContexts = 8
    public static let maximumRoutes = 8
    public static let maximumRequirementsPerWorkflow = 3
    public static let maximumTitleLength = 80

    public static func makeAudit(
        tasks: [TaskRecord],
        requirements: [RequirementRecord],
        taskIntervals: [TaskIntervalRecord],
        activities: [ActivityRecord] = [],
        markers: [TimelineMarkerRecord],
        workflowTransitions: [WorkflowTransitionRecord] = [],
        range: Range<Date>,
        now: Date,
        calendar: Calendar = .current
    ) -> (
        contexts: [AutomationWorkflowContextArtifact],
        audit: AutomationWorkflowTransitionAuditArtifact
    ) {
        let effectiveNow = min(now, range.upperBound)
        let intervals = taskIntervals.compactMap {
            clipped($0, to: range, now: effectiveNow)
        }.sorted { left, right in
            if left.startedAt != right.startedAt {
                return left.startedAt < right.startedAt
            }
            return left.id.uuidString < right.id.uuidString
        }
        let attributedSeconds = attributedSecondsByWorkflow(
            activities: activities,
            range: range,
            now: effectiveNow
        )
        let taskTitles = Dictionary(
            uniqueKeysWithValues: tasks.map {
                ($0.id, boundedTitle($0.title, fallback: "未命名工作流"))
            }
        )
        let openRequirements = requirements.filter {
            $0.status != .completed && $0.status != .archived
        }
        let requirementTitlesByWorkflow = Dictionary(
            grouping: RequirementEngine.ordered(
                openRequirements,
                at: range.lowerBound,
                calendar: calendar
            ).compactMap { requirement -> (UUID, String)? in
                guard let workflowID = requirement.workflowID else { return nil }
                return (
                    workflowID,
                    boundedTitle(requirement.title, fallback: "未命名需求")
                )
            },
            by: \.0
        ).mapValues {
            Array($0.map(\.1).uniqued().prefix(maximumRequirementsPerWorkflow))
        }

        let semanticTransitions = workflowTransitions.filter {
            range.contains($0.resolvedAt) && $0.source == .space
        }.sorted { $0.resolvedAt < $1.resolvedAt }
        let semanticDates = semanticTransitions.map(\.resolvedAt)
        let transitionMarkers = markers.filter {
            range.contains($0.date)
                && reason(for: $0.kind) != nil
                && !isNearSemanticTransition($0.date, dates: semanticDates)
        }.sorted { $0.date < $1.date }
        let spaceIntervals = intervals.filter {
            $0.effectiveWorkflowSource == .space
        }
        let startsByWorkflow = Dictionary(
            grouping: intervals,
            by: \.taskID
        ).mapValues { $0.map(\.startedAt) }
        let legacyCancelledCount = markers.filter {
            range.contains($0.date)
                && $0.kind == .spaceSwitchCancelled
                && !isNearSemanticTransition($0.date, dates: semanticDates)
        }.count

        var groupedRoutes: [RouteKey: [TransitionSample]] = [:]
        var reasonCounts: [String: Int] = [:]
        var matchedDestinationIntervalIDs = Set<UUID>()
        var semanticFinalSwitches = 0
        var explicitReasonSwitches = 0
        var timedOutSwitches = 0
        var automaticSwitches = 0
        var unresolvedNavigations = 0
        var semanticCancelledCount = 0
        var semanticReasonedSwitches = 0
        var semanticUnreasonedSwitches = 0

        for transition in semanticTransitions {
            switch transition.outcome {
            case .cancelled:
                semanticCancelledCount += 1
                continue
            case .unresolved:
                unresolvedNavigations += 1
                continue
            case .confirmed, .timedOut, .automatic:
                break
            }
            guard transition.origin != transition.destination else { continue }
            switch transition.outcome {
            case .confirmed:
                explicitReasonSwitches += 1
            case .timedOut:
                timedOutSwitches += 1
            case .automatic:
                automaticSwitches += 1
            case .cancelled, .unresolved:
                break
            }
            semanticFinalSwitches += 1
            let mappedReason = transition.reason.map(automationReason)
            if let mappedReason {
                semanticReasonedSwitches += 1
                reasonCounts[mappedReason.rawValue, default: 0] += 1
            } else {
                semanticUnreasonedSwitches += 1
            }

            let destination = destinationInterval(
                at: transition.resolvedAt,
                in: spaceIntervals
            )
            if let destination {
                matchedDestinationIntervalIDs.insert(destination.id)
            }
            let destinationMinutes = destination.map {
                max(
                    0,
                    ($0.endedAt ?? effectiveNow)
                        .timeIntervalSince($0.startedAt) / 60
                )
            }
            let originID = transition.origin.workflowID
            let returned = originID.map {
                containsDate(
                    startsByWorkflow[$0] ?? [],
                    after: transition.resolvedAt,
                    through: transition.resolvedAt.addingTimeInterval(30 * 60)
                )
            } ?? false
            let sample = TransitionSample(
                reason: mappedReason,
                outcome: transition.outcome.rawValue,
                destinationMinutes: destinationMinutes,
                returnedWithin30Minutes: returned,
                timeBucket: timeBucket(
                    for: transition.resolvedAt,
                    calendar: calendar
                )
            )
            groupedRoutes[
                RouteKey(
                    fromWorkflow: title(
                        for: transition.origin,
                        taskTitles: taskTitles
                    ),
                    toWorkflow: title(
                        for: transition.destination,
                        taskTitles: taskTitles
                    )
                ),
                default: []
            ].append(sample)
        }

        for marker in transitionMarkers {
            guard let reason = reason(for: marker.kind) else { continue }
            reasonCounts[reason.rawValue, default: 0] += 1

            let destination = destinationInterval(
                for: marker,
                in: spaceIntervals
            )
            if let destination {
                matchedDestinationIntervalIDs.insert(destination.id)
            }
            let fromTitle = marker.taskID.flatMap { taskTitles[$0] }
                ?? "未绑定桌面"
            let toTitle = destination.flatMap { taskTitles[$0.taskID] }
                ?? "未绑定桌面"
            guard marker.taskID != destination?.taskID else { continue }

            let destinationMinutes = destination.map {
                max(0, ($0.endedAt ?? effectiveNow).timeIntervalSince($0.startedAt) / 60)
            }
            let returned = marker.taskID.map { originID in
                containsDate(
                    startsByWorkflow[originID] ?? [],
                    after: marker.date,
                    through: marker.date.addingTimeInterval(30 * 60)
                )
            } ?? false
            let sample = TransitionSample(
                reason: reason,
                outcome: "legacyInferred",
                destinationMinutes: destinationMinutes,
                returnedWithin30Minutes: returned,
                timeBucket: timeBucket(for: marker.date, calendar: calendar)
            )
            groupedRoutes[
                RouteKey(fromWorkflow: fromTitle, toWorkflow: toTitle),
                default: []
            ].append(sample)
        }

        let routes = groupedRoutes.map { key, samples in
            let durations = samples.compactMap(\.destinationMinutes).sorted()
            return AutomationWorkflowTransitionRouteArtifact(
                fromWorkflow: key.fromWorkflow,
                toWorkflow: key.toWorkflow,
                count: samples.count,
                reasonCounts: Dictionary(
                    grouping: samples.compactMap(\.reason),
                    by: \.rawValue
                ).mapValues(\.count),
                medianDestinationMinutes: median(durations),
                returnedWithin30Minutes: samples.filter(\.returnedWithin30Minutes).count,
                timeBucketCounts: Dictionary(
                    grouping: samples,
                    by: \.timeBucket
                ).mapValues(\.count),
                outcomeCounts: Dictionary(
                    grouping: samples,
                    by: \.outcome
                ).mapValues(\.count)
            )
        }.sorted { left, right in
            if left.count != right.count { return left.count > right.count }
            if left.fromWorkflow != right.fromWorkflow {
                return left.fromWorkflow.localizedStandardCompare(right.fromWorkflow)
                    == .orderedAscending
            }
            return left.toWorkflow.localizedStandardCompare(right.toWorkflow)
                == .orderedAscending
        }

        let unmatchedSpaceIntervals = spaceIntervals.filter {
            $0.startedAt > range.lowerBound
                && !matchedDestinationIntervalIDs.contains($0.id)
                && !isNearSemanticTransition(
                    $0.startedAt,
                    dates: semanticDates
                )
        }.count
        let reasonedSwitches = semanticReasonedSwitches
            + transitionMarkers.count
        let legacyExplicitReasonSwitches = transitionMarkers.filter {
            reason(for: $0.kind) != .unstructured
        }.count
        let legacyTimedOutSwitches = transitionMarkers.filter {
            reason(for: $0.kind) == .unstructured
        }.count
        let unreasonedSwitches = semanticUnreasonedSwitches
            + unmatchedSpaceIntervals
        let finalSwitches = semanticFinalSwitches
            + transitionMarkers.count
            + unmatchedSpaceIntervals
        let dataSource: String
        switch (semanticTransitions.isEmpty, transitionMarkers.isEmpty
            && unmatchedSpaceIntervals == 0 && legacyCancelledCount == 0) {
        case (false, false):
            dataSource = "mixed"
        case (false, true):
            dataSource = "semanticEvents"
        case (true, false):
            dataSource = "legacyInferred"
        case (true, true):
            dataSource = "none"
        }
        let contexts = workflowContexts(
            intervals: intervals,
            taskTitles: taskTitles,
            requirementTitlesByWorkflow: requirementTitlesByWorkflow,
            attributedSeconds: attributedSeconds
        )
        let intervention = WorkflowSwitchInterventionEngine.audit(
            transitions: workflowTransitions,
            range: range,
            now: effectiveNow
        )
        return (
            contexts,
            AutomationWorkflowTransitionAuditArtifact(
                protocolVersion: 2,
                dataSource: dataSource,
                finalSwitches: finalSwitches,
                explicitReasonSwitches: explicitReasonSwitches
                    + legacyExplicitReasonSwitches,
                timedOutSwitches: timedOutSwitches
                    + legacyTimedOutSwitches,
                automaticSwitches: automaticSwitches,
                unresolvedNavigations: unresolvedNavigations,
                explicitReasonCoverage: finalSwitches > 0
                    ? Double(
                        explicitReasonSwitches
                            + legacyExplicitReasonSwitches
                    ) / Double(finalSwitches)
                    : nil,
                interventionPolicy: "thirdFinalWorkflowSwitchWithin10Minutes",
                frequentSwitchEpisodes: intervention.frequentSwitchEpisodes,
                interventionPrompts: intervention.promptsShown,
                assessedInterventionPrompts: intervention.assessedPrompts,
                postPromptQuietRate: intervention.quietAfterPromptRate,
                reasonedSwitches: reasonedSwitches,
                unreasonedSwitches: unreasonedSwitches,
                cancelledNavigations: semanticCancelledCount
                    + legacyCancelledCount,
                reasonCounts: reasonCounts,
                routes: Array(routes.prefix(maximumRoutes))
            )
        )
    }

    private static func workflowContexts(
        intervals: [TaskIntervalRecord],
        taskTitles: [UUID: String],
        requirementTitlesByWorkflow: [UUID: [String]],
        attributedSeconds: [UUID: TimeInterval]
    ) -> [AutomationWorkflowContextArtifact] {
        let workflowIDs = Set(intervals.map(\.taskID))
            .union(attributedSeconds.keys)
        return workflowIDs.map { workflowID in
            AutomationWorkflowContextArtifact(
                workflowTitle: taskTitles[workflowID] ?? "未命名工作流",
                activeMinutes: (attributedSeconds[workflowID] ?? 0) / 60,
                openRequirementTitles: requirementTitlesByWorkflow[workflowID] ?? []
            )
        }.sorted { left, right in
            if left.activeMinutes != right.activeMinutes {
                return left.activeMinutes > right.activeMinutes
            }
            return left.workflowTitle.localizedStandardCompare(right.workflowTitle)
                == .orderedAscending
        }.prefix(maximumWorkflowContexts).map { $0 }
    }

    private static func attributedSecondsByWorkflow(
        activities: [ActivityRecord],
        range: Range<Date>,
        now: Date
    ) -> [UUID: TimeInterval] {
        var result: [UUID: TimeInterval] = [:]
        for activity in activities {
            guard let workflowID = activity.taskID,
                  ![.systemInactive, .trackerControl].contains(activity.classification) else {
                continue
            }
            let end = min(activity.endedAt ?? now, range.upperBound)
            let start = max(activity.startedAt, range.lowerBound)
            guard start < end else { continue }
            result[workflowID, default: 0] += end.timeIntervalSince(start)
        }
        return result
    }

    private static func clipped(
        _ interval: TaskIntervalRecord,
        to range: Range<Date>,
        now: Date
    ) -> TaskIntervalRecord? {
        let intervalEnd = interval.endedAt ?? now
        guard interval.startedAt < range.upperBound,
              intervalEnd >= range.lowerBound else {
            return nil
        }
        return TaskIntervalRecord(
            id: interval.id,
            taskID: interval.taskID,
            startedAt: max(interval.startedAt, range.lowerBound),
            endedAt: min(intervalEnd, range.upperBound),
            workflowSource: interval.workflowSource
        )
    }

    private static func destinationInterval(
        for marker: TimelineMarkerRecord,
        in intervals: [TaskIntervalRecord]
    ) -> TaskIntervalRecord? {
        let lowerBound = marker.date.addingTimeInterval(-2)
        var low = 0
        var high = intervals.count
        while low < high {
            let middle = (low + high) / 2
            if intervals[middle].startedAt < lowerBound {
                low = middle + 1
            } else {
                high = middle
            }
        }
        var best: TaskIntervalRecord?
        var index = low
        while index < intervals.count,
              intervals[index].startedAt <= marker.date.addingTimeInterval(2) {
            let candidate = intervals[index]
            if best == nil
                || abs(candidate.startedAt.timeIntervalSince(marker.date))
                    < abs(best!.startedAt.timeIntervalSince(marker.date)) {
                best = candidate
            }
            index += 1
        }
        return best
    }

    private static func destinationInterval(
        at date: Date,
        in intervals: [TaskIntervalRecord]
    ) -> TaskIntervalRecord? {
        destinationInterval(
            for: TimelineMarkerRecord(
                date: date,
                kind: .activeSpaceChanged
            ),
            in: intervals
        )
    }

    private static func title(
        for endpoint: WorkflowTransitionEndpoint,
        taskTitles: [UUID: String]
    ) -> String {
        switch endpoint.kind {
        case .workflow:
            return endpoint.workflowID.flatMap { taskTitles[$0] }
                ?? "已删除工作流"
        case .unbound:
            return "未绑定桌面"
        case .unknown:
            return "无法识别"
        case .conflict:
            return "绑定冲突"
        }
    }

    private static func isNearSemanticTransition(
        _ date: Date,
        dates: [Date]
    ) -> Bool {
        dates.contains { abs($0.timeIntervalSince(date)) <= 2 }
    }

    private static func containsDate(
        _ dates: [Date],
        after lowerBound: Date,
        through upperBound: Date
    ) -> Bool {
        var low = 0
        var high = dates.count
        while low < high {
            let middle = (low + high) / 2
            if dates[middle] <= lowerBound {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < dates.count && dates[low] <= upperBound
    }

    private static func reason(
        for kind: TimelineMarkerKind
    ) -> AutomationWorkflowSwitchReason? {
        switch kind {
        case .spaceSwitchCheckpoint:
            return .checkpoint
        case .spaceSwitchWaiting:
            return .waitingForResult
        case .spaceSwitchInterrupted:
            return .forcedInterruption
        case .spaceSwitchUnstructured:
            return .unstructured
        default:
            return nil
        }
    }

    private static func automationReason(
        _ reason: SpaceSwitchReason
    ) -> AutomationWorkflowSwitchReason {
        switch reason {
        case .reachedCheckpoint:
            return .checkpoint
        case .waitingForResult:
            return .waitingForResult
        case .forcedInterruption:
            return .forcedInterruption
        case .unstructured:
            return .unstructured
        }
    }

    private static func timeBucket(
        for date: Date,
        calendar: Calendar
    ) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12:
            return "morning"
        case 12..<18:
            return "afternoon"
        default:
            return "evening"
        }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        if values.count.isMultiple(of: 2) {
            let middle = values.count / 2
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[values.count / 2]
    }

    private static func boundedTitle(
        _ title: String,
        fallback: String
    ) -> String {
        let collapsed = title
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let usable = collapsed.isEmpty ? fallback : collapsed
        return String(usable.prefix(maximumTitleLength))
    }

    private struct RouteKey: Hashable {
        let fromWorkflow: String
        let toWorkflow: String
    }

    private struct TransitionSample {
        let reason: AutomationWorkflowSwitchReason?
        let outcome: String
        let destinationMinutes: Double?
        let returnedWithin30Minutes: Bool
        let timeBucket: String
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
