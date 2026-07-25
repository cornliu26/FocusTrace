import SwiftUI
import FocusTraceCore

struct ReviewView: View {
    @ObservedObject var state: ApplicationState
    @StateObject private var codexBridge = CodexReviewBridge()
    @StateObject private var codexLauncher = CodexConnectionLauncher()
    @State private var showPlanHistory = false
    @State private var showLocalEvidence = false
    @State private var showDailyDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                reviewHeader
                localAnalysis
                codexAnalysis
                if hasUnresolvedReview {
                    unresolvedReview
                }
                phaseTwoAnalysis
                dailySummary
                trainingHistory
            }
            .focusTracePageContent()
        }
        .focusTraceScreen()
        .task(id: state.selectedDate) {
            await codexBridge.observe(for: state.selectedDate)
        }
    }

    private var reviewHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            FocusTraceDateNavigator(
                selection: $state.selectedDate,
                latestDate: state.now
            )
            .equatable()
            VStack(alignment: .leading, spacing: 3) {
                Text("先看结论，再决定是否展开数据")
                    .font(.headline)
                Text("本地分析实时可用；Codex 是可选的每日深度复盘，不参与采集。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var localAnalysis: some View {
        let analysis = state.selectedCoachingAnalysis
        let recommendation = analysis.recommendation
        return GroupBox {
            VStack(alignment: .leading, spacing: 14) {
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

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今天唯一建议")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FocusTraceTheme.mint)
                        Text(recommendation.title)
                            .font(.title2.bold())
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

                DisclosureGroup(
                    "为什么这么建议",
                    isExpanded: $showLocalEvidence
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(recommendation.evidence, id: \.self) { evidence in
                            Label(evidence, systemImage: "chart.bar.xaxis")
                                .font(.callout)
                        }
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible()), count: 4),
                            spacing: 10
                        ) {
                            MetricCard(
                                title: "有效记录",
                                value: String(format: "%.0f 分", analysis.metrics.recordedMinutes),
                                detail: analysis.quality.isReliableForBehavior ? "可用于比较" : "暂不做行为判断"
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
                    }
                    .padding(.top, 10)
                }
            }
            .padding(8)
        } label: {
            HStack {
                Label("FocusTrace 本地分析", systemImage: "cpu")
                Spacer()
                Text("无需 Codex · 实时")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var codexAnalysis: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 13) {
                Text("FocusTrace 只把匿名聚合报告交给 Codex；Codex 负责解释趋势并写回本页，不会读取窗口标题、输入内容或逐条轨迹。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                switch codexBridge.status {
                case .notConnected:
                    VStack(alignment: .leading, spacing: 12) {
                        bridgeStatus(
                            title: "尚未连接每日复盘",
                            detail: "FocusTrace 会准备匿名聚合工作区，并把完整接入指令预填到 Codex。",
                            systemImage: "link.badge.plus",
                            color: .orange
                        )
                        Button {
                            codexLauncher.connect()
                            codexBridge.load(for: state.selectedDate)
                        } label: {
                            Label(
                                codexConnectButtonTitle,
                                systemImage: "arrow.up.forward.app"
                            )
                        }
                        .buttonStyle(FocusTracePrimaryButtonStyle())
                        .disabled(codexLauncher.status == .preparing)
                    }
                case .noAggregate:
                    bridgeStatus(
                        title: "这一天还没有聚合报告",
                        detail: "定时任务运行后会生成；这不影响上面的本地分析。",
                        systemImage: "calendar.badge.exclamationmark",
                        color: .secondary
                    )
                case let .waiting(report):
                    bridgeStatus(
                        title: "聚合报告已准备，等待 Codex 写回",
                        detail: "报告生成于 \(report.generatedAt.formatted(date: .omitted, time: .shortened))；每日定时任务完成后会自动出现在这里。",
                        systemImage: "clock.arrow.circlepath",
                        color: .blue
                    )
                case let .ready(_, review):
                    VStack(alignment: .leading, spacing: 12) {
                        Text(review.headline)
                            .font(.title3.bold())
                        Text(review.interpretation)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Codex 建议")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.purple)
                            Text(review.recommendation)
                                .font(.headline)
                            ForEach(review.evidence, id: \.self) { evidence in
                                Label(evidence, systemImage: "checkmark.circle")
                                    .font(.callout)
                            }
                            Label("下次验证：\(review.nextCheck)", systemImage: "scope")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.purple)
                        }
                        Text("写回于 \(review.generatedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                case let .invalid(message):
                    bridgeStatus(
                        title: "Codex 写回内容未通过校验",
                        detail: message,
                        systemImage: "exclamationmark.shield",
                        color: .red
                    )
                }

                codexConnectionFeedback

                HStack {
                    Spacer()
                    Button("刷新 Codex 结果") {
                        codexBridge.load(for: state.selectedDate)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
        } label: {
            HStack {
                Label("Codex 每日深度复盘", systemImage: "sparkles")
                Spacer()
                Text("可选增强 · 文件桥")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var codexConnectButtonTitle: String {
        codexLauncher.status == .preparing
            ? "正在准备本地工作区…"
            : "在 Codex 中接入每日复盘"
    }

    @ViewBuilder
    private var codexConnectionFeedback: some View {
        switch codexLauncher.status {
        case .idle, .preparing:
            EmptyView()
        case .opened:
            Label(
                "Codex 已打开：发送已经填好的指令，即可完成首次验证和每日定时任务。",
                systemImage: "checkmark.circle"
            )
            .font(.callout)
            .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    private func bridgeStatus(
        title: String,
        detail: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var hasUnresolvedReview: Bool {
        state.selectedInterruptions.contains { $0.resolution == .unresolved }
    }

    private var dailySummary: some View {
        let summary = state.selectedSummary
        return GroupBox {
            DisclosureGroup(
                "当天记录明细",
                isExpanded: $showDailyDetails
            ) {
                VStack(alignment: .leading, spacing: 14) {
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
                    MetricCard(title: "保存返回点", value: "\(summary.taskParkingCount)", detail: "离开前写下下一步")
                    MetricCard(title: "已返回", value: "\(summary.resumedTaskCount)", detail: "按返回点继续")
                    MetricCard(
                        title: "平均恢复耗时",
                        value: summary.averageTaskResumeLatency.map(duration) ?? "—",
                        detail: "从离开到继续"
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
                .padding(.top, 12)
            }
            .padding(8)
        } label: {
            Text("数据证据")
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
        case .parkWorkflow: return "练习一次保存返回点"
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
