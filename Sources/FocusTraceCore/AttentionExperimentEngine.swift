import Foundation

/// A persisted, user-confirmed change to one attention habit. Experiments use
/// existing aggregate behavior and training feedback; they never add raw
/// collection or claim to measure neurological load.
public enum AttentionExperimentVariable: String, Codable, CaseIterable, Sendable {
    case protectedOutputBlock
    case singleOutputBoundary
    case savedReturnPoint
    case focusDuration
}

public enum AttentionExperimentTimeBand: String, Codable, CaseIterable, Sendable {
    case morning
    case afternoon
    case evening

    public static func containing(
        _ date: Date,
        calendar: Calendar = .current
    ) -> AttentionExperimentTimeBand {
        let hour = calendar.component(.hour, from: date)
        if hour < 12 { return .morning }
        if hour < 18 { return .afternoon }
        return .evening
    }

    fileprivate func contains(
        _ date: Date,
        calendar: Calendar
    ) -> Bool {
        Self.containing(date, calendar: calendar) == self
    }
}

public enum AttentionExperimentStatus: String, Codable, Equatable, Sendable {
    case active
    case completed
    case stopped
}

public enum AttentionExperimentResult: String, Codable, Equatable, Sendable {
    case targetMet
    case needsAdjustment
    case insufficientEvidence
    case stopped
}

public struct AttentionExperimentRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let metricKind: AttentionDashboardMetricKind
    public let variable: AttentionExperimentVariable
    public let title: String
    public let hypothesis: String
    public let methodTitle: String
    public let steps: [String]
    public let successMeasure: String
    public let evidence: [String]
    public let action: DailyCoachAction
    public let baselineValue: Double
    public let baselineSecondaryValue: Double?
    public let targetValue: Double
    public let targetSecondaryValue: Double?
    public let lowerIsBetter: Bool
    public let targetReliableSamples: Int
    public let startedAt: Date
    public let measurementStartsAt: Date
    public let contextWorkflowID: UUID?
    public let contextTimeBand: AttentionExperimentTimeBand
    public let status: AttentionExperimentStatus
    public let completedAt: Date?
    public let result: AttentionExperimentResult?
    public let resultSummary: String?

    public init(
        id: UUID = UUID(),
        metricKind: AttentionDashboardMetricKind,
        variable: AttentionExperimentVariable,
        title: String,
        hypothesis: String,
        methodTitle: String,
        steps: [String],
        successMeasure: String,
        evidence: [String],
        action: DailyCoachAction,
        baselineValue: Double,
        baselineSecondaryValue: Double? = nil,
        targetValue: Double,
        targetSecondaryValue: Double? = nil,
        lowerIsBetter: Bool,
        targetReliableSamples: Int,
        startedAt: Date,
        measurementStartsAt: Date,
        contextWorkflowID: UUID? = nil,
        contextTimeBand: AttentionExperimentTimeBand,
        status: AttentionExperimentStatus = .active,
        completedAt: Date? = nil,
        result: AttentionExperimentResult? = nil,
        resultSummary: String? = nil
    ) {
        self.id = id
        self.metricKind = metricKind
        self.variable = variable
        self.title = title
        self.hypothesis = hypothesis
        self.methodTitle = methodTitle
        self.steps = Array(steps.prefix(4))
        self.successMeasure = successMeasure
        self.evidence = Array(evidence.prefix(2))
        self.action = action
        self.baselineValue = baselineValue
        self.baselineSecondaryValue = baselineSecondaryValue
        self.targetValue = targetValue
        self.targetSecondaryValue = targetSecondaryValue
        self.lowerIsBetter = lowerIsBetter
        self.targetReliableSamples = max(1, targetReliableSamples)
        self.startedAt = startedAt
        self.measurementStartsAt = measurementStartsAt
        self.contextWorkflowID = contextWorkflowID
        self.contextTimeBand = contextTimeBand
        self.status = status
        self.completedAt = completedAt
        self.result = result
        self.resultSummary = resultSummary
    }
}

public enum AttentionExperimentProgressState: String, Equatable, Sendable {
    case collecting
    case ready
    case completed
    case stopped
}

public struct AttentionExperimentProgress: Equatable, Sendable {
    public let state: AttentionExperimentProgressState
    public let reliableSamples: Int
    public let targetReliableSamples: Int
    public let noOpportunityCount: Int
    public let missingInputCount: Int
    public let qualityBlockedCount: Int
    public let observedValue: Double?
    public let observedSecondaryValue: Double?
    public let targetMet: Bool?
    public let summary: String
    public let nextAction: String

    public init(
        state: AttentionExperimentProgressState,
        reliableSamples: Int,
        targetReliableSamples: Int,
        noOpportunityCount: Int,
        missingInputCount: Int,
        qualityBlockedCount: Int,
        observedValue: Double?,
        observedSecondaryValue: Double?,
        targetMet: Bool?,
        summary: String,
        nextAction: String
    ) {
        self.state = state
        self.reliableSamples = max(0, reliableSamples)
        self.targetReliableSamples = max(1, targetReliableSamples)
        self.noOpportunityCount = max(0, noOpportunityCount)
        self.missingInputCount = max(0, missingInputCount)
        self.qualityBlockedCount = max(0, qualityBlockedCount)
        self.observedValue = observedValue
        self.observedSecondaryValue = observedSecondaryValue
        self.targetMet = targetMet
        self.summary = summary
        self.nextAction = nextAction
    }
}

public enum AttentionExperimentEngine {
    public static let minimumWorkflowContextSeconds: TimeInterval = 10 * 60

    public static func canStartNew(
        in experiments: [AttentionExperimentRecord]
    ) -> Bool {
        !experiments.contains { $0.status == .active }
    }

    public static func proposal(
        recommendation: DailyCoachRecommendation,
        dashboard: AttentionDashboard,
        contextWorkflowID: UUID?,
        startedAt: Date,
        calendar: Calendar = .current
    ) -> AttentionExperimentRecord? {
        guard dashboard.finding?.state == .needsAttention,
              let kind = dashboard.finding?.kind,
              let metric = dashboard.metrics.first(where: { $0.kind == kind }),
              let trend = metric.trend,
              trend.direction == .worsening,
              let baseline = trend.recentMedian else {
            return nil
        }

        let target: Double
        let secondaryTarget: Double?
        let sampleTarget: Int
        let variable: AttentionExperimentVariable
        switch kind {
        case .sustainedProgress:
            target = baseline + max(2, baseline * 0.15)
            secondaryTarget = nil
            sampleTarget = 3
            variable = .protectedOutputBlock
        case .fragmentation:
            target = max(0, baseline - 10)
            secondaryTarget = nil
            sampleTarget = 3
            variable = .singleOutputBoundary
        case .switchingBoundary:
            target = max(0, baseline - 15)
            secondaryTarget = nil
            sampleTarget = 3
            variable = .savedReturnPoint
        case .contextRecovery:
            target = min(100, baseline + 20)
            secondaryTarget = nil
            sampleTarget = 3
            variable = .savedReturnPoint
        case .trainingFeedback:
            target = 80
            secondaryTarget = 3
            sampleTarget = 5
            variable = .focusDuration
        }

        let measurementStart: Date
        if kind == .trainingFeedback {
            measurementStart = startedAt
        } else {
            let day = calendar.startOfDay(for: startedAt)
            measurementStart = calendar.date(byAdding: .day, value: 1, to: day)
                ?? day.addingTimeInterval(86_400)
        }
        return AttentionExperimentRecord(
            metricKind: kind,
            variable: variable,
            title: recommendation.title,
            hypothesis: recommendation.rationale,
            methodTitle: recommendation.method.title,
            steps: recommendation.method.steps,
            successMeasure: recommendation.method.successMeasure,
            evidence: recommendation.evidence,
            action: recommendation.action,
            baselineValue: baseline,
            baselineSecondaryValue: trend.points
                .filter { !$0.isPartial && $0.isReliable }
                .compactMap(\.secondaryValue)
                .suffix(AttentionDashboardEngine.recentTrendDays)
                .median,
            targetValue: target,
            targetSecondaryValue: secondaryTarget,
            lowerIsBetter: trend.lowerIsBetter,
            targetReliableSamples: sampleTarget,
            startedAt: startedAt,
            measurementStartsAt: measurementStart,
            contextWorkflowID: contextWorkflowID,
            contextTimeBand: .containing(startedAt, calendar: calendar)
        )
    }

    public static func evaluate(
        _ experiment: AttentionExperimentRecord,
        dashboard: AttentionDashboard,
        taskIntervals: [TaskIntervalRecord],
        focusSessions: [FocusSessionRecord],
        taskParkings: [TaskParkingRecord] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AttentionExperimentProgress {
        if experiment.status != .active {
            return terminalProgress(experiment)
        }
        if experiment.metricKind == .trainingFeedback {
            return evaluateTraining(
                experiment,
                focusSessions: focusSessions,
                calendar: calendar
            )
        }
        guard let trend = dashboard.metrics.first(
            where: { $0.kind == experiment.metricKind }
        )?.trend else {
            return AttentionExperimentProgress(
                state: .collecting,
                reliableSamples: 0,
                targetReliableSamples: experiment.targetReliableSamples,
                noOpportunityCount: 0,
                missingInputCount: 0,
                qualityBlockedCount: 1,
                observedValue: nil,
                observedSecondaryValue: nil,
                targetMet: nil,
                summary: "当前趋势没有可用于实验评估的指标。",
                nextAction: "保持实验变量不变，先修复回顾页标出的数据质量问题。"
            )
        }

        let measurementDay = calendar.startOfDay(
            for: experiment.measurementStartsAt
        )
        var reliableValues: [Double] = []
        var secondaryValues: [Double] = []
        var noOpportunity = 0
        var missingInput = 0
        var qualityBlocked = 0

        let evidencePoints = trend.points
            .filter {
                calendar.startOfDay(for: $0.date) >= measurementDay
                    && !$0.isPartial
            }
            .sorted { $0.date < $1.date }
            .prefix(AttentionDashboardEngine.experimentEvidenceWorkdayCount)

        for point in evidencePoints {
            guard hasMatchingContext(
                experiment,
                on: point.date,
                taskIntervals: taskIntervals,
                focusSessions: focusSessions,
                taskParkings: taskParkings,
                now: now,
                calendar: calendar
            ) else {
                noOpportunity += 1
                continue
            }
            guard performedExperimentVariable(
                experiment,
                on: point.date,
                focusSessions: focusSessions,
                taskParkings: taskParkings,
                calendar: calendar
            ) else {
                missingInput += 1
                continue
            }
            switch point.effectiveAvailability {
            case .reliable:
                if reliableValues.count < experiment.targetReliableSamples,
                   let value = point.value {
                    reliableValues.append(value)
                    if let secondaryValue = point.secondaryValue {
                        secondaryValues.append(secondaryValue)
                    }
                } else if point.value == nil {
                    missingInput += 1
                }
            case .noOpportunity, .partial:
                noOpportunity += 1
            case .missingInput, .calibrating:
                missingInput += 1
            case .qualityBlocked:
                qualityBlocked += 1
            }
        }

        let observed = reliableValues.median
        let observedSecondary = secondaryValues.median
        let hasEnoughReliableSamples =
            reliableValues.count >= experiment.targetReliableSamples
        let evidenceWindowEnded =
            evidencePoints.count
                >= AttentionDashboardEngine.experimentEvidenceWorkdayCount
        let ready = hasEnoughReliableSamples || evidenceWindowEnded
        let targetMet = hasEnoughReliableSamples && observed.map {
            experiment.lowerIsBetter
                ? $0 <= experiment.targetValue
                : $0 >= experiment.targetValue
        } == true
        let finalTargetResult: Bool? = hasEnoughReliableSamples
            ? targetMet
            : nil
        let summary: String
        let nextAction: String
        if evidenceWindowEnded && !hasEnoughReliableSamples {
            summary = "首个 10 个完整工作日的证据窗口已结束，仅形成 \(reliableValues.count)/\(experiment.targetReliableSamples) 个可靠样本；当前不能判断实验是否有效。"
            nextAction = "保存“证据不足”结论；如仍要验证，应先修复主要缺口，再由新的可靠问题发起下一项实验。"
        } else {
            summary = progressSummary(
                experiment: experiment,
                observed: observed,
                targetMet: ready ? finalTargetResult : nil
            )
            nextAction = ready
                ? "证据窗口已完成；保存结论后，再决定是否调整下一项变量。"
                : collectingNextAction(
                    reliable: reliableValues.count,
                    target: experiment.targetReliableSamples,
                    noOpportunity: noOpportunity,
                    missingInput: missingInput,
                    qualityBlocked: qualityBlocked
                )
        }
        return AttentionExperimentProgress(
            state: ready ? .ready : .collecting,
            reliableSamples: reliableValues.count,
            targetReliableSamples: experiment.targetReliableSamples,
            noOpportunityCount: noOpportunity,
            missingInputCount: missingInput,
            qualityBlockedCount: qualityBlocked,
            observedValue: observed,
            observedSecondaryValue: observedSecondary,
            targetMet: ready ? finalTargetResult : nil,
            summary: summary,
            nextAction: nextAction
        )
    }

    public static func completed(
        _ experiment: AttentionExperimentRecord,
        progress: AttentionExperimentProgress,
        at date: Date = Date()
    ) -> AttentionExperimentRecord {
        let result: AttentionExperimentResult
        if progress.state != .ready {
            result = .insufficientEvidence
        } else if let targetMet = progress.targetMet {
            result = targetMet ? .targetMet : .needsAdjustment
        } else {
            result = .insufficientEvidence
        }
        return replacingTerminalState(
            experiment,
            status: .completed,
            result: result,
            summary: progress.summary,
            at: date
        )
    }

    public static func stopped(
        _ experiment: AttentionExperimentRecord,
        at date: Date = Date()
    ) -> AttentionExperimentRecord {
        replacingTerminalState(
            experiment,
            status: .stopped,
            result: .stopped,
            summary: "实验由用户提前结束；未据此修改训练计划。",
            at: date
        )
    }

    private static func evaluateTraining(
        _ experiment: AttentionExperimentRecord,
        focusSessions: [FocusSessionRecord],
        calendar: Calendar
    ) -> AttentionExperimentProgress {
        let opportunities = focusSessions.filter { session in
            guard session.startedAt >= experiment.measurementStartsAt,
                  session.endedAt != nil,
                  session.outcome != .pending else {
                return false
            }
            if let workflowID = experiment.contextWorkflowID,
               session.taskID != workflowID {
                return false
            }
            return experiment.contextTimeBand.contains(
                session.startedAt,
                calendar: calendar
            )
        }.sorted { $0.startedAt < $1.startedAt }
        var recent: [FocusSessionRecord] = []
        var missingFeedback = 0
        for session in opportunities {
            if session.difficulty != nil {
                recent.append(session)
                if recent.count >= experiment.targetReliableSamples {
                    break
                }
            } else {
                missingFeedback += 1
            }
        }
        let observed = recent.isEmpty
            ? nil
            : Double(recent.filter(\.isSuccessful).count)
                / Double(recent.count) * 100
        let difficulty = recent.compactMap { $0.difficulty.map(Double.init) }
            .median
        let ready = recent.count >= experiment.targetReliableSamples
        let targetMet = ready
            && (observed ?? 0) >= experiment.targetValue
            && difficulty.map {
                $0 <= (experiment.targetSecondaryValue ?? 5)
            } == true
        return AttentionExperimentProgress(
            state: ready ? .ready : .collecting,
            reliableSamples: recent.count,
            targetReliableSamples: experiment.targetReliableSamples,
            noOpportunityCount: opportunities.isEmpty ? 1 : 0,
            missingInputCount: missingFeedback,
            qualityBlockedCount: 0,
            observedValue: observed,
            observedSecondaryValue: difficulty,
            targetMet: ready ? targetMet : nil,
            summary: progressSummary(
                experiment: experiment,
                observed: observed,
                targetMet: ready ? targetMet : nil,
                observedSecondary: difficulty
            ),
            nextAction: ready
                ? "五次可比训练已完成；保存结论后，再决定是否调整训练时长。"
                : missingFeedback > 0
                    ? "训练结束后补记 1–5 级难度；没有难度反馈的训练不进入验收。"
                    : "保持工作流、时段和允许工具不变，再完成一轮训练。"
        )
    }

    private static func hasMatchingContext(
        _ experiment: AttentionExperimentRecord,
        on date: Date,
        taskIntervals: [TaskIntervalRecord],
        focusSessions: [FocusSessionRecord],
        taskParkings: [TaskParkingRecord],
        now: Date,
        calendar: Calendar
    ) -> Bool {
        if performedExperimentVariable(
            experiment,
            on: date,
            focusSessions: focusSessions,
            taskParkings: taskParkings,
            calendar: calendar
        ) {
            return true
        }
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        let duration = taskIntervals
            .filter {
                experiment.contextWorkflowID == nil
                    || $0.taskID == experiment.contextWorkflowID
            }
            .reduce(0.0) { total, interval in
                let start = max(interval.startedAt, dayStart)
                let end = min(interval.endedAt ?? now, dayEnd)
                guard end > start else { return total }
                let midpoint = start.addingTimeInterval(
                    end.timeIntervalSince(start) / 2
                )
                guard experiment.contextTimeBand.contains(
                    midpoint,
                    calendar: calendar
                ) else {
                    return total
                }
                return total + end.timeIntervalSince(start)
            }
        return duration >= minimumWorkflowContextSeconds
    }

    private static func performedExperimentVariable(
        _ experiment: AttentionExperimentRecord,
        on date: Date,
        focusSessions: [FocusSessionRecord],
        taskParkings: [TaskParkingRecord],
        calendar: Calendar
    ) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        switch experiment.variable {
        case .protectedOutputBlock, .singleOutputBoundary:
            return focusSessions.contains { session in
                session.startedAt >= dayStart
                    && session.startedAt < dayEnd
                    && session.endedAt != nil
                    && session.outcome != .pending
                    && (
                        experiment.contextWorkflowID == nil
                            || session.taskID == experiment.contextWorkflowID
                    )
                    && experiment.contextTimeBand.contains(
                        session.startedAt,
                        calendar: calendar
                    )
            }
        case .savedReturnPoint:
            return taskParkings.contains { parking in
                parking.parkedAt >= dayStart
                    && parking.parkedAt < dayEnd
                    && (
                        experiment.contextWorkflowID == nil
                            || parking.taskID == experiment.contextWorkflowID
                    )
                    && experiment.contextTimeBand.contains(
                        parking.parkedAt,
                        calendar: calendar
                    )
            }
        case .focusDuration:
            return false
        }
    }

    private static func progressSummary(
        experiment: AttentionExperimentRecord,
        observed: Double?,
        targetMet: Bool?,
        observedSecondary: Double? = nil
    ) -> String {
        guard let observed else {
            return "还没有形成可比结果；当前不判断实验是否有效。"
        }
        let value = formatted(observed, kind: experiment.metricKind)
        let target = formatted(
            experiment.targetValue,
            kind: experiment.metricKind
        )
        let secondary = observedSecondary.map {
            "，难度中位数 \(String(format: "%.1f", $0))/5"
        } ?? ""
        guard let targetMet else {
            return "当前可比样本为 \(value)\(secondary)，目标 \(target)；样本仍在收集。"
        }
        return targetMet
            ? "当前可比样本为 \(value)\(secondary)，已达到目标 \(target)。"
            : "当前可比样本为 \(value)\(secondary)，尚未达到目标 \(target)。"
    }

    private static func collectingNextAction(
        reliable: Int,
        target: Int,
        noOpportunity: Int,
        missingInput: Int,
        qualityBlocked: Int
    ) -> String {
        if qualityBlocked > 0 {
            return "先修复回顾页标出的数据质量问题；被门禁阻断的日期不进入验收。"
        }
        if missingInput > 0 {
            return "已有同情境工作，但未观察到实验动作或必要反馈；下一次从实验卡片开始，并完成结果记录。"
        }
        if noOpportunity > 0 && reliable == 0 {
            return "尚未出现同工作流、同时段的可比机会；无需刻意制造切换。"
        }
        return "保持唯一变量不变，还需 \(max(0, target - reliable)) 个可靠样本。"
    }

    private static func terminalProgress(
        _ experiment: AttentionExperimentRecord
    ) -> AttentionExperimentProgress {
        AttentionExperimentProgress(
            state: experiment.status == .stopped ? .stopped : .completed,
            reliableSamples: experiment.targetReliableSamples,
            targetReliableSamples: experiment.targetReliableSamples,
            noOpportunityCount: 0,
            missingInputCount: 0,
            qualityBlockedCount: 0,
            observedValue: nil,
            observedSecondaryValue: nil,
            targetMet: experiment.result == .targetMet,
            summary: experiment.resultSummary ?? "实验已结束。",
            nextAction: "先保持当前方法；只有新的可靠主要问题出现时再开始下一项实验。"
        )
    }

    private static func replacingTerminalState(
        _ experiment: AttentionExperimentRecord,
        status: AttentionExperimentStatus,
        result: AttentionExperimentResult,
        summary: String,
        at date: Date
    ) -> AttentionExperimentRecord {
        AttentionExperimentRecord(
            id: experiment.id,
            metricKind: experiment.metricKind,
            variable: experiment.variable,
            title: experiment.title,
            hypothesis: experiment.hypothesis,
            methodTitle: experiment.methodTitle,
            steps: experiment.steps,
            successMeasure: experiment.successMeasure,
            evidence: experiment.evidence,
            action: experiment.action,
            baselineValue: experiment.baselineValue,
            baselineSecondaryValue: experiment.baselineSecondaryValue,
            targetValue: experiment.targetValue,
            targetSecondaryValue: experiment.targetSecondaryValue,
            lowerIsBetter: experiment.lowerIsBetter,
            targetReliableSamples: experiment.targetReliableSamples,
            startedAt: experiment.startedAt,
            measurementStartsAt: experiment.measurementStartsAt,
            contextWorkflowID: experiment.contextWorkflowID,
            contextTimeBand: experiment.contextTimeBand,
            status: status,
            completedAt: date,
            result: result,
            resultSummary: summary
        )
    }

    private static func formatted(
        _ value: Double,
        kind: AttentionDashboardMetricKind
    ) -> String {
        if kind == .sustainedProgress {
            return "\(String(format: "%.1f", value)) 分钟"
        }
        return "\(Int(value.rounded()))%"
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
