import Foundation

/// This is deliberately a behavioral estimate, not a neurological measurement.
/// A single composite "brain load score" would imply precision that application
/// events, workflow labels, and self-reports cannot provide.
public enum SwitchingLoadStatus: String, Codable, Equatable, Sendable {
    case unavailable
    case calibrating
    case mixedEvidence
    case stable
    case elevated
}

public enum SwitchingLoadConfidence: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

public enum SwitchingLoadTraceFamily: String, Codable, CaseIterable, Sendable {
    case applicationActivity
    case workflowIntervals
    case semanticTransitions
    case transitionReasons
    case navigationBursts
    case interruptions
    case focusFeedback
    case returnPoints
    case workflowRequirements
    case systemInactive
}

public enum SwitchingLoadTraceStatus: String, Codable, Equatable, Sendable {
    case used
    case noSample
    case qualityBlocked
}

public struct SwitchingLoadTraceUse: Codable, Equatable, Sendable {
    public let family: SwitchingLoadTraceFamily
    public let status: SwitchingLoadTraceStatus
    public let role: String

    public init(
        family: SwitchingLoadTraceFamily,
        status: SwitchingLoadTraceStatus,
        role: String
    ) {
        self.family = family
        self.status = status
        self.role = role
    }
}

public struct SwitchingLoadMetrics: Codable, Equatable, Sendable {
    public let activeMinutes: Double
    public let appSwitchesPerHour: Double
    public let withinWorkflowAppSwitchRatio: Double?
    public let peakFiveMinuteAppSwitches: Int
    public let highFragmentationWindows: Int
    public let activeFiveMinuteWindows: Int?
    public let finalWorkflowSwitches: Int
    public let plannedWorkflowSwitches: Int
    public let highRecoveryBurdenSwitches: Int
    public let navigationEventsPerBurst: Double?
    public let explicitReasonCoverage: Double?
    public let shortDestinationSwitches: Int
    public let returnedWithin30Minutes: Int
    public let returnPointResumeRate: Double?
    public let averageInterruptionReturnSeconds: Double?
    public let averageSubjectiveDifficulty: Double?
    public let subjectiveDifficultySamples: Int
    public let focusSuccessRate: Double?
    public let comparableBaselineDays: Int
    public let systemInactiveMinutes: Double

    public init(
        activeMinutes: Double,
        appSwitchesPerHour: Double,
        withinWorkflowAppSwitchRatio: Double?,
        peakFiveMinuteAppSwitches: Int,
        highFragmentationWindows: Int,
        activeFiveMinuteWindows: Int? = nil,
        finalWorkflowSwitches: Int,
        plannedWorkflowSwitches: Int,
        highRecoveryBurdenSwitches: Int,
        navigationEventsPerBurst: Double?,
        explicitReasonCoverage: Double?,
        shortDestinationSwitches: Int,
        returnedWithin30Minutes: Int,
        returnPointResumeRate: Double?,
        averageInterruptionReturnSeconds: Double?,
        averageSubjectiveDifficulty: Double?,
        subjectiveDifficultySamples: Int,
        focusSuccessRate: Double?,
        comparableBaselineDays: Int,
        systemInactiveMinutes: Double
    ) {
        self.activeMinutes = activeMinutes
        self.appSwitchesPerHour = appSwitchesPerHour
        self.withinWorkflowAppSwitchRatio = withinWorkflowAppSwitchRatio
        self.peakFiveMinuteAppSwitches = peakFiveMinuteAppSwitches
        self.highFragmentationWindows = highFragmentationWindows
        self.activeFiveMinuteWindows = activeFiveMinuteWindows
        self.finalWorkflowSwitches = finalWorkflowSwitches
        self.plannedWorkflowSwitches = plannedWorkflowSwitches
        self.highRecoveryBurdenSwitches = highRecoveryBurdenSwitches
        self.navigationEventsPerBurst = navigationEventsPerBurst
        self.explicitReasonCoverage = explicitReasonCoverage
        self.shortDestinationSwitches = shortDestinationSwitches
        self.returnedWithin30Minutes = returnedWithin30Minutes
        self.returnPointResumeRate = returnPointResumeRate
        self.averageInterruptionReturnSeconds = averageInterruptionReturnSeconds
        self.averageSubjectiveDifficulty = averageSubjectiveDifficulty
        self.subjectiveDifficultySamples = subjectiveDifficultySamples
        self.focusSuccessRate = focusSuccessRate
        self.comparableBaselineDays = comparableBaselineDays
        self.systemInactiveMinutes = systemInactiveMinutes
    }
}

public struct SwitchingLoadAssessment: Codable, Equatable, Sendable {
    public let version: Int
    public let status: SwitchingLoadStatus
    public let confidence: SwitchingLoadConfidence
    public let boundary: String
    public let headline: String
    public let convergingSignals: [String]
    public let evidence: [String]
    public let recommendedExperiment: String
    public let metrics: SwitchingLoadMetrics
    public let traceCoverage: [SwitchingLoadTraceUse]

    public init(
        version: Int = 1,
        status: SwitchingLoadStatus,
        confidence: SwitchingLoadConfidence,
        boundary: String = "行为切换负荷估计，不是脑活动、脑损伤或临床认知负荷测量",
        headline: String,
        convergingSignals: [String],
        evidence: [String],
        recommendedExperiment: String,
        metrics: SwitchingLoadMetrics,
        traceCoverage: [SwitchingLoadTraceUse]
    ) {
        self.version = version
        self.status = status
        self.confidence = confidence
        self.boundary = boundary
        self.headline = headline
        self.convergingSignals = convergingSignals
        self.evidence = evidence
        self.recommendedExperiment = recommendedExperiment
        self.metrics = metrics
        self.traceCoverage = traceCoverage
    }
}

public enum SwitchingLoadEngine {
    /// Product heuristics are intentionally relative to the person's recent
    /// baseline and require converging evidence. The 25% delta is an
    /// operational sensitivity threshold, not a clinical cutoff.
    public static let elevatedRelativeDeltaPercent = 25.0
    public static let minimumComparableBaselineDays = 3
    public static let minimumSubjectiveSamples = 3

    public static func assess(
        activities: [ActivityRecord],
        taskIntervals: [TaskIntervalRecord],
        focusSessions: [FocusSessionRecord],
        interruptions: [InterruptionRecord],
        workflowTransitions: [WorkflowTransitionRecord],
        taskParkings: [TaskParkingRecord],
        markers: [TimelineMarkerRecord],
        workflowContextCount: Int,
        range: DateInterval,
        now: Date,
        quality: DailyDataQuality,
        trend: DailyTrendComparison,
        transitionAudit: AutomationWorkflowTransitionAuditArtifact
    ) -> SwitchingLoadAssessment {
        let effectiveNow = min(now, range.end)
        let visibleActivities = activities
            .filter {
                ![.systemInactive, .trackerControl].contains($0.classification)
            }
            .sorted { $0.startedAt < $1.startedAt }
        let appSwitchPairs = zip(
            visibleActivities,
            visibleActivities.dropFirst()
        ).filter { $0.0.app.bundleID != $0.1.app.bundleID }
        let withinWorkflowSwitches = appSwitchPairs.filter {
            $0.0.taskID != nil && $0.0.taskID == $0.1.taskID
        }.count
        let withinWorkflowRatio = appSwitchPairs.isEmpty
            ? nil
            : Double(withinWorkflowSwitches) / Double(appSwitchPairs.count)

        let buckets = TimelineAggregationEngine.buckets(
            activities: visibleActivities,
            markers: markers,
            range: range,
            bucketMinutes: 5,
            now: effectiveNow
        )
        let peakSwitches = buckets.map(\.switchCount).max() ?? 0
        let highFragmentationWindows = buckets.filter {
            $0.activeSeconds > 0 && $0.switchCount >= 6
        }.count

        let finalTransitions = workflowTransitions.filter {
            WorkflowSwitchInterventionEngine.isFinalWorkflowSwitch($0)
        }
        let plannedSwitches = finalTransitions.filter {
            $0.reason == .reachedCheckpoint || $0.reason == .waitingForResult
        }.count
        let burdenSwitches = finalTransitions.filter {
            $0.reason == .forcedInterruption || $0.reason == .unstructured
        }.count
        let navigationEventsPerBurst = workflowTransitions.isEmpty
            ? nil
            : Double(workflowTransitions.reduce(0) { $0 + $1.navigationEventCount })
                / Double(workflowTransitions.count)
        let shortDestinationSwitches = transitionAudit.routes
            .filter { ($0.medianDestinationMinutes ?? .greatestFiniteMagnitude) < 5 }
            .reduce(0) { $0 + $1.count }
        let quickReturns = transitionAudit.routes.reduce(0) {
            $0 + $1.returnedWithin30Minutes
        }

        let resumedParkings = taskParkings.filter { $0.resumedAt != nil }.count
        let parkingResumeRate = taskParkings.isEmpty
            ? nil
            : Double(resumedParkings) / Double(taskParkings.count)
        let returnLatencies = interruptions.compactMap { interruption -> Double? in
            guard interruption.resolution == .returnedToTask,
                  let resolvedAt = interruption.resolvedAt else {
                return nil
            }
            return max(0, resolvedAt.timeIntervalSince(interruption.detectedAt))
        }
        let averageReturnSeconds = average(returnLatencies)
        let difficulties = focusSessions.compactMap {
            $0.difficulty.map(Double.init)
        }
        let averageDifficulty = average(difficulties)
        let focusSuccessRate = focusSessions.isEmpty
            ? nil
            : Double(focusSessions.filter(\.isSuccessful).count)
                / Double(focusSessions.count)
        let inactiveRanges = SystemInactiveIntervalEngine.inactiveRanges(
            markers: markers,
            range: range,
            now: effectiveNow
        )
        let systemInactiveMinutes = inactiveRanges.reduce(0) {
            $0 + $1.duration
        } / 60

        let metrics = SwitchingLoadMetrics(
            activeMinutes: visibleActivities.reduce(0) {
                $0 + $1.duration(relativeTo: effectiveNow)
            } / 60,
            appSwitchesPerHour: appSwitchPairs.isEmpty
                ? 0
                : Double(appSwitchPairs.count) / max(
                    1.0 / 60,
                    visibleActivities.reduce(0) {
                        $0 + $1.duration(relativeTo: effectiveNow)
                    } / 3_600
                ),
            withinWorkflowAppSwitchRatio: withinWorkflowRatio,
            peakFiveMinuteAppSwitches: peakSwitches,
            highFragmentationWindows: highFragmentationWindows,
            activeFiveMinuteWindows: buckets.filter { $0.activeSeconds > 0 }.count,
            finalWorkflowSwitches: finalTransitions.count,
            plannedWorkflowSwitches: plannedSwitches,
            highRecoveryBurdenSwitches: burdenSwitches,
            navigationEventsPerBurst: navigationEventsPerBurst,
            explicitReasonCoverage: transitionAudit.explicitReasonCoverage,
            shortDestinationSwitches: shortDestinationSwitches,
            returnedWithin30Minutes: quickReturns,
            returnPointResumeRate: parkingResumeRate,
            averageInterruptionReturnSeconds: averageReturnSeconds,
            averageSubjectiveDifficulty: averageDifficulty,
            subjectiveDifficultySamples: difficulties.count,
            focusSuccessRate: focusSuccessRate,
            comparableBaselineDays: trend.baselineDays,
            systemInactiveMinutes: systemInactiveMinutes
        )

        let traceCoverage = coverage(
            activities: visibleActivities,
            taskIntervals: taskIntervals,
            focusSessions: focusSessions,
            interruptions: interruptions,
            workflowTransitions: workflowTransitions,
            taskParkings: taskParkings,
            markers: markers,
            workflowContextCount: workflowContextCount,
            quality: quality
        )

        guard quality.isReliableForBehavior else {
            return SwitchingLoadAssessment(
                status: .unavailable,
                confidence: .low,
                headline: "当前不能据此判断切换负荷",
                convergingSignals: [],
                evidence: [
                    "有效行为镜头未达到可靠门槛",
                    "已审计所有 trace 家族，但质量门禁阻止行为结论"
                ],
                recommendedExperiment: "先完成日报指出的唯一数据质量修复，再观察至少 30 分钟",
                metrics: metrics,
                traceCoverage: traceCoverage
            )
        }

        let applicationPressure = quality.isReliable(.fragmentation)
            && (trend.appSwitchRateDeltaPercent ?? 0)
                >= elevatedRelativeDeltaPercent
        let workflowPressure = quality.isReliable(.workflowSemantics)
            && (trend.workflowSwitchRateDeltaPercent ?? 0)
                >= elevatedRelativeDeltaPercent
        let recoveryPressure = quality.isReliable(.contextRecovery)
            && burdenSwitches >= 2
            && (
                quickReturns >= 2
                    || shortDestinationSwitches >= 2
                    || (parkingResumeRate.map { $0 < 0.5 } == true)
            )
        let subjectivePressure = difficulties.count >= minimumSubjectiveSamples
            && (averageDifficulty ?? 0) >= 4
        let performancePressure = focusSessions.count >= minimumSubjectiveSamples
            && (focusSuccessRate ?? 1) <= 0.4

        var signals: [String] = []
        if applicationPressure {
            signals.append("应用碎片较个人基线上升")
        }
        if workflowPressure {
            signals.append("工作流切换较个人基线上升")
        }
        if recoveryPressure {
            signals.append("切换后恢复负担升高")
        }
        if subjectivePressure {
            signals.append("主观专注难度持续偏高")
        }
        if performancePressure {
            signals.append("训练完成结果持续承压")
        }

        let behaviorChannel = applicationPressure || workflowPressure
        let recoveryChannel = recoveryPressure
        let subjectiveOrOutcomeChannel = subjectivePressure || performancePressure
        let convergingChannelCount = [
            behaviorChannel,
            recoveryChannel,
            subjectiveOrOutcomeChannel
        ].filter { $0 }.count
        let calibrated = trend.baselineDays >= minimumComparableBaselineDays
            && difficulties.count >= minimumSubjectiveSamples
        let status: SwitchingLoadStatus
        if !calibrated {
            status = .calibrating
        } else if convergingChannelCount >= 2 {
            status = .elevated
        } else if convergingChannelCount == 1 {
            status = .mixedEvidence
        } else {
            status = .stable
        }
        let confidence: SwitchingLoadConfidence
        if calibrated,
           trend.baselineDays >= 5,
           difficulties.count >= 5 {
            confidence = .high
        } else if calibrated {
            confidence = .medium
        } else {
            confidence = .low
        }

        return SwitchingLoadAssessment(
            status: status,
            confidence: confidence,
            headline: headline(for: status),
            convergingSignals: signals,
            evidence: evidence(
                metrics: metrics,
                trend: trend,
                applicationPressure: applicationPressure,
                workflowPressure: workflowPressure,
                recoveryPressure: recoveryPressure,
                subjectivePressure: subjectivePressure
            ),
            recommendedExperiment: experiment(
                status: status,
                withinWorkflowRatio: withinWorkflowRatio,
                applicationPressure: applicationPressure,
                workflowPressure: workflowPressure,
                recoveryPressure: recoveryPressure,
                subjectivePressure: subjectivePressure,
                taskParkings: taskParkings
            ),
            metrics: metrics,
            traceCoverage: traceCoverage
        )
    }

    private static func headline(
        for status: SwitchingLoadStatus
    ) -> String {
        switch status {
        case .unavailable:
            return "当前不能据此判断切换负荷"
        case .calibrating:
            return "已有行为信号，但尚未完成个人校准"
        case .mixedEvidence:
            return "一项负荷信号升高，其他证据尚未收敛"
        case .stable:
            return "切换负荷未高于个人近期基线"
        case .elevated:
            return "多类证据共同指向切换负荷升高"
        }
    }

    private static func evidence(
        metrics: SwitchingLoadMetrics,
        trend: DailyTrendComparison,
        applicationPressure: Bool,
        workflowPressure: Bool,
        recoveryPressure: Bool,
        subjectivePressure: Bool
    ) -> [String] {
        var result: [String] = []
        if applicationPressure, let delta = trend.appSwitchRateDeltaPercent {
            result.append(
                "应用切换率较个人基线升高 \(Int(delta.rounded()))%"
            )
        }
        if workflowPressure, let delta = trend.workflowSwitchRateDeltaPercent {
            result.append(
                "工作流切换率较个人基线升高 \(Int(delta.rounded()))%"
            )
        }
        if recoveryPressure {
            result.append(
                "高恢复负担切换 \(metrics.highRecoveryBurdenSwitches) 次，"
                    + "30 分钟内返回 \(metrics.returnedWithin30Minutes) 次"
            )
        }
        if subjectivePressure, let difficulty = metrics.averageSubjectiveDifficulty {
            result.append(
                "主观专注难度 \(String(format: "%.1f", difficulty))/5，"
                    + "样本 \(metrics.subjectiveDifficultySamples) 次"
            )
        }
        if result.isEmpty {
            result.append(
                "高切换五分钟窗口 \(metrics.highFragmentationWindows) 个"
            )
            result.append(
                "高恢复负担切换 \(metrics.highRecoveryBurdenSwitches) 次"
            )
        }
        return Array(result.prefix(3))
    }

    private static func experiment(
        status: SwitchingLoadStatus,
        withinWorkflowRatio: Double?,
        applicationPressure: Bool,
        workflowPressure: Bool,
        recoveryPressure: Bool,
        subjectivePressure: Bool,
        taskParkings: [TaskParkingRecord]
    ) -> String {
        if status == .unavailable {
            return "先完成日报指出的唯一数据质量修复，再观察至少 30 分钟"
        }
        if recoveryPressure {
            return "下一次离开未完成工作流前写下“回来先做什么”，保存返回点；下一工作日只检查是否返回及返回耗时"
        }
        if applicationPressure,
           (withinWorkflowRatio ?? 0) >= 0.7,
           !workflowPressure {
            return "先不减少同一工作流内的必要工具切换；做一轮单一产出训练，只检查高切换五分钟窗口是否减少"
        }
        if applicationPressure || workflowPressure {
            return "下一次跨工作流只在明确检查点切换；下一工作日检查同一路线的短停留和 30 分钟内返回"
        }
        if subjectivePressure {
            return "暂不增加训练时长；再完成一轮相同时长训练并记录难度，等待行为与主观证据收敛"
        }
        if taskParkings.contains(where: { $0.resumedAt == nil }) {
            return "先返回一个已保存的工作流并执行第一步，只验证恢复闭环"
        }
        return "保持当前方法，再收集一轮带完成结果和主观难度的训练样本"
    }

    private static func coverage(
        activities: [ActivityRecord],
        taskIntervals: [TaskIntervalRecord],
        focusSessions: [FocusSessionRecord],
        interruptions: [InterruptionRecord],
        workflowTransitions: [WorkflowTransitionRecord],
        taskParkings: [TaskParkingRecord],
        markers: [TimelineMarkerRecord],
        workflowContextCount: Int,
        quality: DailyDataQuality
    ) -> [SwitchingLoadTraceUse] {
        let semanticStatus: SwitchingLoadTraceStatus = quality.isReliable(.workflowSemantics)
            ? sampleStatus(!workflowTransitions.isEmpty)
            : .qualityBlocked
        let reasonStatus: SwitchingLoadTraceStatus
        if !quality.isReliable(.workflowSemantics) {
            reasonStatus = .qualityBlocked
        } else {
            reasonStatus = sampleStatus(
                workflowTransitions.contains { $0.reason != nil }
            )
        }
        return [
            SwitchingLoadTraceUse(
                family: .applicationActivity,
                status: sampleStatus(!activities.isEmpty),
                role: "应用切换率、同工作流工具切换和五分钟碎片窗口"
            ),
            SwitchingLoadTraceUse(
                family: .workflowIntervals,
                status: sampleStatus(!taskIntervals.isEmpty),
                role: "工作流归因、目的工作流停留与跨上下文边界"
            ),
            SwitchingLoadTraceUse(
                family: .semanticTransitions,
                status: semanticStatus,
                role: "最终工作流路线、结果和切换后果"
            ),
            SwitchingLoadTraceUse(
                family: .transitionReasons,
                status: reasonStatus,
                role: "区分检查点、等待结果、被迫中断和无结构切换"
            ),
            SwitchingLoadTraceUse(
                family: .navigationBursts,
                status: semanticStatus,
                role: "连续 Space 导航事件与最终落点搜索强度"
            ),
            SwitchingLoadTraceUse(
                family: .interruptions,
                status: sampleStatus(!interruptions.isEmpty),
                role: "确认偏离和返回耗时"
            ),
            SwitchingLoadTraceUse(
                family: .focusFeedback,
                status: sampleStatus(
                    focusSessions.contains { $0.difficulty != nil }
                ),
                role: "目标完成、主观难度和行为信号校准"
            ),
            SwitchingLoadTraceUse(
                family: .returnPoints,
                status: sampleStatus(!taskParkings.isEmpty),
                role: "保存上下文、实际返回和恢复耗时"
            ),
            SwitchingLoadTraceUse(
                family: .workflowRequirements,
                status: quality.isReliable(.workflowSemantics)
                    ? sampleStatus(workflowContextCount > 0)
                    : .qualityBlocked,
                role: "只作为路线目标语义上下文，不单独判断负荷"
            ),
            SwitchingLoadTraceUse(
                family: .systemInactive,
                status: sampleStatus(markers.contains {
                    [.screenSlept, .screenWoke, .sessionBecameInactive, .sessionBecameActive]
                        .contains($0.kind)
                }),
                role: "排除锁屏、睡眠和会话非活动时间"
            )
        ]
    }

    private static func sampleStatus(
        _ hasSample: Bool
    ) -> SwitchingLoadTraceStatus {
        hasSample ? .used : .noSample
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
