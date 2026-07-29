import SwiftUI
import FocusTraceCore

struct ReviewView: View {
    @ObservedObject var state: ApplicationState
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var codexBridge = CodexReviewBridge()
    @StateObject private var codexLauncher = CodexConnectionLauncher()
    @State private var showPlanHistory = false
    @State private var showLocalEvidence = false
    @State private var showObservationPlan = false
    @State private var showDailyDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                reviewHeader
                attentionDashboard
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
            codexLauncher.refreshExistingWorkspaceIfPresent()
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
                Text("本地分析实时可用；Codex 是可选的每日行动复盘，不参与采集。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var attentionDashboard: some View {
        let dashboard = state.selectedAttentionDashboard
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(FocusTraceTheme.accentGradient.opacity(0.14))
                    Image(systemName: "rectangle.3.group.bubble.left.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(FocusTraceTheme.indigo)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text("注意力趋势")
                        .font(.title3.bold())
                    Text(dashboardPeriodDescription(dashboard))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    DashboardSummaryPill(
                        title: "趋势工作日",
                        value: "\(dashboard.baselineDays)/\(AttentionDashboardEngine.trendWorkdayCount)"
                    )
                    DashboardSummaryPill(
                        title: "可靠趋势",
                        value: "\(dashboard.reliableDimensionCount)/\(dashboard.metrics.count)"
                    )
                    DashboardSummaryPill(
                        title: "所选日记录",
                        value: "\(Int(dashboard.recordedMinutes.rounded())) 分"
                    )
                }
            }

            if let finding = dashboard.finding {
                AttentionDashboardFindingCard(finding: finding)
            } else if dashboard.reliableDimensionCount == 0 {
                Label(
                    "当前不能据此判断注意力；至少需要 5 个可靠工作日。",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(FocusTraceTheme.amber)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    FocusTraceTheme.amber.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }

            VStack(spacing: 10) {
                ForEach(dashboard.metrics) { metric in
                    AttentionTrendCard(metric: metric)
                }
            }

            if dashboard.includesPartialDay == true {
                Label(
                    "进行中的日期只显示为空心点，不参与趋势方向和主要问题判断。",
                    systemImage: "circle.dashed"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(dashboard.boundary)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(
            FocusTraceTheme.cardFill(colorScheme),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FocusTraceTheme.cardBorder(colorScheme), lineWidth: 1)
        }
    }

    private var localAnalysis: some View {
        let analysis = state.selectedCoachingAnalysis
        let recommendation = state.selectedAttentionDashboard.recommendation
            ?? analysis.recommendation
        let observationPlan = ObservationPlanEngine.makePlan(
            coaching: analysis,
            summary: state.selectedSummary,
            interventionAudit: state.selectedInterventionAudit
        )
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
                        Text("下一步单项实验")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FocusTraceTheme.mint)
                        Text(recommendation.title)
                            .font(.title2.bold())
                        Text(recommendation.rationale)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("趋势可信度：\(confidenceText(recommendation.confidence))")
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
                    Label("验收：\(recommendation.method.successMeasure)", systemImage: "checkmark.seal")
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
                    }
                    .padding(.top, 6)
                }
                .focusTraceDisclosureHitTarget(isExpanded: $showLocalEvidence)

                observationPlanDisclosure(observationPlan)
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

    private func dashboardPeriodDescription(
        _ dashboard: AttentionDashboard
    ) -> String {
        guard let start = dashboard.periodStart,
              let end = dashboard.periodEnd else {
            return "至少 5 个可靠工作日后，比较最近 3 日与此前个人典型区间"
        }
        let startText = start.formatted(.dateTime.month().day())
        let endText = end.formatted(.dateTime.month().day())
        return "\(startText)–\(endText) · 最近 3 个可靠工作日 vs 此前最多 7 日"
    }

    private func observationPlanDisclosure(
        _ plan: DailyObservationPlan
    ) -> some View {
        let primary = plan.primaryAllocation
        return DisclosureGroup(
            isExpanded: $showObservationPlan
        ) {
            VStack(alignment: .leading, spacing: 11) {
                Text("这里配置的是分析精力，不会抽样或丢弃原始时间轴。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(plan.allocations, id: \.lens) { allocation in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(observationLensTitle(allocation.lens))
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Text("\(allocation.percent)%")
                                .font(.callout.monospacedDigit().weight(.semibold))
                        }
                        ProgressView(
                            value: Double(allocation.percent),
                            total: 100
                        )
                        .tint(observationLensColor(allocation.lens))
                        Text(allocation.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Label(
                    plan.source == .initialDefault
                        ? "来源：均衡初始配置"
                        : "来源：当天聚合 + 近 7 个可比工作日（当前可比 \(plan.lookbackWorkdays) 天）",
                    systemImage: "doc.text.magnifyingglass"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Label(
                    plan.interventionRecommendation,
                    systemImage: "bell.badge"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Text(
                    "今天重点观察："
                        + observationLensTitle(
                            primary?.lens ?? .dataQuality
                        )
                )
                Spacer()
                Text("\(primary?.percent ?? 25)% · 配置 v\(plan.version)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .focusTraceDisclosureHitTarget(isExpanded: $showObservationPlan)
    }

    @ViewBuilder
    private var codexAnalysis: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 13) {
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
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 7) {
                            Label(
                                review.displayedStatus == .dataQualityBlocked
                                    ? "当前数据问题"
                                    : "当前问题",
                                systemImage: review.displayedStatus == .dataQualityBlocked
                                    ? "exclamationmark.triangle.fill"
                                    : "scope"
                            )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(
                                review.displayedStatus == .dataQualityBlocked
                                    ? FocusTraceTheme.amber
                                    : FocusTraceTheme.coral
                            )
                            Text(review.displayedProblem)
                                .font(.title3.bold())
                                .fixedSize(horizontal: false, vertical: true)
                            ForEach(review.evidence, id: \.self) { evidence in
                                Label(evidence, systemImage: "chart.bar.fill")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 7) {
                            Label("今天怎么做", systemImage: "arrow.right.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(FocusTraceTheme.mint)
                            Text(review.recommendation)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Label("验收：\(review.nextCheck)", systemImage: "checkmark.seal")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(FocusTraceTheme.sky)
                        }

                        Label(
                            "仅使用本地聚合数据 · 写回于 \(review.generatedAt.formatted(date: .omitted, time: .shortened))",
                            systemImage: "lock.shield"
                        )
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
                Label("Codex 每日行动复盘", systemImage: "sparkles")
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
            .focusTraceDisclosureHitTarget(isExpanded: $showDailyDetails)
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
            .focusTraceDisclosureHitTarget(isExpanded: $showPlanHistory)
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

    private func observationLensTitle(_ lens: ObservationLens) -> String {
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

    private func observationLensColor(_ lens: ObservationLens) -> Color {
        switch lens {
        case .dataQuality:
            return FocusTraceTheme.amber
        case .fragmentation:
            return FocusTraceTheme.sky
        case .contextRecovery:
            return FocusTraceTheme.mint
        case .workflowSemantics:
            return FocusTraceTheme.coral
        }
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
        case .bindWorkflow: return nil
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
            break
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

private struct DashboardSummaryPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.secondary.opacity(0.07), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

private struct AttentionDashboardFindingCard: View {
    let finding: AttentionDashboardFinding
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(
                    color.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                Text(finding.title)
                    .font(.title3.bold())
                Text(finding.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(finding.evidence, id: \.self) { evidence in
                    Label(evidence, systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
        }
        .padding(14)
        .background(
            FocusTraceTheme.elevatedFill(colorScheme),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var label: String {
        switch finding.state {
        case .calibrating: return "样本状态"
        case .stable: return "当前结论"
        case .improving: return "持续改善"
        case .needsAttention: return "当前唯一问题"
        }
    }

    private var icon: String {
        switch finding.state {
        case .calibrating: return "hourglass"
        case .stable: return "equal.circle"
        case .improving: return "arrow.up.right.circle"
        case .needsAttention: return "scope"
        }
    }

    private var color: Color {
        switch finding.state {
        case .calibrating: return FocusTraceTheme.sky
        case .stable, .improving: return FocusTraceTheme.jade
        case .needsAttention: return FocusTraceTheme.coral
        }
    }
}

private struct AttentionTrendCard: View {
    let metric: AttentionDashboardMetric
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(
                        accent.opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.title)
                        .font(.headline)
                    Text(metric.value)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                }
            }
            .frame(width: 170, alignment: .leading)

            if let trend = metric.trend {
                VStack(spacing: 4) {
                    AttentionTrendChart(trend: trend, accent: accent)
                        .frame(height: 62)
                    HStack {
                        Text(
                            trend.points.first?.date.formatted(
                                .dateTime.month().day()
                            ) ?? ""
                        )
                        Spacer()
                        Text(
                            trend.points.last?.date.formatted(
                                .dateTime.month().day()
                            ) ?? ""
                        )
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("等待形成纵向样本")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(stateTitle)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(stateColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(stateColor.opacity(0.10), in: Capsule())
                    Spacer()
                    if let reliableDays = metric.trend?.reliableDayCount {
                        Text(
                            metric.kind == .trainingFeedback
                                ? "最近 \(reliableDays) 次"
                                : "可靠 \(reliableDays) 天"
                        )
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(metric.comparison)
                    .font(.caption.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let evidence = metric.evidence.first {
                    Text(evidence)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(width: 235, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            FocusTraceTheme.elevatedFill(colorScheme),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(accent.opacity(0.14), lineWidth: 1)
        }
        .opacity(metric.state == .unavailable ? 0.72 : 1)
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch metric.kind {
        case .sustainedProgress: return "arrow.right.to.line.compact"
        case .fragmentation: return "square.grid.3x3.middle.filled"
        case .switchingBoundary: return "arrow.trianglehead.branch"
        case .contextRecovery: return "arrow.uturn.backward.circle"
        case .trainingFeedback: return "scope"
        }
    }

    private var accent: Color {
        switch metric.kind {
        case .sustainedProgress: return FocusTraceTheme.jade
        case .fragmentation: return FocusTraceTheme.amber
        case .switchingBoundary: return FocusTraceTheme.indigo
        case .contextRecovery: return FocusTraceTheme.violet
        case .trainingFeedback: return FocusTraceTheme.cyan
        }
    }

    private var stateTitle: String {
        switch metric.state {
        case .unavailable: return "待收集"
        case .calibrating: return "趋势校准中"
        case .observed: return "趋势稳定"
        case .improving: return "持续改善"
        case .needsAttention:
            return metric.kind == .trainingFeedback
                ? "负荷不适配"
                : "持续恶化"
        }
    }

    private var stateColor: Color {
        switch metric.state {
        case .unavailable: return .secondary
        case .calibrating: return FocusTraceTheme.sky
        case .observed: return accent
        case .improving: return FocusTraceTheme.jade
        case .needsAttention: return FocusTraceTheme.coral
        }
    }
}

private struct AttentionTrendChart: View {
    let trend: AttentionMetricTrend
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let values = trend.points.compactMap(\.value)
                + [trend.typicalLowerBound, trend.typicalUpperBound]
                    .compactMap { $0 }
            guard !values.isEmpty else { return }
            let minimum = values.min() ?? 0
            let maximum = values.max() ?? 1
            let spread = max(1, maximum - minimum)
            let lower = max(0, minimum - spread * 0.12)
            let upper = maximum + spread * 0.12
            let plotInset = min(
                CGFloat(FocusTraceAttentionTrendLayout.plotInset),
                min(size.width, size.height) / 2
            )
            let plotWidth = max(0, size.width - plotInset * 2)
            let plotHeight = max(0, size.height - plotInset * 2)

            func x(_ index: Int) -> CGFloat {
                CGFloat(
                    FocusTraceAttentionTrendLayout.pointX(
                        index: index,
                        pointCount: trend.points.count,
                        availableWidth: Double(size.width)
                    )
                )
            }
            func y(_ value: Double) -> CGFloat {
                let normalized = (value - lower) / max(0.0001, upper - lower)
                return plotInset + plotHeight * CGFloat(1 - normalized)
            }

            if let typicalLower = trend.typicalLowerBound,
               let typicalUpper = trend.typicalUpperBound {
                let top = y(max(typicalLower, typicalUpper))
                let bottom = y(min(typicalLower, typicalUpper))
                let rect = CGRect(
                    x: plotInset,
                    y: min(top, bottom),
                    width: plotWidth,
                    height: max(3, abs(bottom - top))
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 3),
                    with: .color(accent.opacity(0.08))
                )
            }

            if let baseline = trend.baselineMedian {
                var baselinePath = Path()
                baselinePath.move(
                    to: CGPoint(x: plotInset, y: y(baseline))
                )
                baselinePath.addLine(
                    to: CGPoint(
                        x: size.width - plotInset,
                        y: y(baseline)
                    )
                )
                context.stroke(
                    baselinePath,
                    with: .color(accent.opacity(0.28)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
            }

            var line = Path()
            var hasOpenSegment = false
            for (index, point) in trend.points.enumerated() {
                guard let value = point.value,
                      point.isReliable,
                      !point.isPartial else {
                    hasOpenSegment = false
                    continue
                }
                let location = CGPoint(x: x(index), y: y(value))
                if hasOpenSegment {
                    line.addLine(to: location)
                } else {
                    line.move(to: location)
                    hasOpenSegment = true
                }
            }
            context.stroke(
                line,
                with: .color(accent.opacity(0.82)),
                style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            for (index, point) in trend.points.enumerated() {
                guard let value = point.value else { continue }
                let location = CGPoint(x: x(index), y: y(value))
                let diameter: CGFloat = point.isPartial ? 7 : 6
                let dot = Path(
                    ellipseIn: CGRect(
                        x: location.x - diameter / 2,
                        y: location.y - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                )
                if point.isPartial {
                    context.stroke(
                        dot,
                        with: .color(accent),
                        style: StrokeStyle(lineWidth: 1.5)
                    )
                } else if point.isReliable {
                    context.fill(dot, with: .color(accent))
                } else {
                    context.fill(
                        dot,
                        with: .color(Color.secondary.opacity(0.28))
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}
