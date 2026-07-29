import Foundation

public enum ObservationLens: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case dataQuality
    case fragmentation
    case contextRecovery
    case workflowSemantics
}

public enum ObservationPlanSource: String, Codable, Equatable, Sendable {
    case initialDefault
    case todayAndRecentWorkdays
}

public enum RawCollectionMode: String, Codable, Equatable, Sendable {
    case minimalEventDrivenFixed
}

public struct ObservationAllocation: Codable, Equatable, Sendable {
    public let lens: ObservationLens
    public let percent: Int
    public let reason: String

    public init(lens: ObservationLens, percent: Int, reason: String) {
        self.lens = lens
        self.percent = percent
        self.reason = reason
    }
}

public struct DailyObservationPlan: Codable, Equatable, Sendable {
    public let version: Int
    public let source: ObservationPlanSource
    public let lookbackWorkdays: Int
    public let rawCollectionMode: RawCollectionMode
    public let allocations: [ObservationAllocation]
    public let interventionConfiguration: WorkflowInterventionConfiguration
    public let interventionRecommendation: String

    public init(
        version: Int = 1,
        source: ObservationPlanSource,
        lookbackWorkdays: Int,
        rawCollectionMode: RawCollectionMode = .minimalEventDrivenFixed,
        allocations: [ObservationAllocation],
        interventionConfiguration: WorkflowInterventionConfiguration = .initial,
        interventionRecommendation: String
    ) {
        self.version = version
        self.source = source
        self.lookbackWorkdays = lookbackWorkdays
        self.rawCollectionMode = rawCollectionMode
        self.allocations = allocations
        self.interventionConfiguration = interventionConfiguration
        self.interventionRecommendation = interventionRecommendation
    }

    public var primaryAllocation: ObservationAllocation? {
        allocations.max {
            if $0.percent != $1.percent {
                return $0.percent < $1.percent
            }
            let left = ObservationLens.allCases.firstIndex(of: $0.lens) ?? 0
            let right = ObservationLens.allCases.firstIndex(of: $1.lens) ?? 0
            return left > right
        }
    }
}

/// Chooses how much analysis attention each evidence class receives.
///
/// It never changes the raw event set or sampling rate. That distinction keeps
/// the timeline complete and comparisons across days meaningful.
public enum ObservationPlanEngine {
    public static func makePlan(
        coaching: DailyCoachingAnalysis,
        summary: DailySummary,
        interventionAudit: WorkflowInterventionAudit
    ) -> DailyObservationPlan {
        guard coaching.metrics.recordedMinutes > 0 else {
            return DailyObservationPlan(
                source: .initialDefault,
                lookbackWorkdays: 0,
                allocations: ObservationLens.allCases.map {
                    ObservationAllocation(
                        lens: $0,
                        percent: 25,
                        reason: "尚无当天证据，使用均衡初始配置"
                    )
                },
                interventionRecommendation: "先保持初始确认规则，等待可比较数据"
            )
        }

        var weights = Dictionary(
            uniqueKeysWithValues: ObservationLens.allCases.map { ($0, 1.0) }
        )
        var reasons: [ObservationLens: String] = [
            .dataQuality: "核对记录完整性与工作流归因",
            .fragmentation: "比较应用切换率与连续专注",
            .contextRecovery: "检查保存返回点与恢复耗时",
            .workflowSemantics: "联合判断工作目标、切换原因与切换后果"
        ]

        if !coaching.quality.isReliableForBehavior {
            weights[.dataQuality] = 7
            reasons[.dataQuality] = "行为数据尚不可靠，先修复最高优先级的数据问题"
        } else {
            if !coaching.quality.isReliable(.workflowSemantics) {
                weights[.dataQuality, default: 1] += 2
                weights[.workflowSemantics] = 0.25
                reasons[.dataQuality] = "说明 trace 补全与未归因范围，不阻塞其他可靠分析"
                reasons[.workflowSemantics] = "命名工作流证据不足，本次不判断路线语义"
            }

            if coaching.quality.isReliable(.fragmentation),
               let delta = coaching.trend.appSwitchRateDeltaPercent,
               delta >= 15 {
                weights[.fragmentation, default: 1] += 2
                reasons[.fragmentation] = "应用切换率较近 \(coaching.trend.baselineDays) 个可比工作日上升"
            }

            let incompleteParkings = max(
                0,
                summary.taskParkingCount - summary.resumedTaskCount
            )
            if coaching.quality.isReliable(.contextRecovery),
               incompleteParkings > 0
                || (summary.averageTaskResumeLatency ?? 0) >= 10 * 60 {
                weights[.contextRecovery, default: 1] += 2
                reasons[.contextRecovery] = incompleteParkings > 0
                    ? "存在尚未恢复的工作流返回点"
                    : "工作流恢复耗时达到 10 分钟"
            }

            let semanticEvents = interventionAudit.frequentSwitchEpisodes > 0
                || (coaching.trend.workflowSwitchRateDeltaPercent ?? 0) >= 15
            if coaching.quality.isReliable(.workflowSemantics), semanticEvents {
                weights[.workflowSemantics, default: 1] += 2
                reasons[.workflowSemantics] = interventionAudit.frequentSwitchEpisodes > 0
                    ? "出现高频工作流切换段，需要区分目标连续与上下文重置"
                    : "工作流切换率较近期可比日上升"
            }
        }

        let allocations = normalizedAllocations(
            weights: weights,
            reasons: reasons
        )
        let interventionRecommendation: String
        if interventionAudit.assessedPrompts < 5 {
            interventionRecommendation = "保持当前确认规则；至少 5 个完整观察窗后再评估"
        } else if let rate = interventionAudit.quietAfterPromptRate,
                  rate < 0.4 {
            interventionRecommendation = "确认后的稳定效果偏弱；优先改善切换前的交接，不增加弹窗"
        } else {
            interventionRecommendation = "当前确认规则已有足够观察窗，继续保持"
        }

        return DailyObservationPlan(
            source: .todayAndRecentWorkdays,
            lookbackWorkdays: coaching.trend.baselineDays,
            allocations: allocations,
            interventionRecommendation: interventionRecommendation
        )
    }

    private static func normalizedAllocations(
        weights: [ObservationLens: Double],
        reasons: [ObservationLens: String]
    ) -> [ObservationAllocation] {
        let total = ObservationLens.allCases.reduce(0) {
            $0 + max(0, weights[$1, default: 0])
        }
        guard total > 0 else { return [] }

        var values = ObservationLens.allCases.map { lens -> (
            lens: ObservationLens,
            percent: Int,
            fraction: Double
        ) in
            let exact = max(0, weights[lens, default: 0]) / total * 100
            let floor = Int(exact.rounded(.down))
            return (lens, floor, exact - Double(floor))
        }
        var remaining = 100 - values.reduce(0) { $0 + $1.percent }
        let order = values.indices.sorted {
            if values[$0].fraction != values[$1].fraction {
                return values[$0].fraction > values[$1].fraction
            }
            return $0 < $1
        }
        for index in order where remaining > 0 {
            values[index].percent += 1
            remaining -= 1
        }
        return values.map {
            ObservationAllocation(
                lens: $0.lens,
                percent: $0.percent,
                reason: reasons[$0.lens] ?? "使用默认分析规则"
            )
        }
    }
}
