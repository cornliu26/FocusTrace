import Foundation

/// A read-only view of FocusTrace's on-disk snapshot. It deliberately exposes
/// domain records rather than persistence implementation types so local tools
/// can share the analysis rules without importing AppKit or SwiftUI.
public struct FocusTraceLocalSnapshot: Decodable, Sendable {
    public let tasks: [TaskRecord]
    public let taskIntervals: [TaskIntervalRecord]
    public let activities: [ActivityRecord]
    public let focusSessions: [FocusSessionRecord]
    public let interruptions: [InterruptionRecord]
    public let trainingPlans: [TrainingPlanRecord]
    public let markers: [TimelineMarkerRecord]
    public let workflowTransitions: [WorkflowTransitionRecord]
    public let taskParkings: [TaskParkingRecord]
    public let requirements: [RequirementRecord]

    public init(
        tasks: [TaskRecord] = [],
        taskIntervals: [TaskIntervalRecord] = [],
        activities: [ActivityRecord] = [],
        focusSessions: [FocusSessionRecord] = [],
        interruptions: [InterruptionRecord] = [],
        trainingPlans: [TrainingPlanRecord] = [],
        markers: [TimelineMarkerRecord] = [],
        workflowTransitions: [WorkflowTransitionRecord] = [],
        taskParkings: [TaskParkingRecord] = [],
        requirements: [RequirementRecord] = []
    ) {
        self.tasks = tasks
        self.taskIntervals = taskIntervals
        self.activities = activities
        self.focusSessions = focusSessions
        self.interruptions = interruptions
        self.trainingPlans = trainingPlans
        self.markers = markers
        self.workflowTransitions = workflowTransitions
        self.taskParkings = taskParkings
        self.requirements = requirements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try container.decodeIfPresent([PersistedTask].self, forKey: .tasks)?
            .map(\.record) ?? []
        taskIntervals = try container.decodeIfPresent([PersistedTaskInterval].self, forKey: .taskIntervals)?
            .map(\.record) ?? []
        activities = try container.decodeIfPresent([PersistedActivity].self, forKey: .activities)?
            .map(\.record) ?? []
        focusSessions = try container.decodeIfPresent([PersistedFocusSession].self, forKey: .focusSessions)?
            .map(\.record) ?? []
        interruptions = try container.decodeIfPresent([PersistedInterruption].self, forKey: .interruptions)?
            .map(\.record) ?? []
        trainingPlans = try container.decodeIfPresent([PersistedTrainingPlan].self, forKey: .trainingPlans)?
            .map(\.record) ?? []
        markers = try container.decodeIfPresent([PersistedTimelineMarker].self, forKey: .markers)?
            .map(\.record) ?? []
        workflowTransitions = try container.decodeIfPresent(
            [PersistedWorkflowTransition].self,
            forKey: .workflowTransitions
        )?.map(\.record) ?? []
        taskParkings = try container.decodeIfPresent([PersistedTaskParking].self, forKey: .taskParkings)?
            .map(\.record) ?? []
        requirements = try container.decodeIfPresent(
            [PersistedRequirement].self,
            forKey: .requirements
        )?.map(\.record) ?? []
    }

    public static func load(from url: URL) throws -> FocusTraceLocalSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FocusTraceLocalSnapshot.self, from: Data(contentsOf: url))
    }

    public var currentPlan: TrainingPlanRecord {
        trainingPlans.max(by: { $0.version < $1.version })
            ?? TrainingPlanRecord(version: 1, focusMinutes: 15, reason: "基线数据不足，使用默认 15 分钟")
    }

    private enum CodingKeys: String, CodingKey {
        case tasks
        case taskIntervals
        case activities
        case focusSessions
        case interruptions
        case trainingPlans
        case markers
        case workflowTransitions
        case taskParkings
        case requirements
    }
}

public struct AutomationDailyReport: Equatable, Sendable {
    public let reportDate: Date
    public let reportCivilDate: String
    public let generatedAt: Date
    public let summary: DailySummary
    public let trainingCount: Int
    public let successfulTrainingCount: Int
    public let totalWorkdays: Int
    public let totalCompletedSessions: Int
    public let currentPlan: TrainingPlanRecord
    public let analysis: AnalysisResult
    public let coaching: DailyCoachingAnalysis
    public let workflowContexts: [AutomationWorkflowContextArtifact]
    public let transitionAudit: AutomationWorkflowTransitionAuditArtifact
    public let observationPlan: DailyObservationPlan

    public init(
        reportDate: Date,
        reportCivilDate: String,
        generatedAt: Date,
        summary: DailySummary,
        trainingCount: Int,
        successfulTrainingCount: Int,
        totalWorkdays: Int,
        totalCompletedSessions: Int,
        currentPlan: TrainingPlanRecord,
        analysis: AnalysisResult,
        coaching: DailyCoachingAnalysis,
        workflowContexts: [AutomationWorkflowContextArtifact],
        transitionAudit: AutomationWorkflowTransitionAuditArtifact,
        observationPlan: DailyObservationPlan
    ) {
        self.reportDate = reportDate
        self.reportCivilDate = reportCivilDate
        self.generatedAt = generatedAt
        self.summary = summary
        self.trainingCount = trainingCount
        self.successfulTrainingCount = successfulTrainingCount
        self.totalWorkdays = totalWorkdays
        self.totalCompletedSessions = totalCompletedSessions
        self.currentPlan = currentPlan
        self.analysis = analysis
        self.coaching = coaching
        self.workflowContexts = workflowContexts
        self.transitionAudit = transitionAudit
        self.observationPlan = observationPlan
    }
}

public struct AutomationDailyCounts: Codable, Equatable, Sendable {
    public let appSwitches: Int
    public let workflowSwitches: Int
    public let manualWorkflowSwitches: Int
    public let suspectedDistractions: Int
    public let confirmedDistractions: Int
    public let trainings: Int
    public let successfulTrainings: Int
    public let parkings: Int
    public let resumedParkings: Int
}

public struct AutomationPhaseTwoArtifact: Codable, Equatable, Sendable {
    public let status: String
    public let workdays: Int
    public let sessions: Int
    public let remainingWorkdays: Int
    public let remainingSessions: Int
    public let insights: [AnalysisInsightArtifact]
    public let suggestionTitle: String?
    public let suggestionEvidence: String?
}

public struct AnalysisInsightArtifact: Codable, Equatable, Sendable {
    public let title: String
    public let value: String
    public let detail: String
}

public struct AutomationPlanArtifact: Codable, Equatable, Sendable {
    public let version: Int
    public let focusMinutes: Int
    public let sessionsPerDay: Int
    public let breakMinutes: Int
    public let reminderThresholdSeconds: Int
    public let reason: String
}

public struct AutomationReportArtifact: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let reportID: String
    public let reportDate: Date
    public let reportCivilDate: String?
    public let generatedAt: Date
    public let counts: AutomationDailyCounts
    public let normalized: DailyNormalizedMetrics
    public let dataQuality: DailyDataQuality
    public let trend: DailyTrendComparison
    public let previousRecommendationEvaluation: DailyCoachEvaluation?
    public let recommendation: DailyCoachRecommendation
    public let phaseTwo: AutomationPhaseTwoArtifact
    public let currentPlan: AutomationPlanArtifact
    public let workflowContexts: [AutomationWorkflowContextArtifact]?
    public let transitionAudit: AutomationWorkflowTransitionAuditArtifact?
    public let observationPlan: DailyObservationPlan?

    public init(report: AutomationDailyReport) {
        schemaVersion = 5
        reportID = "focustrace-\(Int(report.reportDate.timeIntervalSince1970))-\(Int(report.generatedAt.timeIntervalSince1970))"
        reportDate = report.reportDate
        reportCivilDate = report.reportCivilDate
        generatedAt = report.generatedAt
        counts = AutomationDailyCounts(
            appSwitches: report.summary.appSwitchCount,
            workflowSwitches: report.summary.workflowSwitchCount,
            manualWorkflowSwitches: report.summary.taskSwitchCount,
            suspectedDistractions: report.summary.suspectedDistractionCount,
            confirmedDistractions: report.summary.confirmedDistractionCount,
            trainings: report.trainingCount,
            successfulTrainings: report.successfulTrainingCount,
            parkings: report.summary.taskParkingCount,
            resumedParkings: report.summary.resumedTaskCount
        )
        normalized = report.coaching.metrics
        dataQuality = report.coaching.quality
        trend = report.coaching.trend
        previousRecommendationEvaluation = report.coaching.previousRecommendationEvaluation
        recommendation = report.coaching.recommendation
        workflowContexts = report.workflowContexts
        transitionAudit = report.transitionAudit
        observationPlan = report.observationPlan
        currentPlan = AutomationPlanArtifact(
            version: report.currentPlan.version,
            focusMinutes: report.currentPlan.focusMinutes,
            sessionsPerDay: report.currentPlan.sessionsPerDay,
            breakMinutes: report.currentPlan.breakMinutes,
            reminderThresholdSeconds: report.currentPlan.reminderThresholdSeconds,
            reason: report.currentPlan.reason
        )
        let workdays: Int
        let sessions: Int
        let status: String
        switch report.analysis.readiness {
        case let .locked(valueWorkdays, valueSessions):
            status = "locked"
            workdays = valueWorkdays
            sessions = valueSessions
        case .ready:
            status = "ready"
            workdays = report.totalWorkdays
            sessions = report.totalCompletedSessions
        }
        phaseTwo = AutomationPhaseTwoArtifact(
            status: status,
            workdays: workdays,
            sessions: sessions,
            remainingWorkdays: max(0, 10 - workdays),
            remainingSessions: max(0, 20 - sessions),
            insights: report.analysis.insights.map {
                AnalysisInsightArtifact(title: $0.title, value: $0.value, detail: $0.detail)
            },
            suggestionTitle: report.analysis.suggestion?.title,
            suggestionEvidence: report.analysis.suggestion?.evidence
        )
    }
}

/// Aggregate-only interpretation written back by the optional Codex daily task.
/// It deliberately references an AutomationReportArtifact instead of activity
/// rows, so the app can reject stale or unrelated reviews.
public enum CodexReviewStatus: String, Codable, Equatable, Sendable {
    case behaviorFinding
    case dataQualityBlocked
}

public enum CodexReviewAnalysisSource: String, Codable, Equatable, Sendable {
    case dataQuality
    case workflowRoute
    case previousRecommendation
    case normalizedTrend
    case phaseTwo
    case localRecommendation
}

public enum CodexReviewContextRelation: String, Codable, Equatable, Sendable {
    case sameDeliverableToolChange
    case adjacentDeliverables
    case differentGoals
    case insufficientEvidence
    case notApplicable
}

public struct CodexReviewRouteSelection: Codable, Equatable, Sendable {
    public let fromWorkflow: String
    public let toWorkflow: String
    public let reason: AutomationWorkflowSwitchReason

    public init(
        fromWorkflow: String,
        toWorkflow: String,
        reason: AutomationWorkflowSwitchReason
    ) {
        self.fromWorkflow = fromWorkflow
        self.toWorkflow = toWorkflow
        self.reason = reason
    }
}

public struct CodexReviewAnalysisAudit: Codable, Equatable, Sendable {
    public let source: CodexReviewAnalysisSource
    public let selectedRoute: CodexReviewRouteSelection?
    public let contextRelation: CodexReviewContextRelation

    public init(
        source: CodexReviewAnalysisSource,
        selectedRoute: CodexReviewRouteSelection? = nil,
        contextRelation: CodexReviewContextRelation = .notApplicable
    ) {
        self.source = source
        self.selectedRoute = selectedRoute
        self.contextRelation = contextRelation
    }
}

public struct CodexReviewArtifact: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sourceReportID: String
    public let reportDate: Date
    public let generatedAt: Date
    public let status: CodexReviewStatus?
    public let problem: String?
    public let recommendation: String
    public let evidence: [String]
    public let nextCheck: String
    public let headline: String?
    public let interpretation: String?
    public let analysisAudit: CodexReviewAnalysisAudit?

    public init(
        schemaVersion: Int = 2,
        sourceReportID: String,
        reportDate: Date,
        generatedAt: Date,
        status: CodexReviewStatus,
        problem: String,
        recommendation: String,
        evidence: [String],
        nextCheck: String,
        analysisAudit: CodexReviewAnalysisAudit? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sourceReportID = sourceReportID
        self.reportDate = reportDate
        self.generatedAt = generatedAt
        self.status = status
        self.problem = problem
        self.recommendation = recommendation
        self.evidence = evidence
        self.nextCheck = nextCheck
        headline = nil
        interpretation = nil
        self.analysisAudit = analysisAudit
    }

    /// Read compatibility for reviews created before the decision-brief
    /// contract. The UI intentionally discards the legacy interpretation
    /// paragraph so an old verbose artifact does not regain prominence.
    public init(
        schemaVersion: Int = 1,
        sourceReportID: String,
        reportDate: Date,
        generatedAt: Date,
        headline: String,
        interpretation: String,
        recommendation: String,
        evidence: [String],
        nextCheck: String
    ) {
        self.schemaVersion = schemaVersion
        self.sourceReportID = sourceReportID
        self.reportDate = reportDate
        self.generatedAt = generatedAt
        status = nil
        problem = nil
        self.recommendation = recommendation
        self.evidence = evidence
        self.nextCheck = nextCheck
        self.headline = headline
        self.interpretation = interpretation
        analysisAudit = nil
    }

    public var displayedProblem: String {
        if schemaVersion == 2 || schemaVersion == 3 {
            return problem?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return headline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public var displayedStatus: CodexReviewStatus {
        if let status { return status }
        let legacyText = [
            headline ?? "",
            interpretation ?? ""
        ].joined(separator: " ")
        return legacyText.contains("不能据此判断注意力")
            ? .dataQualityBlocked
            : .behaviorFinding
    }

    public var hasValidShape: Bool {
        guard !sourceReportID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !recommendation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !nextCheck.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if schemaVersion == 1 {
            return !(headline ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !(interpretation ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && evidence.count == 2
                && evidence.allSatisfy {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
        }

        guard schemaVersion == 2 || schemaVersion == 3,
              status != nil,
              !displayedProblem.isEmpty,
              displayedProblem.count <= 110,
              recommendation.count <= 150,
              nextCheck.count <= 80,
              (1...2).contains(evidence.count),
              evidence.allSatisfy({
                  let text = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                  return !text.isEmpty && text.count <= 80
              }) else {
            return false
        }

        let normalizedEvidence = evidence.map(Self.normalized)
        guard Set(normalizedEvidence).count == evidence.count else {
            return false
        }
        if schemaVersion == 3, analysisAudit == nil {
            return false
        }

        let visibleCharacterCount = displayedProblem.count
            + recommendation.count
            + evidence.reduce(0) { $0 + $1.count }
            + nextCheck.count
        return visibleCharacterCount <= 360
    }

    public func isConsistentWithBehaviorReliability(_ isReliable: Bool) -> Bool {
        guard schemaVersion == 2 || schemaVersion == 3 else {
            return schemaVersion == 1
        }
        if isReliable {
            return status == .behaviorFinding
        }
        return status == .dataQualityBlocked
            && displayedProblem.contains("当前不能据此判断注意力")
    }

    /// Schema v3 records the aggregate source used for the decision. This
    /// prevents a fluent but ungrounded route interpretation from entering the
    /// UI. v1/v2 artifacts remain readable as historical output.
    public func isGrounded(in report: AutomationReportArtifact) -> Bool {
        guard schemaVersion == 3 else {
            return schemaVersion == 1 || schemaVersion == 2
        }
        guard let analysisAudit else { return false }
        let noRoute = analysisAudit.selectedRoute == nil
            && analysisAudit.contextRelation == .notApplicable

        switch analysisAudit.source {
        case .dataQuality:
            return !report.dataQuality.isReliableForBehavior && noRoute
        case .workflowRoute:
            guard report.dataQuality.isReliableForBehavior,
                  let selection = analysisAudit.selectedRoute,
                  analysisAudit.contextRelation != .notApplicable,
                  let transitionAudit = report.transitionAudit,
                  ["semanticEvents", "mixed"].contains(
                      transitionAudit.dataSource ?? ""
                  ),
                  let route = transitionAudit.routes.first(where: {
                      $0.fromWorkflow == selection.fromWorkflow
                          && $0.toWorkflow == selection.toWorkflow
                  }) else {
                return false
            }
            return route.reasonCounts[selection.reason.rawValue, default: 0] >= 2
        case .previousRecommendation:
            guard report.dataQuality.isReliableForBehavior, noRoute,
                  let status = report.previousRecommendationEvaluation?.status else {
                return false
            }
            return status == .needsAdjustment || status == .notRun
        case .normalizedTrend:
            return report.dataQuality.isReliableForBehavior
                && noRoute
                && report.trend.baselineDays >= 2
                && (
                    report.trend.appSwitchRateDeltaPercent != nil
                        || report.trend.workflowSwitchRateDeltaPercent != nil
                        || report.trend.attributedRatioDeltaPoints != nil
                        || report.trend.medianFocusDeltaMinutes != nil
                )
        case .phaseTwo:
            return report.dataQuality.isReliableForBehavior
                && noRoute
                && report.phaseTwo.status == "ready"
                && (
                    !report.phaseTwo.insights.isEmpty
                        || report.phaseTwo.suggestionTitle != nil
                )
        case .localRecommendation:
            return report.dataQuality.isReliableForBehavior && noRoute
        }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }
}

public struct CodexBridgeRegistration: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let reportDirectory: String
    public let updatedAt: Date

    public init(
        schemaVersion: Int = 1,
        reportDirectory: String,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.reportDirectory = reportDirectory
        self.updatedAt = updatedAt
    }
}

public enum AutomationReportEngine {
    public static func makeReport(
        snapshot: FocusTraceLocalSnapshot,
        reportDate: Date,
        generatedAt: Date = Date(),
        calendar: Calendar = .current,
        previousIssuedReport: AutomationReportArtifact? = nil
    ) -> AutomationDailyReport {
        let start = calendar.startOfDay(for: reportDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let effectiveNow = min(generatedAt, end)

        let activities = snapshot.activities.compactMap { activity -> ActivityRecord? in
            let activityEnd = activity.endedAt ?? effectiveNow
            guard activity.startedAt < end, activityEnd >= start else { return nil }
            return ActivityRecord(
                id: activity.id,
                app: activity.app,
                startedAt: max(activity.startedAt, start),
                endedAt: min(activityEnd, end),
                taskID: activity.taskID,
                focusSessionID: activity.focusSessionID,
                classification: activity.classification,
                source: activity.source
            )
        }
        let taskIntervals = snapshot.taskIntervals.compactMap { interval -> TaskIntervalRecord? in
            let intervalEnd = interval.endedAt ?? effectiveNow
            guard interval.startedAt < end, intervalEnd >= start else { return nil }
            return TaskIntervalRecord(
                id: interval.id,
                taskID: interval.taskID,
                startedAt: max(interval.startedAt, start),
                endedAt: min(intervalEnd, end),
                workflowSource: interval.workflowSource
            )
        }
        let interruptions = snapshot.interruptions.filter {
            $0.detectedAt >= start && $0.detectedAt < end
        }
        let sessions = snapshot.focusSessions.filter {
            $0.startedAt >= start && $0.startedAt < end && $0.endedAt != nil
        }
        let taskParkings = snapshot.taskParkings.filter {
            $0.parkedAt >= start && $0.parkedAt < end
        }
        let completedSessions = snapshot.focusSessions.filter { $0.endedAt != nil }
        let plan = snapshot.currentPlan
        let analysis = AdaptiveAnalyzer.analyze(
            activities: snapshot.activities,
            sessions: completedSessions,
            interruptions: snapshot.interruptions,
            currentPlan: plan,
            calendar: calendar
        )
        let coaching = DailyCoachEngine.analyze(
            snapshot: snapshot,
            reportDate: reportDate,
            generatedAt: generatedAt,
            calendar: calendar,
            previousIssuedRecommendation: previousIssuedReport?.recommendation,
            previousIssuedMetrics: previousIssuedReport?.normalized
        )
        let summary = MetricsEngine.dailySummary(
            activities: activities,
            taskIntervals: taskIntervals,
            interruptions: interruptions,
            taskParkings: taskParkings,
            now: effectiveNow
        )
        let transitionResult = WorkflowTransitionAuditEngine.makeAudit(
            tasks: snapshot.tasks,
            requirements: snapshot.requirements,
            taskIntervals: snapshot.taskIntervals,
            activities: snapshot.activities,
            markers: snapshot.markers,
            workflowTransitions: snapshot.workflowTransitions,
            range: start..<end,
            now: effectiveNow,
            calendar: calendar
        )
        let observationPlan = ObservationPlanEngine.makePlan(
            coaching: coaching,
            summary: summary,
            interventionAudit: WorkflowSwitchInterventionEngine.audit(
                transitions: snapshot.workflowTransitions,
                range: start..<end,
                now: effectiveNow
            )
        )

        return AutomationDailyReport(
            reportDate: start,
            reportCivilDate: civilDate(start, calendar: calendar),
            generatedAt: generatedAt,
            summary: summary,
            trainingCount: sessions.count,
            successfulTrainingCount: sessions.filter(\.isSuccessful).count,
            totalWorkdays: Set(snapshot.activities.map { calendar.startOfDay(for: $0.startedAt) }).count,
            totalCompletedSessions: completedSessions.count,
            currentPlan: plan,
            analysis: analysis,
            coaching: coaching,
            workflowContexts: transitionResult.contexts,
            transitionAudit: transitionResult.audit,
            observationPlan: observationPlan
        )
    }

    public static func markdown(
        for report: AutomationDailyReport,
        timeZone: TimeZone = .current
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.timeZone = timeZone

        let medianFocus = report.summary.medianFocusStreak
            .map { "\(Int(($0 / 60).rounded())) 分钟" } ?? "暂无"
        let returnLatency = report.summary.averageReturnLatency
            .map { "\(Int($0.rounded())) 秒" } ?? "暂无"

        var lines = [
            "# FocusTrace 每日回顾 — \(dateFormatter.string(from: report.reportDate))",
            "",
            "生成时间：\(timestampFormatter.string(from: report.generatedAt))",
            "",
            "## 今日聚合",
            "",
            "- 应用切换：\(report.summary.appSwitchCount) 次",
            "- 桌面工作流切换：\(report.summary.workflowSwitchCount) 次",
            "- 手动工作流切换：\(report.summary.taskSwitchCount) 次",
            "- 疑似 / 确认分心：\(report.summary.suspectedDistractionCount) / \(report.summary.confirmedDistractionCount) 次",
            "- 平均返回耗时：\(returnLatency)",
            "- 中位连续专注：\(medianFocus)",
            "- 训练：\(report.trainingCount) 次，成功 \(report.successfulTrainingCount) 次",
            "- 保存返回点 / 已返回：\(report.summary.taskParkingCount) / \(report.summary.resumedTaskCount) 次",
            "- 返回点平均恢复耗时：\(formatDuration(report.summary.averageTaskResumeLatency))",
            "- 当前计划：v\(report.currentPlan.version)，\(report.currentPlan.focusMinutes) 分钟 × 每日 \(report.currentPlan.sessionsPerDay) 次",
            "",
            "## 数据质量与归一化",
            "",
            "- 有效记录：\(formatMinutes(report.coaching.metrics.recordedMinutes))",
            "- 工作流归因：\(formatPercent(report.coaching.metrics.attributedRatio))（\(formatMinutes(report.coaching.metrics.attributedMinutes))）",
            "- 应用切换率：\(formatDecimal(report.coaching.metrics.appSwitchesPerHour)) 次/小时",
            "- 工作流切换率：\(formatDecimal(report.coaching.metrics.workflowSwitchesPerHour)) 次/小时",
            "- 行为结论可信：\(report.coaching.quality.isReliableForBehavior ? "是" : "否")",
        ]
        if report.coaching.quality.warnings.isEmpty {
            lines.append("- 数据质量提醒：无")
        } else {
            for warning in report.coaching.quality.warnings {
                lines.append("- 数据质量提醒：\(clean(warning))")
            }
        }
        lines.append(contentsOf: [
            "",
            "## 今日观察配置",
            "",
            "- 配置版本：v\(report.observationPlan.version)",
            "- 来源：\(observationPlanSource(report.observationPlan.source))",
            "- 可比历史：\(report.observationPlan.lookbackWorkdays) 个工作日",
            "- 原始采集：固定的最小事件驱动集合；以下比例是分析配额，不是抽样率"
        ])
        for allocation in report.observationPlan.allocations {
            lines.append(
                "- \(observationLensTitle(allocation.lens))："
                    + "\(allocation.percent)%（\(clean(allocation.reason))）"
            )
        }
        lines.append(
            "- 提醒策略：\(clean(report.observationPlan.interventionRecommendation))"
        )
        lines.append(contentsOf: [
            "",
            "## 工作流跳转审计",
            "",
            "- 协议：v\(report.transitionAudit.protocolVersion ?? 0)，数据来源 \(report.transitionAudit.dataSource ?? "legacyInferred")",
            "- 最终跳转：\(report.transitionAudit.finalSwitches ?? (report.transitionAudit.reasonedSwitches + report.transitionAudit.unreasonedSwitches)) 次",
            "- 主动说明 / 超时 / 自动：\(report.transitionAudit.explicitReasonSwitches ?? 0) / \(report.transitionAudit.timedOutSwitches ?? 0) / \(report.transitionAudit.automaticSwitches ?? 0) 次",
            "- 已说明原因的最终跳转：\(report.transitionAudit.reasonedSwitches) 次",
            "- 未说明原因的工作流跳转：\(report.transitionAudit.unreasonedSwitches) 次",
            "- 导航后回到原工作流：\(report.transitionAudit.cancelledNavigations) 次",
            "- 无法解析导航：\(report.transitionAudit.unresolvedNavigations ?? 0) 次",
            "- 主动原因覆盖率：\(report.transitionAudit.explicitReasonCoverage.map(formatPercent) ?? "暂无")",
            "- 高频切换段 / 实际确认：\(report.transitionAudit.frequentSwitchEpisodes ?? 0) / \(report.transitionAudit.interventionPrompts ?? 0) 次",
            "- 确认后 10 分钟稳定率：\(report.transitionAudit.postPromptQuietRate.map(formatPercent) ?? "暂无")（完整观察窗 \(report.transitionAudit.assessedInterventionPrompts ?? 0) 次）",
            "- 原因分布：\(reasonSummary(report.transitionAudit.reasonCounts))"
        ])
        if report.transitionAudit.routes.isEmpty {
            lines.append("- 路线：暂无可审计的最终跳转")
        } else {
            for route in report.transitionAudit.routes {
                let duration = route.medianDestinationMinutes.map {
                    "\(formatDecimal($0)) 分钟"
                } ?? "暂无"
                lines.append(
                    "- \(clean(route.fromWorkflow)) → \(clean(route.toWorkflow))："
                        + "\(route.count) 次；原因 \(reasonSummary(route.reasonCounts))；"
                        + "目的工作流停留中位数 \(duration)；"
                        + "30 分钟内返回 \(route.returnedWithin30Minutes)/\(route.count)"
                )
            }
        }
        lines.append("")
        lines.append("### 当日工作上下文")
        lines.append("")
        if report.workflowContexts.isEmpty {
            lines.append("- 暂无已归因工作流")
        } else {
            for context in report.workflowContexts {
                let requirements = context.openRequirementTitles.isEmpty
                    ? "无已关联未完成需求"
                    : context.openRequirementTitles.map(clean).joined(separator: "；")
                lines.append(
                    "- \(clean(context.workflowTitle))：\(formatMinutes(context.activeMinutes))；"
                        + "关联需求：\(requirements)"
                )
            }
        }
        lines.append(contentsOf: [
            "",
            "## 近 7 个有效工作日趋势",
            "",
            "- 可比样本：\(report.coaching.trend.baselineDays) 天",
            "- 应用切换率变化：\(formatDelta(report.coaching.trend.appSwitchRateDeltaPercent))",
            "- 工作流切换率变化：\(formatDelta(report.coaching.trend.workflowSwitchRateDeltaPercent))",
            "- 工作流归因率变化：\(formatPointDelta(report.coaching.trend.attributedRatioDeltaPoints))",
            "- 中位连续专注变化：\(formatMinuteDelta(report.coaching.trend.medianFocusDeltaMinutes))",
            ""
        ])
        if let evaluation = report.coaching.previousRecommendationEvaluation {
            lines.append(contentsOf: [
                "## 上一项训练验证",
                "",
                "- 状态：\(evaluationStatus(evaluation.status))",
                "- \(clean(evaluation.title))",
                "- 证据：\(clean(evaluation.evidence))",
                ""
            ])
        }
        let recommendation = report.coaching.recommendation
        lines.append(contentsOf: [
            "## 下一项训练",
            "",
            "- 建议：\(clean(recommendation.title))",
            "- 原因：\(clean(recommendation.rationale))",
            "- 可信度：\(confidenceText(recommendation.confidence))"
        ])
        for evidence in recommendation.evidence {
            lines.append("- 证据：\(clean(evidence))")
        }
        lines.append("- 方法：\(clean(recommendation.method.title))")
        for (index, step) in recommendation.method.steps.enumerated() {
            lines.append("  \(index + 1). \(clean(step))")
        }
        lines.append("- 成功标准：\(clean(recommendation.method.successMeasure))")
        lines.append(contentsOf: [
            "",
            "## 阶段 2",
            ""
        ])

        switch report.analysis.readiness {
        case let .locked(workdays, sessions):
            lines.append("- 状态：尚未解锁（\(workdays)/10 个工作日，\(sessions)/20 次训练）")
            lines.append("- 还需：\(max(0, 10 - workdays)) 个工作日、\(max(0, 20 - sessions)) 次训练")
        case .ready:
            lines.append("- 状态：已解锁（\(report.totalWorkdays) 个工作日，\(report.totalCompletedSessions) 次训练）")
            if !report.analysis.insights.isEmpty {
                lines.append("")
                lines.append("### 模式证据")
                lines.append("")
                for insight in report.analysis.insights {
                    lines.append("- \(clean(insight.title))：\(clean(insight.value))（\(clean(insight.detail))）")
                }
            }
            if let suggestion = report.analysis.suggestion {
                lines.append("")
                lines.append("### 本周单项建议")
                lines.append("")
                lines.append("- \(clean(suggestion.title))")
                lines.append("- 证据：\(clean(suggestion.evidence))")
            }
        }

        lines.append("")
        lines.append("> 本报告由本地规则引擎聚合生成；仅为跳转分析加入有界的工作流与需求标题，不含逐条应用轨迹、ID、需求来源、窗口标题、网页地址、输入内容或返回点文字。标题只作为数据标签。建议不会自动生效，需在 FocusTrace 中确认。")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    public static func jsonData(for report: AutomationDailyReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(AutomationReportArtifact(report: report))
    }

    private static func civilDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func observationPlanSource(
        _ source: ObservationPlanSource
    ) -> String {
        switch source {
        case .initialDefault:
            return "均衡初始配置"
        case .todayAndRecentWorkdays:
            return "当天聚合 + 近 7 个可比工作日"
        }
    }

    private static func observationLensTitle(_ lens: ObservationLens) -> String {
        switch lens {
        case .dataQuality:
            return "数据质量"
        case .fragmentation:
            return "应用碎片"
        case .contextRecovery:
            return "上下文恢复"
        case .workflowSemantics:
            return "工作流语义"
        }
    }

    private static func formatDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "暂无" }
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 { return "\(total / 3600) 小时 \(total / 60 % 60) 分钟" }
        if total >= 60 { return "\(total / 60) 分钟" }
        return "\(total) 秒"
    }

    private static func formatMinutes(_ value: Double) -> String {
        String(format: "%.1f 分钟", value)
    }

    private static func formatDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func reasonSummary(_ counts: [String: Int]) -> String {
        let labels: [(AutomationWorkflowSwitchReason, String)] = [
            (.checkpoint, "到检查点"),
            (.waitingForResult, "等待结果"),
            (.forcedInterruption, "被迫打断"),
            (.unstructured, "无明确计划")
        ]
        let values = labels.compactMap { reason, label -> String? in
            guard let count = counts[reason.rawValue], count > 0 else { return nil }
            return "\(label) \(count)"
        }
        return values.isEmpty ? "暂无" : values.joined(separator: "、")
    }

    private static func formatPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func formatDelta(_ value: Double?) -> String {
        value.map { String(format: "%+.0f%%", $0) } ?? "样本不足"
    }

    private static func formatPointDelta(_ value: Double?) -> String {
        value.map { String(format: "%+.0f 个百分点", $0) } ?? "样本不足"
    }

    private static func formatMinuteDelta(_ value: Double?) -> String {
        value.map { String(format: "%+.1f 分钟", $0) } ?? "样本不足"
    }

    private static func confidenceText(_ value: DailyCoachConfidence) -> String {
        switch value {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }

    private static func evaluationStatus(_ value: DailyCoachEvaluationStatus) -> String {
        switch value {
        case .improved: return "已改善"
        case .needsAdjustment: return "需调整"
        case .notRun: return "未执行"
        case .insufficientData: return "数据不足"
        }
    }
}

private struct PersistedTask: Decodable {
    let id: UUID
    let title: String
    let expectedOutcome: String?
    let allowedBundleIDs: [String]?

    var record: TaskRecord {
        TaskRecord(
            id: id,
            title: title,
            expectedOutcome: expectedOutcome ?? "",
            allowedBundleIDs: Set(allowedBundleIDs ?? [])
        )
    }
}

private struct PersistedTaskInterval: Decodable {
    let id: UUID
    let taskID: UUID
    let startedAt: Date
    let endedAt: Date?
    let workflowSourceRaw: String?

    var record: TaskIntervalRecord {
        TaskIntervalRecord(
            id: id,
            taskID: taskID,
            startedAt: startedAt,
            endedAt: endedAt,
            workflowSource: workflowSourceRaw.flatMap(WorkflowIntervalSource.init(rawValue:)) ?? .manual
        )
    }
}

private struct PersistedActivity: Decodable {
    let id: UUID
    let appName: String
    let bundleID: String
    let startedAt: Date
    let endedAt: Date?
    let taskID: UUID?
    let focusSessionID: UUID?
    let classificationRaw: String
    let sourceRaw: String

    var record: ActivityRecord {
        ActivityRecord(
            id: id,
            app: AppIdentity(bundleID: bundleID, name: appName),
            startedAt: startedAt,
            endedAt: endedAt,
            taskID: taskID,
            focusSessionID: focusSessionID,
            classification: ActivityClassification(rawValue: classificationRaw) ?? .allowed,
            source: ActivityEventSource(rawValue: sourceRaw) ?? .appActivation
        )
    }
}

private struct PersistedFocusSession: Decodable {
    let id: UUID
    let taskID: UUID
    let startedAt: Date
    let endedAt: Date?
    let targetSeconds: Int
    let outcomeRaw: String
    let difficulty: Int?
    let confirmedDistractionCount: Int
    let pausedAt: Date?
    let accumulatedPausedSeconds: TimeInterval?

    var record: FocusSessionRecord {
        FocusSessionRecord(
            id: id,
            taskID: taskID,
            startedAt: startedAt,
            endedAt: endedAt,
            targetSeconds: targetSeconds,
            outcome: FocusOutcome(rawValue: outcomeRaw) ?? .pending,
            difficulty: difficulty,
            confirmedDistractionCount: confirmedDistractionCount,
            pausedSeconds: max(0, accumulatedPausedSeconds ?? 0) + (pausedAt.map {
                max(0, (endedAt ?? $0).timeIntervalSince($0))
            } ?? 0)
        )
    }
}

private struct PersistedInterruption: Decodable {
    let id: UUID
    let activityID: UUID
    let focusSessionID: UUID
    let taskID: UUID
    let appName: String
    let bundleID: String
    let detectedAt: Date
    let resolvedAt: Date?
    let resolutionRaw: String

    var record: InterruptionRecord {
        InterruptionRecord(
            id: id,
            activityID: activityID,
            focusSessionID: focusSessionID,
            taskID: taskID,
            app: AppIdentity(bundleID: bundleID, name: appName),
            detectedAt: detectedAt,
            resolvedAt: resolvedAt,
            resolution: InterruptionResolution(rawValue: resolutionRaw) ?? .unresolved
        )
    }
}

private struct PersistedTrainingPlan: Decodable {
    let id: UUID
    let version: Int
    let effectiveAt: Date
    let focusMinutes: Int
    let sessionsPerDay: Int
    let breakMinutes: Int
    let reminderThresholdSeconds: Int
    let reason: String
    let previousPlanID: UUID?

    var record: TrainingPlanRecord {
        TrainingPlanRecord(
            id: id,
            version: version,
            effectiveAt: effectiveAt,
            focusMinutes: focusMinutes,
            sessionsPerDay: sessionsPerDay,
            breakMinutes: breakMinutes,
            reminderThresholdSeconds: reminderThresholdSeconds,
            reason: reason,
            previousPlanID: previousPlanID
        )
    }
}

private struct PersistedTimelineMarker: Decodable {
    let id: UUID
    let date: Date
    let kindRaw: String
    let taskID: UUID?

    var record: TimelineMarkerRecord {
        TimelineMarkerRecord(
            id: id,
            date: date,
            kind: TimelineMarkerKind(rawValue: kindRaw) ?? .activeSpaceChanged,
            taskID: taskID
        )
    }
}

private struct PersistedWorkflowTransition: Decodable {
    let id: UUID
    let sourceRaw: String
    let navigationStartedAt: Date
    let settledAt: Date
    let resolvedAt: Date
    let originKindRaw: String
    let originWorkflowID: UUID?
    let destinationKindRaw: String
    let destinationWorkflowID: UUID?
    let outcomeRaw: String
    let reasonRaw: String?
    let interventionTriggerRaw: String?
    let navigationEventCount: Int

    var record: WorkflowTransitionRecord {
        WorkflowTransitionRecord(
            id: id,
            source: WorkflowTransitionSource(rawValue: sourceRaw) ?? .space,
            navigationStartedAt: navigationStartedAt,
            settledAt: settledAt,
            resolvedAt: resolvedAt,
            origin: WorkflowTransitionEndpoint(
                kind: WorkflowTransitionEndpointKind(rawValue: originKindRaw)
                    ?? .unknown,
                workflowID: originWorkflowID
            ),
            destination: WorkflowTransitionEndpoint(
                kind: WorkflowTransitionEndpointKind(
                    rawValue: destinationKindRaw
                ) ?? .unknown,
                workflowID: destinationWorkflowID
            ),
            outcome: WorkflowTransitionOutcome(rawValue: outcomeRaw)
                ?? .unresolved,
            reason: reasonRaw.flatMap(SpaceSwitchReason.init(rawValue:)),
            interventionTrigger: interventionTriggerRaw.flatMap(
                WorkflowInterventionTrigger.init(rawValue:)
            ),
            navigationEventCount: navigationEventCount
        )
    }
}

private struct PersistedTaskParking: Decodable {
    let id: UUID
    let taskID: UUID
    let parkedAt: Date
    let resumeCue: String
    let remindAt: Date?
    let switchedToTaskID: UUID?
    let resumedAt: Date?
    let dismissedAt: Date?
    let reminderSentAt: Date?

    var record: TaskParkingRecord {
        TaskParkingRecord(
            id: id,
            taskID: taskID,
            parkedAt: parkedAt,
            resumeCue: resumeCue,
            remindAt: remindAt,
            switchedToTaskID: switchedToTaskID,
            resumedAt: resumedAt,
            dismissedAt: dismissedAt,
            reminderSentAt: reminderSentAt
        )
    }
}

private struct PersistedRequirement: Decodable {
    let id: UUID
    let title: String
    let source: String?
    let capturedAt: Date
    let dueDate: Date?
    let importanceRaw: String?
    let reminderSentAt: Date?
    let planningVersion: Int?
    let priorityRaw: String?
    let statusRaw: String?
    let workflowID: UUID?
    let completedAt: Date?

    var record: RequirementRecord {
        RequirementRecord(
            id: id,
            title: title,
            source: source ?? "",
            capturedAt: capturedAt,
            dueDate: dueDate,
            importance: importanceRaw.flatMap(RequirementImportance.init(rawValue:))
                ?? .normal,
            reminderSentAt: reminderSentAt,
            planningVersion: planningVersion ?? 0,
            priority: priorityRaw.flatMap(RequirementPriority.init(rawValue:))
                ?? .unplanned,
            status: statusRaw.flatMap(RequirementStatus.init(rawValue:))
                ?? .inbox,
            workflowID: workflowID,
            completedAt: completedAt
        )
    }
}
