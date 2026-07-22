import Foundation

public enum AnalysisReadiness: Equatable, Sendable {
    case locked(workdays: Int, sessions: Int)
    case ready
}

public enum SuggestionKind: String, Codable, Sendable {
    case increaseDuration
    case decreaseDuration
    case highRiskApp
    case preferredTime
    case maintainPlan
}

public struct AnalysisSuggestion: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: SuggestionKind
    public let title: String
    public let evidence: String
    public let proposedFocusMinutes: Int?

    public init(
        id: UUID = UUID(),
        kind: SuggestionKind,
        title: String,
        evidence: String,
        proposedFocusMinutes: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.evidence = evidence
        self.proposedFocusMinutes = proposedFocusMinutes
    }
}

public struct AnalysisInsight: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let value: String
    public let detail: String

    public init(id: String, title: String, value: String, detail: String) {
        self.id = id
        self.title = title
        self.value = value
        self.detail = detail
    }
}

public struct AnalysisResult: Equatable, Sendable {
    public let readiness: AnalysisReadiness
    public let suggestion: AnalysisSuggestion?
    public let insights: [AnalysisInsight]

    public init(
        readiness: AnalysisReadiness,
        suggestion: AnalysisSuggestion?,
        insights: [AnalysisInsight] = []
    ) {
        self.readiness = readiness
        self.suggestion = suggestion
        self.insights = insights
    }
}

public enum AdaptiveAnalyzer {
    public static func analyze(
        activities: [ActivityRecord],
        sessions: [FocusSessionRecord],
        interruptions: [InterruptionRecord],
        currentPlan: TrainingPlanRecord,
        calendar: Calendar = .current
    ) -> AnalysisResult {
        let workdays = Set(activities.map { calendar.startOfDay(for: $0.startedAt) }).count
        guard workdays >= 10, sessions.count >= 20 else {
            return AnalysisResult(readiness: .locked(workdays: workdays, sessions: sessions.count), suggestion: nil)
        }

        let confirmed = interruptions.filter {
            $0.resolution == .returnedToTask || $0.resolution == .endedSession
        }
        let necessary = interruptions.filter { $0.resolution == .markedNecessary }
        let sortedActivities = activities.sorted { $0.startedAt < $1.startedAt }
        let activityIndices = Dictionary(uniqueKeysWithValues: sortedActivities.enumerated().map { ($0.element.id, $0.offset) })
        var transitionCounts: [String: (from: String, to: String, count: Int)] = [:]
        for interruption in confirmed {
            guard let index = activityIndices[interruption.activityID], index > 0 else { continue }
            let previous = sortedActivities[index - 1]
            let current = sortedActivities[index]
            guard previous.taskID == current.taskID else { continue }
            let key = "\(previous.app.bundleID)->\(current.app.bundleID)"
            let existing = transitionCounts[key]
            transitionCounts[key] = (
                from: previous.app.name,
                to: current.app.name,
                count: (existing?.count ?? 0) + 1
            )
        }

        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let distractionMinutes = confirmed.compactMap { interruption -> Double? in
            guard let session = sessionByID[interruption.focusSessionID] else { return nil }
            return max(0, interruption.detectedAt.timeIntervalSince(session.startedAt) / 60)
        }
        let returnLatencies = interruptions.compactMap { interruption -> TimeInterval? in
            guard interruption.resolution == .returnedToTask, let resolvedAt = interruption.resolvedAt else { return nil }
            return max(0, resolvedAt.timeIntervalSince(interruption.detectedAt))
        }

        let durationBuckets = Dictionary(grouping: sessions, by: { $0.targetSeconds / 60 })
        let bestDuration = durationBuckets
            .filter { $0.value.count >= 3 }
            .map { minutes, values in
                (minutes, Double(values.filter(\.isSuccessful).count) / Double(values.count), values.count)
            }
            .max { $0.1 < $1.1 }

        var insights: [AnalysisInsight] = []
        if let topTransition = transitionCounts.values.max(by: { $0.count < $1.count }) {
            insights.append(AnalysisInsight(
                id: "transition",
                title: "高风险转换",
                value: "\(topTransition.from) → \(topTransition.to)",
                detail: "\(topTransition.count) 次确认分心"
            ))
        }
        if let medianMinute = median(distractionMinutes) {
            insights.append(AnalysisInsight(
                id: "distraction-minute",
                title: "典型偏离时点",
                value: "第 \(max(1, Int(medianMinute.rounded()))) 分钟",
                detail: "确认分心相对会话开始的中位数"
            ))
        }
        if !returnLatencies.isEmpty {
            let average = returnLatencies.reduce(0, +) / Double(returnLatencies.count)
            insights.append(AnalysisInsight(
                id: "return-latency",
                title: "平均返回耗时",
                value: String(format: "%.0f 秒", average),
                detail: "从提醒到确认返回工作流"
            ))
        }
        if let bestDuration {
            insights.append(AnalysisInsight(
                id: "best-duration",
                title: "当前最佳训练长度",
                value: "\(bestDuration.0) 分钟",
                detail: "\(bestDuration.2) 次样本，成功率 \(Int(bestDuration.1 * 100))%"
            ))
        }
        if let topNecessary = Dictionary(grouping: necessary, by: { $0.app }).mapValues(\.count).max(by: { $0.value < $1.value }) {
            insights.append(AnalysisInsight(
                id: "necessary-app",
                title: "经常属于必要切换",
                value: topNecessary.key.name,
                detail: "\(topNecessary.value) 次标记为本工作流所需"
            ))
        }

        if let transition = transitionCounts.values.max(by: { $0.count < $1.count }), transition.count >= 3 {
            return AnalysisResult(
                readiness: .ready,
                suggestion: AnalysisSuggestion(
                    kind: .highRiskApp,
                    title: "关注 \(transition.from) → \(transition.to) 的切换",
                    evidence: "该转换出现了 \(transition.count) 次确认分心。下一个周期只为这条转换增加一次停顿确认。"
                ),
                insights: insights
            )
        }
        let appCounts = Dictionary(grouping: confirmed, by: { $0.app })
            .mapValues(\.count)
        if let risk = appCounts.max(by: { $0.value < $1.value }), risk.value >= 3 {
            return AnalysisResult(
                readiness: .ready,
                suggestion: AnalysisSuggestion(
                    kind: .highRiskApp,
                    title: "为 \(risk.key.name) 增加切换摩擦",
                    evidence: "最近数据中有 \(risk.value) 次确认分心由该应用触发。先在下一个 5 次训练周期只调整这一项。"
                ),
                insights: insights
            )
        }

        let lastFive = Array(sessions.sorted { $0.startedAt < $1.startedAt }.suffix(5))
        if let adjustment = TrainingEngine.progression(
            currentMinutes: currentPlan.focusMinutes,
            lastFive: lastFive
        ) {
            switch adjustment {
            case let .increase(minutes) where minutes != currentPlan.focusMinutes:
                return AnalysisResult(
                    readiness: .ready,
                    suggestion: AnalysisSuggestion(
                        kind: .increaseDuration,
                        title: "专注训练增加到 \(minutes) 分钟",
                        evidence: "最近 5 次训练至少 4 次成功。",
                        proposedFocusMinutes: minutes
                    ),
                    insights: insights
                )
            case let .decrease(minutes) where minutes != currentPlan.focusMinutes:
                return AnalysisResult(
                    readiness: .ready,
                    suggestion: AnalysisSuggestion(
                        kind: .decreaseDuration,
                        title: "专注训练降低到 \(minutes) 分钟",
                        evidence: "最近 5 次训练成功不超过 2 次。",
                        proposedFocusMinutes: minutes
                    ),
                    insights: insights
                )
            default:
                break
            }
        }

        let buckets = Dictionary(grouping: sessions) { session -> String in
            let hour = calendar.component(.hour, from: session.startedAt)
            switch hour {
            case 5..<12: return "上午"
            case 12..<18: return "下午"
            default: return "晚上"
            }
        }
        let qualified = buckets.compactMap { name, values -> (String, Double, Int)? in
            guard values.count >= 5 else { return nil }
            let rate = Double(values.filter(\.isSuccessful).count) / Double(values.count)
            return (name, rate, values.count)
        }
        if qualified.count >= 2,
           let best = qualified.max(by: { $0.1 < $1.1 }),
           let worst = qualified.min(by: { $0.1 < $1.1 }),
           best.1 - worst.1 >= 0.2 {
            return AnalysisResult(
                readiness: .ready,
                suggestion: AnalysisSuggestion(
                    kind: .preferredTime,
                    title: "优先在\(best.0)安排训练",
                    evidence: "\(best.0)成功率为 \(Int(best.1 * 100))%，比\(worst.0)高至少 20 个百分点。"
                ),
                insights: insights
            )
        }

        return AnalysisResult(
            readiness: .ready,
            suggestion: AnalysisSuggestion(
                kind: .maintainPlan,
                title: "本周保持当前计划",
                evidence: "现有数据没有支持单项调整的稳定差异；继续积累一个 5 次训练周期。"
            ),
            insights: insights
        )
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
