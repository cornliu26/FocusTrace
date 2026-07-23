import SwiftUI
import FocusTraceCore

struct ReviewView: View {
    @ObservedObject var state: ApplicationState
    @State private var showPlanHistory = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dailySummary
                dailyCoaching
                if hasUnresolvedReview {
                    unresolvedReview
                }
                phaseTwoAnalysis
                trainingHistory
            }
            .focusTracePageContent()
        }
        .focusTraceScreen()
    }

    private var dailyCoaching: some View {
        let analysis = state.selectedCoachingAnalysis
        let recommendation = analysis.recommendation
        return GroupBox("每日分析") {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    MetricCard(
                        title: "有效记录",
                        value: String(format: "%.0f 分", analysis.metrics.recordedMinutes),
                        detail: analysis.quality.isReliableForBehavior ? "可用于行为比较" : "先看数据质量"
                    )
                    MetricCard(
                        title: "工作流归因",
                        value: percent(analysis.metrics.attributedRatio),
                        detail: "可靠门槛 70%"
                    )
                    MetricCard(
                        title: "应用切换率",
                        value: String(format: "%.1f/时", analysis.metrics.appSwitchesPerHour),
                        detail: trendText(analysis.trend.appSwitchRateDeltaPercent)
                    )
                    MetricCard(
                        title: "工作流切换率",
                        value: String(format: "%.1f/时", analysis.metrics.workflowSwitchesPerHour),
                        detail: trendText(analysis.trend.workflowSwitchRateDeltaPercent)
                    )
                }

                if !analysis.quality.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(analysis.quality.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if let evaluation = analysis.previousRecommendationEvaluation {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: evaluationIcon(evaluation.status))
                            .foregroundStyle(evaluationColor(evaluation.status))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("上一项训练：\(evaluation.title)")
                                .font(.headline)
                            Text(evaluation.evidence)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(evaluationColor(evaluation.status).opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                }

                Divider()

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recommendation.title)
                            .font(.title3.bold())
                        Text(recommendation.rationale)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("可信度：\(confidenceText(recommendation.confidence))")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.1), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(recommendation.evidence, id: \.self) { evidence in
                        Label(evidence, systemImage: "chart.bar.xaxis")
                            .font(.callout)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(recommendation.method.title)
                        .font(.headline)
                    ForEach(Array(recommendation.method.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 9) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .frame(width: 22, height: 22)
                                .background(.blue.opacity(0.12), in: Circle())
                            Text(step).font(.callout)
                        }
                    }
                    Label("成功标准：\(recommendation.method.successMeasure)", systemImage: "checkmark.seal")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.blue)
                }

                if Calendar.current.isDateInToday(state.selectedDate),
                   let buttonTitle = actionButtonTitle(recommendation.action) {
                    Button(buttonTitle) {
                        perform(recommendation.action)
                    }
                    .buttonStyle(FocusTracePrimaryButtonStyle())
                }
            }
            .padding(8)
        }
    }

    private var hasUnresolvedReview: Bool {
        state.selectedInterruptions.contains { $0.resolution == .unresolved }
    }

    private var dailySummary: some View {
        let summary = state.selectedSummary
        return GroupBox("每日回顾") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    FocusTraceDateNavigator(selection: $state.selectedDate)
                    Spacer()
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    MetricCard(title: "应用切换", value: "\(summary.appSwitchCount)", detail: "原始切换")
                    MetricCard(
                        title: "工作流 / 手动切换",
                        value: "\(summary.workflowSwitchCount) / \(summary.taskSwitchCount)",
                        detail: "桌面识别 / 主动切换"
                    )
                    MetricCard(title: "疑似分心", value: "\(summary.suspectedDistractionCount)", detail: "等待确认")
                    MetricCard(title: "确认分心", value: "\(summary.confirmedDistractionCount)", detail: "用户确认")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    MetricCard(title: "挂起工作流", value: "\(summary.taskParkingCount)", detail: "有意保存恢复线索")
                    MetricCard(title: "已返回", value: "\(summary.resumedTaskCount)", detail: "根据恢复线索继续")
                    MetricCard(
                        title: "平均恢复耗时",
                        value: summary.averageTaskResumeLatency.map(duration) ?? "—",
                        detail: "从挂起到继续"
                    )
                }

                if !summary.appDurations.isEmpty {
                    Text("应用时间分布").font(.headline)
                    ForEach(summary.appDurations.sorted(by: { $0.value > $1.value }).prefix(8), id: \.key) { app, seconds in
                        HStack {
                            Text(app).lineLimit(1)
                            Spacer()
                            Text(duration(seconds)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private var unresolvedReview: some View {
        let unresolved = state.selectedInterruptions.filter { $0.resolution == .unresolved }
        return GroupBox("待确认的疑似分心") {
            if unresolved.isEmpty {
                Label("当天没有待确认事件", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            } else {
                VStack(spacing: 0) {
                    ForEach(unresolved) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(item.appName) · \(state.taskName(for: item.taskID))")
                                    .font(.headline)
                                Text(item.detectedAt, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("必要切换") { state.markNecessary(interruptionID: item.id) }
                            Button("确认为分心") { state.resolveInterruption(item.id, as: .returnedToTask) }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                        }
                        .padding(.vertical, 10)
                        if item.id != unresolved.last?.id { Divider() }
                    }
                }
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private var phaseTwoAnalysis: some View {
        GroupBox("阶段 2 · 针对性分析") {
            VStack(alignment: .leading, spacing: 12) {
                switch state.analysisResult.readiness {
                case let .locked(workdays, sessions):
                    Label("需要至少 10 个工作日和 20 次训练", systemImage: "lock")
                        .font(.headline)
                    ProgressView(value: Double(min(workdays, 10)), total: 10) {
                        Text("工作日 \(workdays)/10")
                    }
                    ProgressView(value: Double(min(sessions, 20)), total: 20) {
                        Text("训练 \(sessions)/20")
                    }
                    Text("数据不足时只展示描述性统计，不生成个性化判断。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(phaseTwoNextStep(workdays: workdays, sessions: sessions))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.blue)
                case .ready:
                    if !state.analysisResult.insights.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(state.analysisResult.insights) { insight in
                                MetricCard(title: insight.title, value: insight.value, detail: insight.detail)
                            }
                        }
                    }
                    if let suggestion = state.analysisResult.suggestion {
                        Label(suggestion.title, systemImage: "lightbulb.max")
                            .font(.headline)
                        Text(suggestion.evidence).foregroundStyle(.secondary)
                        Text("一次只改变一个变量，并至少运行 5 次训练后再评估。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if suggestion.kind != .maintainPlan {
                            Button("采用为下一版计划") {
                                state.applyAnalysisSuggestion(suggestion)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var trainingHistory: some View {
        GroupBox {
            DisclosureGroup("训练计划版本（\(state.trainingPlans.count)）", isExpanded: $showPlanHistory) {
            VStack(spacing: 0) {
                ForEach(state.trainingPlans.sorted(by: { $0.version > $1.version })) { plan in
                    HStack(alignment: .top) {
                        Text("v\(plan.version)")
                            .font(.headline.monospacedDigit())
                            .frame(width: 42, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(plan.focusMinutes) 分钟专注 · \(plan.breakMinutes) 分钟休息 · 每日 \(plan.sessionsPerDay) 次")
                            Text(plan.reason).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(plan.effectiveAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 9)
                    if plan.id != state.trainingPlans.min(by: { $0.version < $1.version })?.id { Divider() }
                }
                if state.trainingPlans.count >= 2 {
                    HStack {
                        Button("回退到上一版本") { state.revertToPreviousPlan() }
                        Spacer()
                    }
                    .padding(.top, 10)
                }
            }
            .padding(8)
            }
        }
    }

    private func phaseTwoNextStep(workdays: Int, sessions: Int) -> String {
        let missingDays = max(0, 10 - workdays)
        let missingSessions = max(0, 20 - sessions)
        if missingDays > 0 && missingSessions > 0 {
            return "下一步：照常记录，并完成今天的专注训练；还差 \(missingDays) 个工作日和 \(missingSessions) 次训练。"
        }
        if missingDays > 0 {
            return "下一步：继续正常工作并保持记录；还差 \(missingDays) 个工作日。"
        }
        return "下一步：再完成 \(missingSessions) 次专注训练。"
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 { return String(format: "%d 小时 %02d 分", total / 3600, total / 60 % 60) }
        return "\(total / 60) 分 \(total % 60) 秒"
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func trendText(_ value: Double?) -> String {
        value.map { String(format: "较近 7 日 %+.0f%%", $0) } ?? "可比样本不足"
    }

    private func confidenceText(_ value: DailyCoachConfidence) -> String {
        switch value {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }

    private func evaluationIcon(_ value: DailyCoachEvaluationStatus) -> String {
        switch value {
        case .improved: return "checkmark.circle.fill"
        case .needsAdjustment: return "arrow.triangle.2.circlepath"
        case .notRun: return "circle.dashed"
        case .insufficientData: return "questionmark.circle"
        }
    }

    private func evaluationColor(_ value: DailyCoachEvaluationStatus) -> Color {
        switch value {
        case .improved: return .green
        case .needsAdjustment: return .orange
        case .notRun, .insufficientData: return .secondary
        }
    }

    private func actionButtonTitle(_ action: DailyCoachAction) -> String? {
        switch action {
        case .none: return nil
        case .bindWorkflow: return "绑定当前桌面"
        case let .startFocus(minutes): return "现在开始 \(minutes) 分钟"
        case .parkWorkflow: return "练习一次挂起"
        case .reviewTimeline: return "打开时间轴校准"
        }
    }

    private func perform(_ action: DailyCoachAction) {
        switch action {
        case .none:
            break
        case .bindWorkflow:
            if state.activeTasks.isEmpty { state.showTaskCreator = true }
            else { state.showTaskSwitcher = true }
        case let .startFocus(minutes):
            state.requestStartFocus(minutes: minutes)
            state.selectedAppSection = .focus
        case .parkWorkflow:
            if state.currentTaskID == nil {
                if state.activeTasks.isEmpty { state.showTaskCreator = true }
                else { state.showTaskSwitcher = true }
            } else {
                state.showTaskParking = true
            }
        case .reviewTimeline:
            state.selectedAppSection = .timeline
        }
    }
}
