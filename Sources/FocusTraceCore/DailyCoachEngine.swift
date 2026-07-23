import Foundation

public enum DailyCoachConfidence: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

public enum DailyCoachKind: String, Codable, Equatable, Sendable {
    case collectData
    case repairAttribution
    case verifySpaceTracking
    case startFocusRound
    case recoveryRound
    case agentParkingDrill
    case maintainRound
}

public enum DailyCoachAction: Codable, Equatable, Sendable {
    case none
    case bindWorkflow
    case startFocus(minutes: Int)
    case parkWorkflow
    case reviewTimeline
}

public struct DailyTrainingMethod: Codable, Equatable, Sendable {
    public let title: String
    public let steps: [String]
    public let successMeasure: String

    public init(title: String, steps: [String], successMeasure: String) {
        self.title = title
        self.steps = steps
        self.successMeasure = successMeasure
    }
}

public struct DailyCoachRecommendation: Codable, Equatable, Sendable {
    public let kind: DailyCoachKind
    public let title: String
    public let rationale: String
    public let evidence: [String]
    public let confidence: DailyCoachConfidence
    public let action: DailyCoachAction
    public let method: DailyTrainingMethod

    public init(
        kind: DailyCoachKind,
        title: String,
        rationale: String,
        evidence: [String],
        confidence: DailyCoachConfidence,
        action: DailyCoachAction,
        method: DailyTrainingMethod
    ) {
        self.kind = kind
        self.title = title
        self.rationale = rationale
        self.evidence = evidence
        self.confidence = confidence
        self.action = action
        self.method = method
    }
}

public struct DailyNormalizedMetrics: Codable, Equatable, Sendable {
    public let recordedMinutes: Double
    public let attributedMinutes: Double
    public let attributedRatio: Double
    public let appSwitchesPerHour: Double
    public let workflowSwitchesPerHour: Double
    public let medianFocusMinutes: Double?
    public let trainingCount: Int
    public let successfulTrainingCount: Int
    public let feedbackCompletionRatio: Double?
    public let parkingCount: Int

    public init(
        recordedMinutes: Double,
        attributedMinutes: Double,
        attributedRatio: Double,
        appSwitchesPerHour: Double,
        workflowSwitchesPerHour: Double,
        medianFocusMinutes: Double?,
        trainingCount: Int,
        successfulTrainingCount: Int,
        feedbackCompletionRatio: Double?,
        parkingCount: Int
    ) {
        self.recordedMinutes = recordedMinutes
        self.attributedMinutes = attributedMinutes
        self.attributedRatio = attributedRatio
        self.appSwitchesPerHour = appSwitchesPerHour
        self.workflowSwitchesPerHour = workflowSwitchesPerHour
        self.medianFocusMinutes = medianFocusMinutes
        self.trainingCount = trainingCount
        self.successfulTrainingCount = successfulTrainingCount
        self.feedbackCompletionRatio = feedbackCompletionRatio
        self.parkingCount = parkingCount
    }
}

public struct DailyDataQuality: Codable, Equatable, Sendable {
    public let isReliableForBehavior: Bool
    public let warnings: [String]

    public init(isReliableForBehavior: Bool, warnings: [String]) {
        self.isReliableForBehavior = isReliableForBehavior
        self.warnings = warnings
    }
}

public struct DailyTrendComparison: Codable, Equatable, Sendable {
    public let baselineDays: Int
    public let appSwitchRateDeltaPercent: Double?
    public let workflowSwitchRateDeltaPercent: Double?
    public let attributedRatioDeltaPoints: Double?
    public let medianFocusDeltaMinutes: Double?

    public init(
        baselineDays: Int,
        appSwitchRateDeltaPercent: Double?,
        workflowSwitchRateDeltaPercent: Double?,
        attributedRatioDeltaPoints: Double?,
        medianFocusDeltaMinutes: Double?
    ) {
        self.baselineDays = baselineDays
        self.appSwitchRateDeltaPercent = appSwitchRateDeltaPercent
        self.workflowSwitchRateDeltaPercent = workflowSwitchRateDeltaPercent
        self.attributedRatioDeltaPoints = attributedRatioDeltaPoints
        self.medianFocusDeltaMinutes = medianFocusDeltaMinutes
    }
}

public enum DailyCoachEvaluationStatus: String, Codable, Equatable, Sendable {
    case improved
    case needsAdjustment
    case notRun
    case insufficientData
}

public struct DailyCoachEvaluation: Codable, Equatable, Sendable {
    public let status: DailyCoachEvaluationStatus
    public let title: String
    public let evidence: String

    public init(status: DailyCoachEvaluationStatus, title: String, evidence: String) {
        self.status = status
        self.title = title
        self.evidence = evidence
    }
}

public struct DailyCoachingAnalysis: Codable, Equatable, Sendable {
    public let metrics: DailyNormalizedMetrics
    public let quality: DailyDataQuality
    public let trend: DailyTrendComparison
    public let recommendation: DailyCoachRecommendation
    public let previousRecommendationEvaluation: DailyCoachEvaluation?

    public init(
        metrics: DailyNormalizedMetrics,
        quality: DailyDataQuality,
        trend: DailyTrendComparison,
        recommendation: DailyCoachRecommendation,
        previousRecommendationEvaluation: DailyCoachEvaluation?
    ) {
        self.metrics = metrics
        self.quality = quality
        self.trend = trend
        self.recommendation = recommendation
        self.previousRecommendationEvaluation = previousRecommendationEvaluation
    }
}

public enum DailyCoachEngine {
    private static let minimumRecordedSeconds: TimeInterval = 30 * 60
    private static let minimumAttributedRatio = 0.70

    public static func analyze(
        snapshot: FocusTraceLocalSnapshot,
        reportDate: Date,
        generatedAt: Date = Date(),
        calendar: Calendar = .current,
        previousIssuedRecommendation: DailyCoachRecommendation? = nil,
        previousIssuedMetrics: DailyNormalizedMetrics? = nil
    ) -> DailyCoachingAnalysis {
        let current = slice(
            snapshot: snapshot,
            date: reportDate,
            now: generatedAt,
            calendar: calendar
        )
        let baseline = baselineSlices(
            snapshot: snapshot,
            before: calendar.startOfDay(for: reportDate),
            now: generatedAt,
            calendar: calendar
        )
        let currentQuality = quality(for: current, baseline: baseline)
        let currentTrend = trend(for: current, baseline: baseline)
        let currentRecommendation = recommendation(
            snapshot: snapshot,
            slice: current,
            baseline: baseline,
            quality: currentQuality,
            trend: currentTrend
        )

        let previousEvaluation: DailyCoachEvaluation?
        if let previousIssuedRecommendation {
            previousEvaluation = evaluate(
                previousIssuedRecommendation,
                previousMetrics: previousIssuedMetrics,
                current: current
            )
        } else if let previousDate = previousWorkday(
            in: snapshot.activities,
            before: calendar.startOfDay(for: reportDate),
            calendar: calendar
        ) {
            let previous = slice(
                snapshot: snapshot,
                date: previousDate,
                now: generatedAt,
                calendar: calendar
            )
            let previousBaseline = baselineSlices(
                snapshot: snapshot,
                before: calendar.startOfDay(for: previousDate),
                now: generatedAt,
                calendar: calendar
            )
            let previousQuality = quality(for: previous, baseline: previousBaseline)
            let previousTrend = trend(for: previous, baseline: previousBaseline)
            let previousRecommendation = recommendation(
                snapshot: snapshot,
                slice: previous,
                baseline: previousBaseline,
                quality: previousQuality,
                trend: previousTrend
            )
            previousEvaluation = evaluate(
                previousRecommendation,
                previousMetrics: previous.metrics,
                current: current
            )
        } else {
            previousEvaluation = nil
        }

        return DailyCoachingAnalysis(
            metrics: current.metrics,
            quality: currentQuality,
            trend: currentTrend,
            recommendation: currentRecommendation,
            previousRecommendationEvaluation: previousEvaluation
        )
    }

    private struct DaySlice {
        let date: Date
        let end: Date
        let summary: DailySummary
        let metrics: DailyNormalizedMetrics
        let sessions: [FocusSessionRecord]
        let interruptions: [InterruptionRecord]
        let taskParkings: [TaskParkingRecord]
    }

    private static func slice(
        snapshot: FocusTraceLocalSnapshot,
        date: Date,
        now: Date,
        calendar: Calendar
    ) -> DaySlice {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let effectiveNow = min(max(now, start), end)
        let activities = snapshot.activities.compactMap {
            clipped($0, start: start, end: end, now: effectiveNow)
        }
        let intervals = snapshot.taskIntervals.compactMap {
            clipped($0, start: start, end: end, now: effectiveNow)
        }
        let interruptions = snapshot.interruptions.filter {
            $0.detectedAt >= start && $0.detectedAt < end
        }
        let sessions = snapshot.focusSessions.filter {
            $0.startedAt >= start && $0.startedAt < end && $0.endedAt != nil
        }
        let parkings = snapshot.taskParkings.filter {
            $0.parkedAt >= start && $0.parkedAt < end
        }
        let summary = MetricsEngine.dailySummary(
            activities: activities,
            taskIntervals: intervals,
            interruptions: interruptions,
            taskParkings: parkings,
            now: effectiveNow
        )
        let visible = activities.filter {
            ![.systemInactive, .trackerControl].contains($0.classification)
        }
        let recordedSeconds = visible.reduce(0) { $0 + $1.duration(relativeTo: effectiveNow) }
        let attributedSeconds = visible.filter { $0.taskID != nil }
            .reduce(0) { $0 + $1.duration(relativeTo: effectiveNow) }
        let hours = recordedSeconds / 3600
        let feedbackCount = sessions.filter {
            $0.outcome != .pending && $0.difficulty != nil
        }.count
        return DaySlice(
            date: start,
            end: end,
            summary: summary,
            metrics: DailyNormalizedMetrics(
                recordedMinutes: recordedSeconds / 60,
                attributedMinutes: attributedSeconds / 60,
                attributedRatio: recordedSeconds > 0 ? attributedSeconds / recordedSeconds : 0,
                appSwitchesPerHour: hours > 0 ? Double(summary.appSwitchCount) / hours : 0,
                workflowSwitchesPerHour: hours > 0 ? Double(summary.workflowSwitchCount) / hours : 0,
                medianFocusMinutes: summary.medianFocusStreak.map { $0 / 60 },
                trainingCount: sessions.count,
                successfulTrainingCount: sessions.filter(\.isSuccessful).count,
                feedbackCompletionRatio: sessions.isEmpty ? nil : Double(feedbackCount) / Double(sessions.count),
                parkingCount: parkings.count
            ),
            sessions: sessions,
            interruptions: interruptions,
            taskParkings: parkings
        )
    }

    private static func baselineSlices(
        snapshot: FocusTraceLocalSnapshot,
        before date: Date,
        now: Date,
        calendar: Calendar
    ) -> [DaySlice] {
        let dates = Set(snapshot.activities.compactMap { activity -> Date? in
            let day = calendar.startOfDay(for: activity.startedAt)
            return day < date ? day : nil
        })
        return dates.sorted(by: >)
            .prefix(7)
            .map { slice(snapshot: snapshot, date: $0, now: now, calendar: calendar) }
            .filter {
                $0.metrics.recordedMinutes >= minimumRecordedSeconds / 60
                    && $0.metrics.attributedRatio >= 0.50
            }
    }

    private static func quality(
        for slice: DaySlice,
        baseline: [DaySlice]
    ) -> DailyDataQuality {
        var warnings: [String] = []
        let metrics = slice.metrics
        if metrics.recordedMinutes < minimumRecordedSeconds / 60 {
            warnings.append("有效记录不足 30 分钟，今天的行为结论可信度较低。")
        }
        if metrics.recordedMinutes > 0, metrics.attributedRatio < minimumAttributedRatio {
            warnings.append("只有 \(percent(metrics.attributedRatio)) 的记录归属于工作流，先补齐桌面绑定。")
        }
        let baselineWorkflowRate = median(baseline.map { $0.metrics.workflowSwitchesPerHour })
        let denseSpaceSignals = slice.summary.workflowSwitchCount >= 10
            && (
                metrics.workflowSwitchesPerHour >= 30
                    || metrics.workflowSwitchesPerHour > max(18, (baselineWorkflowRate ?? 0) * 1.5)
            )
        if denseSpaceSignals {
            warnings.append("桌面工作流切换信号异常密集，先排除 Space 识别噪声，不据此判断注意力。")
        }
        if let feedback = metrics.feedbackCompletionRatio, feedback < 1 {
            warnings.append("部分训练缺少完成结果或难度反馈，会削弱后续个性化分析。")
        }
        let reliable = metrics.recordedMinutes >= minimumRecordedSeconds / 60
            && metrics.attributedRatio >= minimumAttributedRatio
            && !denseSpaceSignals
        return DailyDataQuality(isReliableForBehavior: reliable, warnings: warnings)
    }

    private static func trend(
        for slice: DaySlice,
        baseline: [DaySlice]
    ) -> DailyTrendComparison {
        guard baseline.count >= 2 else {
            return DailyTrendComparison(
                baselineDays: baseline.count,
                appSwitchRateDeltaPercent: nil,
                workflowSwitchRateDeltaPercent: nil,
                attributedRatioDeltaPoints: nil,
                medianFocusDeltaMinutes: nil
            )
        }
        let appBaseline = median(baseline.map { $0.metrics.appSwitchesPerHour })
        let workflowBaseline = median(baseline.map { $0.metrics.workflowSwitchesPerHour })
        let attributionBaseline = median(baseline.map { $0.metrics.attributedRatio })
        let focusBaseline = median(baseline.compactMap { $0.metrics.medianFocusMinutes })
        return DailyTrendComparison(
            baselineDays: baseline.count,
            appSwitchRateDeltaPercent: relativeDelta(slice.metrics.appSwitchesPerHour, appBaseline),
            workflowSwitchRateDeltaPercent: relativeDelta(slice.metrics.workflowSwitchesPerHour, workflowBaseline),
            attributedRatioDeltaPoints: attributionBaseline.map {
                (slice.metrics.attributedRatio - $0) * 100
            },
            medianFocusDeltaMinutes: zipOptional(slice.metrics.medianFocusMinutes, focusBaseline).map {
                $0.0 - $0.1
            }
        )
    }

    private static func recommendation(
        snapshot: FocusTraceLocalSnapshot,
        slice: DaySlice,
        baseline: [DaySlice],
        quality: DailyDataQuality,
        trend: DailyTrendComparison
    ) -> DailyCoachRecommendation {
        let confidence = confidence(quality: quality, baselineDays: baseline.count)
        let availableSessions = snapshot.focusSessions.filter {
            $0.endedAt != nil && $0.startedAt < slice.end
        }
        let effectivePlan = snapshot.trainingPlans
            .filter { $0.effectiveAt < slice.end }
            .max(by: { $0.version < $1.version })
            ?? snapshot.currentPlan
        let minutes = min(50, max(10, effectivePlan.focusMinutes))
        if slice.metrics.recordedMinutes < minimumRecordedSeconds / 60 {
            return DailyCoachRecommendation(
                kind: .collectData,
                title: "先形成 30 分钟可信样本",
                rationale: "记录时间太短时，任何注意力结论都容易受偶然事件影响。",
                evidence: ["今日有效记录 \(rounded(slice.metrics.recordedMinutes)) 分钟", "近 7 日可比样本 \(baseline.count) 天"],
                confidence: .low,
                action: .none,
                method: DailyTrainingMethod(
                    title: "低负担观察",
                    steps: ["绑定当前桌面的工作流", "照常工作至少 30 分钟", "期间不刻意减少工具切换"],
                    successMeasure: "有效记录达到 30 分钟且工作流归因达到 70%"
                )
            )
        }
        if slice.metrics.attributedRatio < minimumAttributedRatio {
            return DailyCoachRecommendation(
                kind: .repairAttribution,
                title: "先修复工作流归因，再训练注意力",
                rationale: "大量时间没有工作流标签，当前切换数据无法区分工作需要与走神。",
                evidence: ["工作流归因率 \(percent(slice.metrics.attributedRatio))", "可靠分析门槛为 70%"],
                confidence: .high,
                action: .bindWorkflow,
                method: DailyTrainingMethod(
                    title: "桌面绑定校准",
                    steps: ["把当前桌面绑定到正在推进的工作流", "在该桌面连续工作 30 分钟", "需要换主线时再切到另一个已绑定桌面"],
                    successMeasure: "下一份报告的工作流归因率达到 70%"
                )
            )
        }
        if quality.warnings.contains(where: { $0.contains("Space 识别噪声") }) {
            return DailyCoachRecommendation(
                kind: .verifySpaceTracking,
                title: "先验证两次真实桌面切换",
                rationale: "当前 Space 信号密度异常，先确认记录器是否把刷新误算成工作流切换。",
                evidence: ["桌面工作流切换 \(rounded(slice.metrics.workflowSwitchesPerHour)) 次/小时", "今天共 \(slice.summary.workflowSwitchCount) 次"],
                confidence: .high,
                action: .reviewTimeline,
                method: DailyTrainingMethod(
                    title: "两次切换校准",
                    steps: ["记住当前工作流名称", "只主动切换桌面两次", "回顾中确认新增工作流切换接近两次"],
                    successMeasure: "实际两次切换与时间轴新增记录基本一致"
                )
            )
        }
        if slice.metrics.trainingCount == 0 {
            return focusRecommendation(
                kind: .startFocusRound,
                title: "完成一轮 \(minutes) 分钟专注训练",
                rationale: "目前最缺少的是带结果和难度反馈的训练样本，而不是更多切换总数。",
                evidence: ["今日训练 0 次", "累计完成训练 \(availableSessions.count)/20 次"],
                confidence: confidence,
                minutes: minutes
            )
        }

        let recent = Array(availableSessions
            .sorted { $0.startedAt < $1.startedAt }.suffix(5))
        let recentSuccessRate = recent.isEmpty ? nil : Double(recent.filter(\.isSuccessful).count) / Double(recent.count)
        let recentDifficulty = average(recent.compactMap { $0.difficulty.map(Double.init) })
        if recent.count >= 3,
           (recentSuccessRate.map { $0 <= 0.40 } == true || recentDifficulty.map { $0 >= 4 } == true) {
            let recoveryMinutes = max(10, minutes - 5)
            return DailyCoachRecommendation(
                kind: .recoveryRound,
                title: "下一轮缩短到 \(recoveryMinutes) 分钟",
                rationale: "先恢复稳定完成感，不自动修改正式训练计划。",
                evidence: ["最近 \(recent.count) 次成功率 \(percent(recentSuccessRate ?? 0))", "平均难度 \(recentDifficulty.map { String(format: "%.1f/5", $0) } ?? "暂无")"],
                confidence: confidence,
                action: .startFocus(minutes: recoveryMinutes),
                method: DailyTrainingMethod(
                    title: "恢复轮",
                    steps: ["只写一个可交付结果", "计时期间只使用必要工具", "结束后完整休息 5 分钟并记录难度"],
                    successMeasure: "达到目标时长、完成单一结果且无确认分心"
                )
            )
        }

        let workflowRateHigh = trend.workflowSwitchRateDeltaPercent.map { $0 >= 25 } == true
            || slice.metrics.workflowSwitchesPerHour >= 6
        if workflowRateHigh, slice.summary.workflowSwitchCount >= 3 {
            return DailyCoachRecommendation(
                kind: .agentParkingDrill,
                title: "练习一次“保存返回点—切换—回来”",
                rationale: "工作流切换偏密集时，训练目标不是禁止切换，而是让每次切换都有明确的回来第一步。",
                evidence: ["工作流切换 \(rounded(slice.metrics.workflowSwitchesPerHour)) 次/小时", trend.workflowSwitchRateDeltaPercent.map { "较近 7 日基线 \(signedPercent($0))" } ?? "趋势样本尚不足"],
                confidence: confidence,
                action: .parkWorkflow,
                method: DailyTrainingMethod(
                    title: "Agent 等待返回点",
                    steps: ["离开前写下回来后的第一步", "保存返回点后再切桌面", "返回原桌面后立刻执行这一步"],
                    successMeasure: "至少保存并返回一次，回来后执行了第一步"
                )
            )
        }

        return focusRecommendation(
            kind: .maintainRound,
            title: "再稳定完成一轮 \(minutes) 分钟",
            rationale: "当前没有足够证据支持增加训练负荷，先重复可完成的方法。",
            evidence: ["今日已训练 \(slice.metrics.trainingCount) 次，成功 \(slice.metrics.successfulTrainingCount) 次", "近 7 日可比样本 \(baseline.count) 天"],
            confidence: confidence,
            minutes: minutes
        )
    }

    private static func focusRecommendation(
        kind: DailyCoachKind,
        title: String,
        rationale: String,
        evidence: [String],
        confidence: DailyCoachConfidence,
        minutes: Int
    ) -> DailyCoachRecommendation {
        DailyCoachRecommendation(
            kind: kind,
            title: title,
            rationale: rationale,
            evidence: evidence,
            confidence: confidence,
            action: .startFocus(minutes: minutes),
            method: DailyTrainingMethod(
                title: "单一产出训练",
                steps: ["开始前写清这一轮唯一产出", "只使用该工作流的必要工具；Agent 等待时先保存返回点", "结束后记录完成情况和主观难度 1–5"],
                successMeasure: "达到目标时长、完成目标且没有确认的非必要偏离"
            )
        )
    }

    private static func evaluate(
        _ recommendation: DailyCoachRecommendation,
        previousMetrics: DailyNormalizedMetrics?,
        current: DaySlice
    ) -> DailyCoachEvaluation {
        switch recommendation.kind {
        case .collectData:
            if current.metrics.recordedMinutes >= minimumRecordedSeconds / 60 {
                return DailyCoachEvaluation(status: .improved, title: "样本已形成", evidence: "今天获得 \(rounded(current.metrics.recordedMinutes)) 分钟有效记录。")
            }
            return DailyCoachEvaluation(status: .insufficientData, title: "样本仍不足", evidence: "今天只有 \(rounded(current.metrics.recordedMinutes)) 分钟有效记录。")
        case .repairAttribution:
            if current.metrics.attributedRatio >= minimumAttributedRatio {
                return DailyCoachEvaluation(status: .improved, title: "工作流归因已恢复", evidence: "归因率达到 \(percent(current.metrics.attributedRatio))。")
            }
            return DailyCoachEvaluation(status: .needsAdjustment, title: "桌面绑定仍需校准", evidence: "归因率仍为 \(percent(current.metrics.attributedRatio))。")
        case .verifySpaceTracking:
            let previousRate = previousMetrics?.workflowSwitchesPerHour ?? 36
            if current.metrics.workflowSwitchesPerHour < max(18, previousRate / 2) {
                return DailyCoachEvaluation(status: .improved, title: "Space 信号已回落", evidence: "工作流切换降至 \(rounded(current.metrics.workflowSwitchesPerHour)) 次/小时。")
            }
            return DailyCoachEvaluation(status: .needsAdjustment, title: "Space 信号仍异常", evidence: "今天仍有 \(rounded(current.metrics.workflowSwitchesPerHour)) 次/小时。")
        case .startFocusRound, .recoveryRound, .maintainRound:
            guard current.metrics.trainingCount > 0 else {
                return DailyCoachEvaluation(status: .notRun, title: "上一项训练尚未执行", evidence: "今天没有完成专注训练。")
            }
            if current.metrics.successfulTrainingCount > 0 {
                return DailyCoachEvaluation(status: .improved, title: "训练已完成", evidence: "今天完成 \(current.metrics.successfulTrainingCount)/\(current.metrics.trainingCount) 次成功训练。")
            }
            return DailyCoachEvaluation(status: .needsAdjustment, title: "训练已执行但尚未成功", evidence: "今天训练 \(current.metrics.trainingCount) 次，成功 0 次；下一轮应降低负荷。")
        case .agentParkingDrill:
            guard current.metrics.parkingCount > 0 else {
                return DailyCoachEvaluation(status: .notRun, title: "返回点流程尚未练习", evidence: "今天没有保存返回点的记录。")
            }
            let improved = previousMetrics.map {
                current.metrics.workflowSwitchesPerHour < $0.workflowSwitchesPerHour
            } ?? true
            return DailyCoachEvaluation(
                status: improved ? .improved : .needsAdjustment,
                title: improved ? "返回点流程已执行" : "已保存返回点，但切换密度未下降",
                evidence: "今天保存返回点 \(current.metrics.parkingCount) 次，工作流切换 \(rounded(current.metrics.workflowSwitchesPerHour)) 次/小时。"
            )
        }
    }

    private static func clipped(
        _ activity: ActivityRecord,
        start: Date,
        end: Date,
        now: Date
    ) -> ActivityRecord? {
        let activityEnd = min(activity.endedAt ?? now, end)
        guard activity.startedAt < end, activityEnd > start else { return nil }
        return ActivityRecord(
            id: activity.id,
            app: activity.app,
            startedAt: max(activity.startedAt, start),
            endedAt: activityEnd,
            taskID: activity.taskID,
            focusSessionID: activity.focusSessionID,
            classification: activity.classification,
            source: activity.source
        )
    }

    private static func clipped(
        _ interval: TaskIntervalRecord,
        start: Date,
        end: Date,
        now: Date
    ) -> TaskIntervalRecord? {
        let intervalEnd = min(interval.endedAt ?? now, end)
        guard interval.startedAt < end, intervalEnd > start else { return nil }
        return TaskIntervalRecord(
            id: interval.id,
            taskID: interval.taskID,
            startedAt: max(interval.startedAt, start),
            endedAt: intervalEnd,
            workflowSource: interval.workflowSource
        )
    }

    private static func previousWorkday(
        in activities: [ActivityRecord],
        before date: Date,
        calendar: Calendar
    ) -> Date? {
        Set(activities.map { calendar.startOfDay(for: $0.startedAt) })
            .filter { $0 < date }
            .max()
    }

    private static func confidence(
        quality: DailyDataQuality,
        baselineDays: Int
    ) -> DailyCoachConfidence {
        guard quality.isReliableForBehavior else { return .low }
        if baselineDays >= 5 { return .high }
        if baselineDays >= 2 { return .medium }
        return .low
    }

    private static func relativeDelta(_ value: Double, _ baseline: Double?) -> Double? {
        guard let baseline, baseline > 0 else { return nil }
        return (value - baseline) / baseline * 100
    }

    private static func zipOptional(_ left: Double?, _ right: Double?) -> (Double, Double)? {
        guard let left, let right else { return nil }
        return (left, right)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let ordered = values.sorted()
        let middle = ordered.count / 2
        if ordered.count.isMultiple(of: 2) {
            return (ordered[middle - 1] + ordered[middle]) / 2
        }
        return ordered[middle]
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func signedPercent(_ value: Double) -> String {
        String(format: "%+.0f%%", value)
    }

    private static func rounded(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
