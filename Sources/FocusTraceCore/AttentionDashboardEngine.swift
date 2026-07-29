import Foundation

/// Five stable, explainable dimensions for the daily attention dashboard.
/// These are behavioral indicators, not a neurological or clinical score.
public enum AttentionDashboardMetricKind: String, Codable, CaseIterable, Sendable {
    case sustainedProgress
    case fragmentation
    case switchingBoundary
    case contextRecovery
    case trainingFeedback
}

public enum AttentionDashboardMetricState: String, Codable, Equatable, Sendable {
    case unavailable
    case calibrating
    case observed
    case improving
    case needsAttention
}

public enum AttentionTrendDirection: String, Codable, Equatable, Sendable {
    case calibrating
    case stable
    case improving
    case worsening
}

public enum AttentionDashboardFindingState: String, Codable, Equatable, Sendable {
    case calibrating
    case stable
    case improving
    case needsAttention
}

public struct AttentionTrendPoint: Identifiable, Codable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let value: Double?
    public let secondaryValue: Double?
    public let sampleCount: Int
    public let isReliable: Bool
    public let isPartial: Bool

    public init(
        date: Date,
        value: Double?,
        secondaryValue: Double? = nil,
        sampleCount: Int,
        isReliable: Bool,
        isPartial: Bool
    ) {
        self.date = date
        self.value = value
        self.secondaryValue = secondaryValue
        self.sampleCount = max(0, sampleCount)
        self.isReliable = isReliable
        self.isPartial = isPartial
    }
}

public struct AttentionMetricTrend: Codable, Equatable, Sendable {
    public let kind: AttentionDashboardMetricKind
    public let unit: String
    public let lowerIsBetter: Bool
    public let direction: AttentionTrendDirection
    public let points: [AttentionTrendPoint]
    public let baselineMedian: Double?
    public let recentMedian: Double?
    public let typicalLowerBound: Double?
    public let typicalUpperBound: Double?
    public let reliableDayCount: Int
    public let comparison: String

    public init(
        kind: AttentionDashboardMetricKind,
        unit: String,
        lowerIsBetter: Bool,
        direction: AttentionTrendDirection,
        points: [AttentionTrendPoint],
        baselineMedian: Double?,
        recentMedian: Double?,
        typicalLowerBound: Double?,
        typicalUpperBound: Double?,
        reliableDayCount: Int,
        comparison: String
    ) {
        self.kind = kind
        self.unit = unit
        self.lowerIsBetter = lowerIsBetter
        self.direction = direction
        self.points = Array(points.suffix(10))
        self.baselineMedian = baselineMedian
        self.recentMedian = recentMedian
        self.typicalLowerBound = typicalLowerBound
        self.typicalUpperBound = typicalUpperBound
        self.reliableDayCount = reliableDayCount
        self.comparison = comparison
    }
}

public struct AttentionDashboardFinding: Codable, Equatable, Sendable {
    public let state: AttentionDashboardFindingState
    public let kind: AttentionDashboardMetricKind?
    public let title: String
    public let detail: String
    public let evidence: [String]

    public init(
        state: AttentionDashboardFindingState,
        kind: AttentionDashboardMetricKind?,
        title: String,
        detail: String,
        evidence: [String]
    ) {
        self.state = state
        self.kind = kind
        self.title = title
        self.detail = detail
        self.evidence = Array(evidence.prefix(2))
    }
}

public struct AttentionDashboardDay: Equatable, Sendable {
    public let date: Date
    public let isPartial: Bool
    public let coaching: DailyCoachingAnalysis
    public let summary: DailySummary
    public let switchingLoad: SwitchingLoadAssessment
    public let interventionAudit: WorkflowInterventionAudit
    public let focusSessions: [FocusSessionRecord]

    public init(
        date: Date,
        isPartial: Bool,
        coaching: DailyCoachingAnalysis,
        summary: DailySummary,
        switchingLoad: SwitchingLoadAssessment,
        interventionAudit: WorkflowInterventionAudit,
        focusSessions: [FocusSessionRecord]
    ) {
        self.date = date
        self.isPartial = isPartial
        self.coaching = coaching
        self.summary = summary
        self.switchingLoad = switchingLoad
        self.interventionAudit = interventionAudit
        self.focusSessions = focusSessions
    }
}

public struct AttentionDashboardComparisonBar: Codable, Equatable, Sendable {
    public let label: String
    public let value: Double
    public let formattedValue: String

    public init(label: String, value: Double, formattedValue: String) {
        self.label = label
        self.value = max(0, value)
        self.formattedValue = formattedValue
    }
}

public struct AttentionDashboardMetric: Identifiable, Codable, Equatable, Sendable {
    public var id: AttentionDashboardMetricKind { kind }
    public let kind: AttentionDashboardMetricKind
    public let state: AttentionDashboardMetricState
    public let title: String
    public let value: String
    public let comparison: String
    public let evidence: [String]
    public let bars: [AttentionDashboardComparisonBar]
    public let trend: AttentionMetricTrend?

    public init(
        kind: AttentionDashboardMetricKind,
        state: AttentionDashboardMetricState,
        title: String,
        value: String,
        comparison: String,
        evidence: [String],
        bars: [AttentionDashboardComparisonBar] = [],
        trend: AttentionMetricTrend? = nil
    ) {
        self.kind = kind
        self.state = state
        self.title = title
        self.value = value
        self.comparison = comparison
        self.evidence = Array(evidence.prefix(2))
        self.bars = Array(bars.prefix(3))
        self.trend = trend
    }
}

public struct AttentionDashboard: Codable, Equatable, Sendable {
    public let version: Int
    public let boundary: String
    public let recordedMinutes: Double
    public let baselineDays: Int
    public let reliableDimensionCount: Int
    public let metrics: [AttentionDashboardMetric]
    public let periodStart: Date?
    public let periodEnd: Date?
    public let includesPartialDay: Bool?
    public let finding: AttentionDashboardFinding?
    public let recommendation: DailyCoachRecommendation?

    public init(
        version: Int = 1,
        boundary: String = "五个行为维度分别判断，不合成为注意力、脑负荷或临床总分",
        recordedMinutes: Double,
        baselineDays: Int,
        reliableDimensionCount: Int,
        metrics: [AttentionDashboardMetric],
        periodStart: Date? = nil,
        periodEnd: Date? = nil,
        includesPartialDay: Bool? = nil,
        finding: AttentionDashboardFinding? = nil,
        recommendation: DailyCoachRecommendation? = nil
    ) {
        self.version = version
        self.boundary = boundary
        self.recordedMinutes = recordedMinutes
        self.baselineDays = baselineDays
        self.reliableDimensionCount = reliableDimensionCount
        self.metrics = metrics
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.includesPartialDay = includesPartialDay
        self.finding = finding
        self.recommendation = recommendation
    }
}

public enum AttentionDashboardEngine {
    public static let minimumTrainingSamples = 5
    public static let minimumReasonCoverage = 0.5
    public static let trendWorkdayCount = 10
    public static let minimumTrendDays = 5
    public static let recentTrendDays = 3

    public static func make(
        coaching: DailyCoachingAnalysis,
        summary: DailySummary,
        switchingLoad: SwitchingLoadAssessment,
        interventionAudit: WorkflowInterventionAudit
    ) -> AttentionDashboard {
        let metrics = [
            sustainedProgress(coaching: coaching),
            fragmentation(coaching: coaching, switchingLoad: switchingLoad),
            switchingBoundary(
                coaching: coaching,
                switchingLoad: switchingLoad,
                interventionAudit: interventionAudit
            ),
            contextRecovery(
                coaching: coaching,
                summary: summary,
                switchingLoad: switchingLoad
            ),
            trainingFeedback(
                coaching: coaching,
                switchingLoad: switchingLoad
            )
        ]
        let reliableCount = metrics.filter {
            ![.unavailable, .calibrating].contains($0.state)
        }.count
        return AttentionDashboard(
            recordedMinutes: coaching.metrics.recordedMinutes,
            baselineDays: coaching.trend.baselineDays,
            reliableDimensionCount: reliableCount,
            metrics: metrics
        )
    }

    public static func candidateDates(
        in snapshot: FocusTraceLocalSnapshot,
        through reportDate: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let limit = calendar.startOfDay(for: reportDate)
        let dates = Set(snapshot.activities.compactMap { activity -> Date? in
            let day = calendar.startOfDay(for: activity.startedAt)
            return day <= limit ? day : nil
        })
        return Array(
            dates.union([limit]).sorted().suffix(trendWorkdayCount)
        )
    }

    public static func make(
        days: [AttentionDashboardDay],
        currentPlan: TrainingPlanRecord
    ) -> AttentionDashboard {
        let ordered = days.sorted { $0.date < $1.date }
        guard let current = ordered.last else {
            let fallback = unavailableDashboard()
            return fallback
        }
        let daily = make(
            coaching: current.coaching,
            summary: current.summary,
            switchingLoad: current.switchingLoad,
            interventionAudit: current.interventionAudit
        )
        let trends = Dictionary(
            uniqueKeysWithValues: AttentionDashboardMetricKind.allCases.map {
                ($0, trend(kind: $0, days: ordered))
            }
        )
        let metrics = daily.metrics.map { metric in
            guard let metricTrend = trends[metric.kind] else { return metric }
            return metricWithTrend(metric, trend: metricTrend)
        }
        let finding = primaryFinding(metrics: metrics)
        let recommendation = trendRecommendation(
            finding: finding,
            metrics: metrics,
            currentPlan: currentPlan
        )
        let reliableCount = metrics.filter {
            guard let trend = $0.trend else { return false }
            return trend.direction != .calibrating
        }.count
        return AttentionDashboard(
            version: 2,
            boundary: "纵向行为趋势，不合成为注意力、脑负荷或临床总分；未结束日期不参与趋势结论",
            recordedMinutes: current.coaching.metrics.recordedMinutes,
            baselineDays: ordered.filter {
                !$0.isPartial && $0.coaching.metrics.recordedMinutes > 0
            }.count,
            reliableDimensionCount: reliableCount,
            metrics: metrics,
            periodStart: ordered.first?.date,
            periodEnd: ordered.last?.date,
            includesPartialDay: ordered.contains(where: \.isPartial),
            finding: finding,
            recommendation: recommendation
        )
    }

    private static func unavailableDashboard() -> AttentionDashboard {
        let metrics = AttentionDashboardMetricKind.allCases.map {
            unavailable(
                kind: $0,
                title: title(for: $0),
                reason: "还没有可用于纵向比较的工作日"
            )
        }
        let finding = AttentionDashboardFinding(
            state: .calibrating,
            kind: nil,
            title: "正在建立趋势样本",
            detail: "至少需要 5 个可靠工作日，当前不会据此判断注意力。",
            evidence: ["继续按正常方式工作，不需要刻意制造或减少切换"]
        )
        return AttentionDashboard(
            version: 2,
            recordedMinutes: 0,
            baselineDays: 0,
            reliableDimensionCount: 0,
            metrics: metrics,
            finding: finding,
            recommendation: nil
        )
    }

    private static func sustainedProgress(
        coaching: DailyCoachingAnalysis
    ) -> AttentionDashboardMetric {
        guard coaching.quality.isReliable(.fragmentation),
              coaching.quality.isReliable(.workflowSemantics),
              let current = coaching.metrics.medianFocusMinutes else {
            return unavailable(
                kind: .sustainedProgress,
                title: "稳定推进",
                reason: "需要至少 30 分钟有效记录和可靠工作流归因"
            )
        }
        guard coaching.trend.baselineDays >= 2,
              let delta = coaching.trend.medianFocusDeltaMinutes else {
            return AttentionDashboardMetric(
                kind: .sustainedProgress,
                state: .calibrating,
                title: "稳定推进",
                value: minutes(current),
                comparison: "正在建立个人基线",
                evidence: ["同一工作流允许应用内的中位连续时长"],
                bars: [
                    bar("今天", current, minutes(current))
                ]
            )
        }

        let baseline = max(0, current - delta)
        let meaningfulDelta = max(2, baseline * 0.15)
        let state: AttentionDashboardMetricState
        if delta >= meaningfulDelta {
            state = .improving
        } else if delta <= -meaningfulDelta {
            state = .needsAttention
        } else {
            state = .observed
        }
        return AttentionDashboardMetric(
            kind: .sustainedProgress,
            state: state,
            title: "稳定推进",
            value: minutes(current),
            comparison: relativeMinutes(delta),
            evidence: [
                "同一工作流允许应用内的中位连续时长",
                "只和你最近的可比工作日比较"
            ],
            bars: [
                bar("今天", current, minutes(current)),
                bar("个人基线", baseline, minutes(baseline))
            ]
        )
    }

    private static func fragmentation(
        coaching: DailyCoachingAnalysis,
        switchingLoad: SwitchingLoadAssessment
    ) -> AttentionDashboardMetric {
        guard coaching.quality.isReliable(.fragmentation) else {
            return unavailable(
                kind: .fragmentation,
                title: "碎片控制",
                reason: "有效记录不足，暂不把应用切换解释成碎片"
            )
        }
        let metrics = switchingLoad.metrics
        let withinWorkflow = metrics.withinWorkflowAppSwitchRatio
        let sameWorkflowQualified = (withinWorkflow ?? 0) >= 0.7
        let delta = coaching.trend.appSwitchRateDeltaPercent
        let activeWindows = metrics.activeFiveMinuteWindows ?? 0
        let highWindowShare = activeWindows > 0
            ? Double(metrics.highFragmentationWindows) / Double(activeWindows)
            : 0
        let concentratedFragmentation = activeWindows >= 4
            && metrics.highFragmentationWindows >= 3
            && highWindowShare >= 0.5
            && !sameWorkflowQualified
        let state: AttentionDashboardMetricState
        if coaching.trend.baselineDays < 2 || delta == nil {
            state = .calibrating
        } else if concentratedFragmentation
                    || (
                        (delta ?? 0)
                            >= SwitchingLoadEngine.elevatedRelativeDeltaPercent
                            && !sameWorkflowQualified
                    ) {
            state = .needsAttention
        } else if (delta ?? 0)
                    <= -SwitchingLoadEngine.elevatedRelativeDeltaPercent {
            state = .improving
        } else {
            state = .observed
        }

        var evidence = [
            "峰值 \(metrics.peakFiveMinuteAppSwitches) 次 / 5 分钟"
        ]
        if let withinWorkflow {
            evidence.append(
                "\(percent(withinWorkflow)) 属于同一工作流工具协作，不直接等于分心"
            )
        } else {
            evidence.append("没有足够工作流归因来区分工具协作")
        }
        return AttentionDashboardMetric(
            kind: .fragmentation,
            state: state,
            title: "碎片控制",
            value: "\(metrics.highFragmentationWindows) 个",
            comparison: fragmentationComparison(
                delta: delta,
                highWindowShare: highWindowShare,
                concentratedFragmentation: concentratedFragmentation,
                sameWorkflowQualified: sameWorkflowQualified
            ),
            evidence: evidence,
            bars: [
                bar(
                    "高碎片窗口",
                    Double(metrics.highFragmentationWindows),
                    "\(metrics.highFragmentationWindows)"
                ),
                bar(
                    "有效五分钟窗口",
                    Double(activeWindows),
                    activeWindows > 0 ? "\(activeWindows)" : "—"
                )
            ]
        )
    }

    private static func switchingBoundary(
        coaching: DailyCoachingAnalysis,
        switchingLoad: SwitchingLoadAssessment,
        interventionAudit: WorkflowInterventionAudit
    ) -> AttentionDashboardMetric {
        guard coaching.quality.isReliable(.workflowSemantics) else {
            return unavailable(
                kind: .switchingBoundary,
                title: "切换边界",
                reason: "工作流归因或 Space 语义尚不可靠"
            )
        }
        let metrics = switchingLoad.metrics
        guard metrics.finalWorkflowSwitches > 0 else {
            return unavailable(
                kind: .switchingBoundary,
                title: "切换边界",
                reason: "今天没有可分析的最终工作流切换"
            )
        }

        let reasonCoverage = metrics.explicitReasonCoverage
        let hasRecoveryConsequence = metrics.shortDestinationSwitches >= 2
            || metrics.returnedWithin30Minutes >= 2
        let state: AttentionDashboardMetricState
        if (reasonCoverage ?? 0) < minimumReasonCoverage {
            state = .calibrating
        } else if metrics.highRecoveryBurdenSwitches >= 2
                    && hasRecoveryConsequence {
            state = .needsAttention
        } else {
            state = .observed
        }
        let quietRate = interventionAudit.quietAfterPromptRate
        return AttentionDashboardMetric(
            kind: .switchingBoundary,
            state: state,
            title: "切换边界",
            value: "\(metrics.plannedWorkflowSwitches) / \(metrics.highRecoveryBurdenSwitches)",
            comparison: "计划边界 / 高恢复负担",
            evidence: [
                "最终切换 \(metrics.finalWorkflowSwitches) 次 · 原因覆盖 \(reasonCoverage.map(percent) ?? "—")",
                "高频段 \(interventionAudit.frequentSwitchEpisodes) · 实际确认 \(interventionAudit.promptsShown) · 确认后稳定 \(quietRate.map(percent) ?? "—")"
            ],
            bars: [
                bar(
                    "计划边界",
                    Double(metrics.plannedWorkflowSwitches),
                    "\(metrics.plannedWorkflowSwitches)"
                ),
                bar(
                    "高恢复负担",
                    Double(metrics.highRecoveryBurdenSwitches),
                    "\(metrics.highRecoveryBurdenSwitches)"
                )
            ]
        )
    }

    private static func contextRecovery(
        coaching: DailyCoachingAnalysis,
        summary: DailySummary,
        switchingLoad: SwitchingLoadAssessment
    ) -> AttentionDashboardMetric {
        guard coaching.quality.isReliable(.contextRecovery) else {
            return unavailable(
                kind: .contextRecovery,
                title: "恢复能力",
                reason: "需要有效工作记录和返回样本"
            )
        }
        let hasParkingSample = summary.taskParkingCount > 0
        let hasInterruptionSample =
            switchingLoad.metrics.averageInterruptionReturnSeconds != nil
        guard hasParkingSample || hasInterruptionSample else {
            return unavailable(
                kind: .contextRecovery,
                title: "恢复能力",
                reason: "今天还没有保存返回点或确认返回样本"
            )
        }

        let metrics = switchingLoad.metrics
        let recoveryPressure = metrics.highRecoveryBurdenSwitches >= 2
            && (
                metrics.shortDestinationSwitches >= 2
                    || metrics.returnedWithin30Minutes >= 2
                    || (metrics.returnPointResumeRate.map { $0 < 0.5 } == true)
            )
        let state: AttentionDashboardMetricState =
            recoveryPressure ? .needsAttention : .observed
        let value: String
        let comparison: String
        if let rate = metrics.returnPointResumeRate {
            value = percent(rate)
            comparison = "\(summary.resumedTaskCount)/\(summary.taskParkingCount) 个返回点已恢复"
        } else {
            value = metrics.averageInterruptionReturnSeconds.map(duration) ?? "—"
            comparison = "确认偏离后的平均返回耗时"
        }
        var evidence: [String] = []
        if let latency = summary.averageTaskResumeLatency {
            evidence.append("从保存返回点到继续：平均 \(duration(latency))")
        }
        if let latency = metrics.averageInterruptionReturnSeconds {
            evidence.append("确认偏离后返回当前工作流：平均 \(duration(latency))")
        }
        if evidence.isEmpty {
            evidence.append("只验证是否回来，不读取返回点文字")
        }
        return AttentionDashboardMetric(
            kind: .contextRecovery,
            state: state,
            title: "恢复能力",
            value: value,
            comparison: comparison,
            evidence: evidence,
            bars: hasParkingSample
                ? [
                    bar(
                        "已恢复",
                        Double(summary.resumedTaskCount),
                        "\(summary.resumedTaskCount)"
                    ),
                    bar(
                        "已保存",
                        Double(summary.taskParkingCount),
                        "\(summary.taskParkingCount)"
                    )
                ]
                : []
        )
    }

    private static func trainingFeedback(
        coaching: DailyCoachingAnalysis,
        switchingLoad: SwitchingLoadAssessment
    ) -> AttentionDashboardMetric {
        let total = coaching.metrics.trainingCount
        guard total > 0 else {
            return unavailable(
                kind: .trainingFeedback,
                title: "训练反馈",
                reason: "完成一轮训练并记录难度后才显示"
            )
        }
        let successful = coaching.metrics.successfulTrainingCount
        let successRate = Double(successful) / Double(total)
        let difficulty = switchingLoad.metrics.averageSubjectiveDifficulty
        let feedbackReady = (coaching.metrics.feedbackCompletionRatio ?? 0) >= 0.8
            && switchingLoad.metrics.subjectiveDifficultySamples >= 3
        let state: AttentionDashboardMetricState
        if total < minimumTrainingSamples || !feedbackReady {
            state = .calibrating
        } else if successRate <= 0.4 || (difficulty ?? 0) >= 4 {
            state = .needsAttention
        } else if successRate >= 0.8 && (difficulty ?? 5) <= 3 {
            state = .improving
        } else {
            state = .observed
        }
        return AttentionDashboardMetric(
            kind: .trainingFeedback,
            state: state,
            title: "训练反馈",
            value: percent(successRate),
            comparison: "\(successful)/\(total) 次达到目标",
            evidence: [
                difficulty.map {
                    "主观难度 \(decimal($0))/5 · \(switchingLoad.metrics.subjectiveDifficultySamples) 次反馈"
                } ?? "主观难度反馈不足",
                total < minimumTrainingSamples
                    ? "满 5 次后才用于调整训练计划"
                    : "完成结果与主观难度共同判断"
            ],
            bars: [
                bar("达到目标", Double(successful), "\(successful)"),
                bar("训练总数", Double(total), "\(total)")
            ]
        )
    }

    private struct TrendMeasurement {
        let value: Double?
        let secondaryValue: Double?
        let sampleCount: Int
        let isReliable: Bool
    }

    private static func trend(
        kind: AttentionDashboardMetricKind,
        days: [AttentionDashboardDay]
    ) -> AttentionMetricTrend {
        let points: [AttentionTrendPoint]
        if kind == .trainingFeedback {
            points = trainingTrendPoints(days: days)
        } else {
            points = days.map { day in
                let measurement = measurement(kind: kind, day: day)
                return AttentionTrendPoint(
                    date: day.date,
                    value: measurement.value,
                    secondaryValue: measurement.secondaryValue,
                    sampleCount: measurement.sampleCount,
                    isReliable: measurement.isReliable,
                    isPartial: day.isPartial
                )
            }
        }
        if kind == .trainingFeedback {
            return trainingTrend(days: days, points: points)
        }

        let reliable = points.filter {
            !$0.isPartial && $0.isReliable && $0.value != nil
        }
        guard reliable.count >= minimumTrendDays else {
            return AttentionMetricTrend(
                kind: kind,
                unit: unit(for: kind),
                lowerIsBetter: lowerIsBetter(kind),
                direction: .calibrating,
                points: points,
                baselineMedian: nil,
                recentMedian: reliable.compactMap(\.value).suffix(recentTrendDays)
                    .map { $0 }.median,
                typicalLowerBound: nil,
                typicalUpperBound: nil,
                reliableDayCount: reliable.count,
                comparison: "可靠 \(reliable.count)/\(minimumTrendDays) 天 · 继续校准"
            )
        }

        let recent = Array(reliable.suffix(recentTrendDays))
        let baseline = Array(
            reliable.dropLast(recent.count).suffix(
                trendWorkdayCount - recentTrendDays
            )
        )
        guard recent.count >= 2, baseline.count >= 2 else {
            return AttentionMetricTrend(
                kind: kind,
                unit: unit(for: kind),
                lowerIsBetter: lowerIsBetter(kind),
                direction: .calibrating,
                points: points,
                baselineMedian: nil,
                recentMedian: recent.compactMap(\.value).median,
                typicalLowerBound: nil,
                typicalUpperBound: nil,
                reliableDayCount: reliable.count,
                comparison: "需要至少 2 天个人典型区间和 2 天近期样本"
            )
        }

        let recentValues = recent.compactMap(\.value)
        let baselineValues = baseline.compactMap(\.value)
        let recentMedian = recentValues.median
        let baselineMedian = baselineValues.median
        let lower = percentile(baselineValues, fraction: 0.25)
        let upper = percentile(baselineValues, fraction: 0.75)
        var direction = trendDirection(
            kind: kind,
            recentMedian: recentMedian,
            baselineMedian: baselineMedian
        )

        if kind == .fragmentation,
           direction == .worsening {
            let collaborationRatio = recent
                .compactMap(\.secondaryValue)
                .median
            if (collaborationRatio ?? 0) >= 70 {
                direction = .stable
            }
        }

        let comparison: String
        if kind == .fragmentation,
           direction == .stable,
           (recent.compactMap(\.secondaryValue).median ?? 0) >= 70,
           let recentMedian {
            comparison = "近 3 日 \(format(recentMedian, kind: kind))，但以同工作流工具协作为主"
        } else if let recentMedian, let baselineMedian {
            comparison = "近 3 日 \(format(recentMedian, kind: kind)) · 此前典型 \(format(baselineMedian, kind: kind))"
        } else {
            comparison = "可靠样本不足"
        }

        return AttentionMetricTrend(
            kind: kind,
            unit: unit(for: kind),
            lowerIsBetter: lowerIsBetter(kind),
            direction: direction,
            points: points,
            baselineMedian: baselineMedian,
            recentMedian: recentMedian,
            typicalLowerBound: lower,
            typicalUpperBound: upper,
            reliableDayCount: reliable.count,
            comparison: comparison
        )
    }

    private static func measurement(
        kind: AttentionDashboardMetricKind,
        day: AttentionDashboardDay
    ) -> TrendMeasurement {
        let coaching = day.coaching
        let metrics = day.switchingLoad.metrics
        switch kind {
        case .sustainedProgress:
            let value = coaching.metrics.medianFocusMinutes
            return TrendMeasurement(
                value: value,
                secondaryValue: nil,
                sampleCount: Int(coaching.metrics.recordedMinutes.rounded()),
                isReliable: value != nil
                    && coaching.quality.isReliable(.fragmentation)
                    && coaching.quality.isReliable(.workflowSemantics)
            )
        case .fragmentation:
            let activeWindows = metrics.activeFiveMinuteWindows ?? 0
            let value = activeWindows > 0
                ? Double(metrics.highFragmentationWindows)
                    / Double(activeWindows) * 100
                : nil
            return TrendMeasurement(
                value: value,
                secondaryValue: metrics.withinWorkflowAppSwitchRatio.map {
                    $0 * 100
                },
                sampleCount: activeWindows,
                isReliable: value != nil
                    && activeWindows >= 4
                    && coaching.quality.isReliable(.fragmentation)
            )
        case .switchingBoundary:
            let total = metrics.finalWorkflowSwitches
            let value = total > 0
                ? Double(metrics.highRecoveryBurdenSwitches)
                    / Double(total) * 100
                : nil
            return TrendMeasurement(
                value: value,
                secondaryValue: metrics.explicitReasonCoverage.map { $0 * 100 },
                sampleCount: total,
                isReliable: value != nil
                    && (metrics.explicitReasonCoverage ?? 0)
                        >= minimumReasonCoverage
                    && coaching.quality.isReliable(.workflowSemantics)
            )
        case .contextRecovery:
            return TrendMeasurement(
                value: metrics.returnPointResumeRate.map { $0 * 100 },
                secondaryValue: metrics.averageInterruptionReturnSeconds,
                sampleCount: day.summary.taskParkingCount,
                isReliable: day.summary.taskParkingCount > 0
                    && metrics.returnPointResumeRate != nil
                    && coaching.quality.isReliable(.contextRecovery)
            )
        case .trainingFeedback:
            return TrendMeasurement(
                value: nil,
                secondaryValue: nil,
                sampleCount: 0,
                isReliable: false
            )
        }
    }

    private static func trainingTrend(
        days: [AttentionDashboardDay],
        points: [AttentionTrendPoint]
    ) -> AttentionMetricTrend {
        let completed = days
            .filter { !$0.isPartial }
            .flatMap(\.focusSessions)
            .filter { $0.endedAt != nil && $0.outcome != .pending }
            .sorted { $0.startedAt < $1.startedAt }
        let recent = Array(completed.suffix(minimumTrainingSamples))
        let recentDifficulty = recent.compactMap {
            $0.difficulty.map(Double.init)
        }
        let recentFeedbackCoverage = recent.isEmpty
            ? 0
            : Double(recentDifficulty.count) / Double(recent.count)
        guard recent.count >= minimumTrainingSamples,
              recentFeedbackCoverage >= 0.8 else {
            return AttentionMetricTrend(
                kind: .trainingFeedback,
                unit: "%",
                lowerIsBetter: false,
                direction: .calibrating,
                points: points,
                baselineMedian: nil,
                recentMedian: recent.isEmpty
                    ? nil
                    : Double(recent.filter(\.isSuccessful).count)
                        / Double(recent.count) * 100,
                typicalLowerBound: nil,
                typicalUpperBound: nil,
                reliableDayCount: recent.count,
                comparison: "已完成 \(recent.count)/\(minimumTrainingSamples) 次 · 难度反馈需覆盖至少 4 次"
            )
        }

        let recentSuccessRate = Double(recent.filter(\.isSuccessful).count)
            / Double(recent.count) * 100
        let recentDifficultyMedian = recentDifficulty.median
        let previous = Array(
            completed.dropLast(minimumTrainingSamples)
                .suffix(minimumTrainingSamples)
        )
        let previousDifficulty = previous.compactMap {
            $0.difficulty.map(Double.init)
        }
        let previousIsReliable = previous.count >= minimumTrainingSamples
            && previousDifficulty.count >= 4
        let previousSuccessRate = previousIsReliable
            ? Double(previous.filter(\.isSuccessful).count)
                / Double(previous.count) * 100
            : nil

        let direction: AttentionTrendDirection
        if recentSuccessRate <= 40 || (recentDifficultyMedian ?? 0) >= 4 {
            direction = .worsening
        } else if let previousSuccessRate {
            direction = trendDirection(
                kind: .trainingFeedback,
                recentMedian: recentSuccessRate,
                baselineMedian: previousSuccessRate
            )
        } else {
            direction = .stable
        }
        let comparison: String
        if let previousSuccessRate {
            comparison = "最近 5 次 \(format(recentSuccessRate, kind: .trainingFeedback)) · 前 5 次 \(format(previousSuccessRate, kind: .trainingFeedback))"
        } else {
            let difficulty = recentDifficultyMedian.map {
                " · 难度 \(decimal($0))/5"
            } ?? ""
            comparison = "最近 5 次 \(format(recentSuccessRate, kind: .trainingFeedback))\(difficulty)"
        }
        return AttentionMetricTrend(
            kind: .trainingFeedback,
            unit: "%",
            lowerIsBetter: false,
            direction: direction,
            points: points,
            baselineMedian: previousSuccessRate,
            recentMedian: recentSuccessRate,
            typicalLowerBound: previousSuccessRate,
            typicalUpperBound: previousSuccessRate,
            reliableDayCount: recent.count,
            comparison: comparison
        )
    }

    private static func trainingTrendPoints(
        days: [AttentionDashboardDay]
    ) -> [AttentionTrendPoint] {
        var completed: [FocusSessionRecord] = []
        return days.map { day in
            completed.append(contentsOf: day.focusSessions.filter {
                $0.endedAt != nil && $0.outcome != .pending
            })
            completed.sort { $0.startedAt < $1.startedAt }
            let recent = Array(completed.suffix(minimumTrainingSamples))
            let feedback = recent.compactMap { session -> Double? in
                session.difficulty.map(Double.init)
            }
            let successRate = recent.isEmpty
                ? nil
                : Double(recent.filter(\.isSuccessful).count)
                    / Double(recent.count) * 100
            let feedbackCoverage = recent.isEmpty
                ? 0
                : Double(feedback.count) / Double(recent.count)
            return AttentionTrendPoint(
                date: day.date,
                value: successRate,
                secondaryValue: feedback.median,
                sampleCount: recent.count,
                isReliable: recent.count >= minimumTrainingSamples
                    && feedbackCoverage >= 0.8,
                isPartial: day.isPartial
            )
        }
    }

    private static func trendDirection(
        kind: AttentionDashboardMetricKind,
        recentMedian: Double?,
        baselineMedian: Double?
    ) -> AttentionTrendDirection {
        guard let recentMedian, let baselineMedian else {
            return .calibrating
        }
        let delta = recentMedian - baselineMedian
        let threshold: Double
        switch kind {
        case .sustainedProgress:
            threshold = max(2, baselineMedian * 0.15)
        case .fragmentation:
            threshold = max(10, baselineMedian * 0.25)
        case .switchingBoundary:
            threshold = max(15, baselineMedian * 0.25)
        case .contextRecovery, .trainingFeedback:
            threshold = 20
        }
        guard abs(delta) >= threshold else { return .stable }
        let numericallyImproving = lowerIsBetter(kind)
            ? delta < 0
            : delta > 0
        return numericallyImproving ? .improving : .worsening
    }

    private static func metricWithTrend(
        _ metric: AttentionDashboardMetric,
        trend: AttentionMetricTrend
    ) -> AttentionDashboardMetric {
        let state: AttentionDashboardMetricState
        switch trend.direction {
        case .calibrating:
            state = trend.reliableDayCount == 0 && metric.state == .unavailable
                ? .unavailable
                : .calibrating
        case .stable:
            state = .observed
        case .improving:
            state = .improving
        case .worsening:
            state = .needsAttention
        }
        let evidence: [String]
        if metric.kind == .trainingFeedback {
            evidence = [
                "完成结果按最近连续 5 次计算，不要求同一天完成",
                "主观难度反馈覆盖至少 4/5 次后才用于调整"
            ]
        } else {
            evidence = metric.evidence
        }
        return AttentionDashboardMetric(
            kind: metric.kind,
            state: state,
            title: title(for: metric.kind),
            value: trend.recentMedian.map {
                format($0, kind: metric.kind)
            } ?? metric.value,
            comparison: trend.comparison,
            evidence: evidence,
            bars: metric.bars,
            trend: trend
        )
    }

    private static func primaryFinding(
        metrics: [AttentionDashboardMetric]
    ) -> AttentionDashboardFinding {
        let byKind = Dictionary(uniqueKeysWithValues: metrics.map {
            ($0.kind, $0)
        })
        let worsening = Set(metrics.compactMap {
            $0.trend?.direction == .worsening ? $0.kind : nil
        })
        let selectedKind: AttentionDashboardMetricKind?
        if worsening.contains(.switchingBoundary),
           worsening.contains(.contextRecovery) {
            selectedKind = .switchingBoundary
        } else if worsening.contains(.fragmentation),
                  worsening.contains(.sustainedProgress) {
            selectedKind = .fragmentation
        } else if worsening.contains(.contextRecovery) {
            selectedKind = .contextRecovery
        } else if worsening.contains(.trainingFeedback) {
            selectedKind = .trainingFeedback
        } else if worsening.contains(.sustainedProgress) {
            selectedKind = .sustainedProgress
        } else if worsening.contains(.switchingBoundary) {
            selectedKind = .switchingBoundary
        } else if worsening.contains(.fragmentation) {
            selectedKind = nil
        } else {
            selectedKind = nil
        }

        if let selectedKind, let metric = byKind[selectedKind] {
            let detail: String
            switch selectedKind {
            case .sustainedProgress:
                detail = "连续工作时长已持续低于个人典型区间；这说明工作被更早打断，不等于产出一定下降。"
            case .fragmentation:
                detail = worsening.contains(.sustainedProgress)
                    ? "高碎片工作段持续增加，并同时压缩连续工作时长。"
                    : "高碎片工作段持续增加，但恢复后果仍需继续验证。"
            case .switchingBoundary:
                detail = "高恢复负担的工作流切换持续增加，并伴随恢复能力下降。"
            case .contextRecovery:
                detail = "保存返回点后的恢复闭环率持续下降；问题在于切走后难以顺利回来。"
            case .trainingFeedback:
                detail = "最近滚动 5 次训练的完成反馈持续下降，当前训练负荷需要重新校准。"
            }
            var evidence = [metric.trend?.comparison ?? metric.comparison]
            if selectedKind == .fragmentation,
               let continuity = byKind[.sustainedProgress]?.trend?.comparison {
                evidence.append("连续工作：\(continuity)")
            } else if selectedKind == .switchingBoundary,
                      let recovery = byKind[.contextRecovery]?.trend?.comparison {
                evidence.append("恢复闭环：\(recovery)")
            } else if let first = metric.evidence.first {
                evidence.append(first)
            }
            return AttentionDashboardFinding(
                state: .needsAttention,
                kind: selectedKind,
                title: findingTitle(for: selectedKind),
                detail: detail,
                evidence: evidence
            )
        }

        let improving = metrics.filter {
            $0.trend?.direction == .improving
        }
        if let metric = improving.first {
            return AttentionDashboardFinding(
                state: .improving,
                kind: metric.kind,
                title: "\(metric.title)正在形成持续改善",
                detail: "最近 3 个可靠工作日优于此前个人典型区间；先保持做法，不立即增加训练负荷。",
                evidence: [metric.trend?.comparison ?? metric.comparison]
            )
        }

        if worsening.contains(.fragmentation),
           let fragmentation = byKind[.fragmentation] {
            return AttentionDashboardFinding(
                state: .stable,
                kind: nil,
                title: "碎片段增加，但还没有出现恢复后果",
                detail: "当前只看到高切换区间增加，连续工作与恢复闭环没有同步恶化；暂不把它升级为注意力问题。",
                evidence: [
                    fragmentation.trend?.comparison
                        ?? fragmentation.comparison,
                    "继续观察连续工作或恢复闭环是否同步变化"
                ]
            )
        }

        let reliable = metrics.filter {
            guard let trend = $0.trend else { return false }
            return trend.direction != .calibrating
        }
        if !reliable.isEmpty {
            return AttentionDashboardFinding(
                state: .stable,
                kind: nil,
                title: "\(reliable.count) 个可靠趋势暂未持续恶化",
                detail: "其余 \(max(0, metrics.count - reliable.count)) 个维度仍在校准；这不代表注意力“满分”，只表示当前没有连续证据支持升级干预。",
                evidence: ["\(reliable.count)/\(metrics.count) 个维度已形成可比较趋势"]
            )
        }

        let bestSample = metrics.compactMap(\.trend).map(\.reliableDayCount)
            .max() ?? 0
        return AttentionDashboardFinding(
            state: .calibrating,
            kind: nil,
            title: "趋势样本仍在建立",
            detail: "至少需要 5 个可靠工作日；当前只展示事实，不判断改善或恶化。",
            evidence: ["当前最多 \(bestSample)/\(minimumTrendDays) 个可靠工作日"]
        )
    }

    private static func trendRecommendation(
        finding: AttentionDashboardFinding,
        metrics: [AttentionDashboardMetric],
        currentPlan: TrainingPlanRecord
    ) -> DailyCoachRecommendation {
        guard finding.state == .needsAttention, let kind = finding.kind else {
            if finding.state == .calibrating {
                return DailyCoachRecommendation(
                    kind: .collectData,
                    title: "先补足可靠趋势，不调整训练",
                    rationale: finding.detail,
                    evidence: finding.evidence,
                    confidence: .low,
                    action: .none,
                    method: DailyTrainingMethod(
                        title: "按正常方式继续工作",
                        steps: [
                            "保持现有工作流命名和切换方式",
                            "训练结束后继续记录结果与难度"
                        ],
                        successMeasure: "至少一个维度形成 5 个可靠工作日，或训练反馈累计满 5 次"
                    )
                )
            }
            let confidence = confidence(
                for: metrics.compactMap(\.trend).map(\.reliableDayCount).max() ?? 0
            )
            return DailyCoachRecommendation(
                kind: .maintainRound,
                title: finding.state == .improving
                    ? "保持当前方法，再观察 3 个有效工作日"
                    : "保持当前方法，不增加训练负荷",
                rationale: finding.detail,
                evidence: finding.evidence,
                confidence: confidence,
                action: .none,
                method: DailyTrainingMethod(
                    title: "保持变量不变",
                    steps: [
                        "沿用当前训练时长和允许工具",
                        "每轮只写一个可交付结果",
                        "完成后继续记录结果和主观难度"
                    ],
                    successMeasure: "3 个有效工作日后趋势仍稳定或继续改善"
                )
            )
        }

        let reliableDays = metrics.first {
            $0.kind == kind
        }?.trend?.reliableDayCount ?? 0
        let confidence = confidence(for: reliableDays)
        switch kind {
        case .fragmentation:
            return DailyCoachRecommendation(
                kind: .startFocusRound,
                title: "把下一段高碎片工作改成单一产出块",
                rationale: finding.detail,
                evidence: finding.evidence,
                confidence: confidence,
                action: .startFocus(minutes: currentPlan.focusMinutes),
                method: DailyTrainingMethod(
                    title: "单一产出实验",
                    steps: [
                        "开始前写下这一段唯一要交付的结果",
                        "同工作流内工具可以切换；跨工作流前先保存返回点",
                        "结束后记录完成情况和难度"
                    ],
                    successMeasure: "未来 3 个有效工作日，高碎片窗口占比下降至少 10 个百分点，连续工作不再下降"
                )
            )
        case .switchingBoundary, .contextRecovery:
            return DailyCoachRecommendation(
                kind: .agentParkingDrill,
                title: "未来 3 天只练一个动作：切走前保存返回点",
                rationale: finding.detail,
                evidence: finding.evidence,
                confidence: confidence,
                action: .parkWorkflow,
                method: DailyTrainingMethod(
                    title: "返回点恢复实验",
                    steps: [
                        "等待 Agent 或被迫中断时写下回来后的第一步",
                        "保存返回点后再切换工作流",
                        "回来后先执行第一步，再决定是否继续"
                    ],
                    successMeasure: "未来 3 个有效工作日，返回点恢复率提高至少 20 个百分点"
                )
            )
        case .trainingFeedback:
            let minutes = max(10, currentPlan.focusMinutes - 5)
            return DailyCoachRecommendation(
                kind: .recoveryRound,
                title: "接下来 5 次训练临时缩短到 \(minutes) 分钟",
                rationale: finding.detail,
                evidence: finding.evidence,
                confidence: confidence,
                action: .startFocus(minutes: minutes),
                method: DailyTrainingMethod(
                    title: "训练负荷校准",
                    steps: [
                        "保持任务类型和允许工具不变",
                        "仅把训练时长缩短 5 分钟",
                        "连续完成 5 次并记录难度"
                    ],
                    successMeasure: "最近 5 次成功率达到 80%，且平均难度不高于 3/5"
                )
            )
        case .sustainedProgress:
            return DailyCoachRecommendation(
                kind: .startFocusRound,
                title: "连续 3 天保护一轮单一产出时间",
                rationale: finding.detail,
                evidence: finding.evidence,
                confidence: confidence,
                action: .startFocus(minutes: currentPlan.focusMinutes),
                method: DailyTrainingMethod(
                    title: "连续工作恢复实验",
                    steps: [
                        "选择当天最重要的一个可交付结果",
                        "开始一轮当前训练时长的专注",
                        "切走前保存返回点，结束后记录难度"
                    ],
                    successMeasure: "未来 3 个有效工作日，中位连续工作时长回到个人典型区间"
                )
            )
        }
    }

    private static func confidence(for reliableDays: Int) -> DailyCoachConfidence {
        if reliableDays >= 8 { return .high }
        if reliableDays >= minimumTrendDays { return .medium }
        return .low
    }

    private static func findingTitle(
        for kind: AttentionDashboardMetricKind
    ) -> String {
        switch kind {
        case .sustainedProgress: return "连续工作时长持续下降"
        case .fragmentation: return "高碎片工作段正在持续增加"
        case .switchingBoundary: return "高恢复负担切换正在持续增加"
        case .contextRecovery: return "切走后的恢复闭环正在变弱"
        case .trainingFeedback: return "当前训练负荷的反馈正在变差"
        }
    }

    private static func title(for kind: AttentionDashboardMetricKind) -> String {
        switch kind {
        case .sustainedProgress: return "连续工作"
        case .fragmentation: return "碎片化"
        case .switchingBoundary: return "切换边界"
        case .contextRecovery: return "恢复闭环"
        case .trainingFeedback: return "训练反应"
        }
    }

    private static func unit(for kind: AttentionDashboardMetricKind) -> String {
        kind == .sustainedProgress ? "分钟" : "%"
    }

    private static func lowerIsBetter(
        _ kind: AttentionDashboardMetricKind
    ) -> Bool {
        [.fragmentation, .switchingBoundary].contains(kind)
    }

    private static func format(
        _ value: Double,
        kind: AttentionDashboardMetricKind
    ) -> String {
        if kind == .sustainedProgress {
            return minutes(value)
        }
        return "\(Int(value.rounded()))%"
    }

    private static func percentile(
        _ values: [Double],
        fraction: Double
    ) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = Int(
            (Double(sorted.count - 1) * min(1, max(0, fraction))).rounded()
        )
        return sorted[index]
    }

    private static func unavailable(
        kind: AttentionDashboardMetricKind,
        title: String,
        reason: String
    ) -> AttentionDashboardMetric {
        AttentionDashboardMetric(
            kind: kind,
            state: .unavailable,
            title: title,
            value: "待收集",
            comparison: reason,
            evidence: ["该维度独立降级，不影响其他可靠维度"]
        )
    }

    private static func bar(
        _ label: String,
        _ value: Double,
        _ formattedValue: String
    ) -> AttentionDashboardComparisonBar {
        AttentionDashboardComparisonBar(
            label: label,
            value: value,
            formattedValue: formattedValue
        )
    }

    private static func minutes(_ value: Double) -> String {
        value < 10
            ? "\(decimal(value)) 分"
            : "\(Int(value.rounded())) 分"
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func relativeMinutes(_ delta: Double) -> String {
        if abs(delta) < 0.05 {
            return "与个人基线持平"
        }
        return "较个人基线 \(delta > 0 ? "+" : "")\(decimal(delta)) 分"
    }

    private static func relativePercent(
        _ delta: Double?,
        noun: String
    ) -> String {
        guard let delta else { return "正在建立个人基线" }
        if abs(delta) < 0.5 {
            return "\(noun)持平"
        }
        return "\(noun) \(delta > 0 ? "+" : "")\(Int(delta.rounded()))%"
    }

    private static func fragmentationComparison(
        delta: Double?,
        highWindowShare: Double,
        concentratedFragmentation: Bool,
        sameWorkflowQualified: Bool
    ) -> String {
        if sameWorkflowQualified, (delta ?? 0) >= 25 {
            return "切换上升，但以同工作流工具协作为主"
        }
        if concentratedFragmentation {
            return "\(percent(highWindowShare)) 的有效窗口进入高碎片"
        }
        return relativePercent(delta, noun: "较个人基线")
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 60 {
            return "\(total / 60)分\(total % 60)秒"
        }
        return "\(total)秒"
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private extension Array where Element == Double {
    var median: Double? {
        guard !isEmpty else { return nil }
        let ordered = sorted()
        let middle = ordered.count / 2
        if ordered.count.isMultiple(of: 2) {
            return (ordered[middle - 1] + ordered[middle]) / 2
        }
        return ordered[middle]
    }
}
