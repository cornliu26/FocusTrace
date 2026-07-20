import Foundation

/// A read-only view of FocusTrace's on-disk snapshot. It deliberately exposes
/// domain records rather than persistence implementation types so local tools
/// can share the analysis rules without importing AppKit or SwiftUI.
public struct FocusTraceLocalSnapshot: Decodable, Sendable {
    public let taskIntervals: [TaskIntervalRecord]
    public let activities: [ActivityRecord]
    public let focusSessions: [FocusSessionRecord]
    public let interruptions: [InterruptionRecord]
    public let trainingPlans: [TrainingPlanRecord]
    public let taskParkings: [TaskParkingRecord]

    public init(
        taskIntervals: [TaskIntervalRecord] = [],
        activities: [ActivityRecord] = [],
        focusSessions: [FocusSessionRecord] = [],
        interruptions: [InterruptionRecord] = [],
        trainingPlans: [TrainingPlanRecord] = [],
        taskParkings: [TaskParkingRecord] = []
    ) {
        self.taskIntervals = taskIntervals
        self.activities = activities
        self.focusSessions = focusSessions
        self.interruptions = interruptions
        self.trainingPlans = trainingPlans
        self.taskParkings = taskParkings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
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
        taskParkings = try container.decodeIfPresent([PersistedTaskParking].self, forKey: .taskParkings)?
            .map(\.record) ?? []
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
        case taskIntervals
        case activities
        case focusSessions
        case interruptions
        case trainingPlans
        case taskParkings
    }
}

public struct AutomationDailyReport: Equatable, Sendable {
    public let reportDate: Date
    public let generatedAt: Date
    public let summary: DailySummary
    public let trainingCount: Int
    public let successfulTrainingCount: Int
    public let totalWorkdays: Int
    public let totalCompletedSessions: Int
    public let currentPlan: TrainingPlanRecord
    public let analysis: AnalysisResult

    public init(
        reportDate: Date,
        generatedAt: Date,
        summary: DailySummary,
        trainingCount: Int,
        successfulTrainingCount: Int,
        totalWorkdays: Int,
        totalCompletedSessions: Int,
        currentPlan: TrainingPlanRecord,
        analysis: AnalysisResult
    ) {
        self.reportDate = reportDate
        self.generatedAt = generatedAt
        self.summary = summary
        self.trainingCount = trainingCount
        self.successfulTrainingCount = successfulTrainingCount
        self.totalWorkdays = totalWorkdays
        self.totalCompletedSessions = totalCompletedSessions
        self.currentPlan = currentPlan
        self.analysis = analysis
    }
}

public enum AutomationReportEngine {
    public static func makeReport(
        snapshot: FocusTraceLocalSnapshot,
        reportDate: Date,
        generatedAt: Date = Date(),
        calendar: Calendar = .current
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

        return AutomationDailyReport(
            reportDate: start,
            generatedAt: generatedAt,
            summary: MetricsEngine.dailySummary(
                activities: activities,
                taskIntervals: taskIntervals,
                interruptions: interruptions,
                taskParkings: taskParkings,
                now: effectiveNow
            ),
            trainingCount: sessions.count,
            successfulTrainingCount: sessions.filter(\.isSuccessful).count,
            totalWorkdays: Set(snapshot.activities.map { calendar.startOfDay(for: $0.startedAt) }).count,
            totalCompletedSessions: completedSessions.count,
            currentPlan: plan,
            analysis: analysis
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
            "- 手动任务切换：\(report.summary.taskSwitchCount) 次",
            "- 疑似 / 确认分心：\(report.summary.suspectedDistractionCount) / \(report.summary.confirmedDistractionCount) 次",
            "- 平均返回耗时：\(returnLatency)",
            "- 中位连续专注：\(medianFocus)",
            "- 训练：\(report.trainingCount) 次，成功 \(report.successfulTrainingCount) 次",
            "- 任务停车 / 已返回：\(report.summary.taskParkingCount) / \(report.summary.resumedTaskCount) 次",
            "- 停车任务平均恢复耗时：\(formatDuration(report.summary.averageTaskResumeLatency))",
            "- 当前计划：v\(report.currentPlan.version)，\(report.currentPlan.focusMinutes) 分钟 × 每日 \(report.currentPlan.sessionsPerDay) 次",
            "",
            "## 阶段 2",
            ""
        ]

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
        lines.append("> 本报告由本地规则引擎从原始日志聚合生成；不含逐条应用轨迹、窗口标题、网页地址或输入内容。建议不会自动生效，需在 FocusTrace 中确认。")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func formatDuration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "暂无" }
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 { return "\(total / 3600) 小时 \(total / 60 % 60) 分钟" }
        if total >= 60 { return "\(total / 60) 分钟" }
        return "\(total) 秒"
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
