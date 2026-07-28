import SwiftUI
import FocusTraceCore

struct ReviewView: View {
    @ObservedObject var state: ApplicationState
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
                localAnalysis
                interventionEffectiveness
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

    private var interventionEffectiveness: some View {
        let audit = state.selectedInterventionAudit
        return GroupBox {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.title3)
                        .foregroundStyle(FocusTraceTheme.mint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("只在高频切换段请求确认")
                            .font(.headline)
                        Text("普通切换静默记录；10 分钟内第 3 次已绑定工作流切换才在屏幕中上方确认，之后冷却 10 分钟。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 4),
                    spacing: 10
                ) {
                    MetricCard(
                        title: "高频切换段",
                        value: "\(audit.frequentSwitchEpisodes)",
                        detail: "达到确认门槛"
                    )
                    MetricCard(
                        title: "实际确认",
                        value: "\(audit.promptsShown)",
                        detail: "最多每 10 分钟一次"
                    )
                    MetricCard(
                        title: "主动说明",
                        value: "\(audit.confirmedPrompts)",
                        detail: audit.promptsShown > 0
                            ? percent(audit.confirmationRate ?? 0)
                            : "暂无确认"
                    )
                    MetricCard(
                        title: "确认后稳定",
                        value: audit.quietAfterPromptRate.map(percent) ?? "—",
                        detail: audit.assessedPrompts > 0
                            ? "后续 10 分钟未再切换"
                            : "等待完整观察窗"
                    )
                }

                Label(interventionStatus(audit), systemImage: interventionStatusIcon(audit))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        } label: {
            HStack {
                Label("切换干预是否值得", systemImage: "waveform.path.ecg")
                Spacer()
                Text("仅聚合语义跳转")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
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

    private var localAnalysis: some View {
        let analysis = state.selectedCoachingAnalysis
        let recommendation = analysis.recommendation
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

    private func interventionStatus(
        _ audit: WorkflowInterventionAudit
    ) -> String {
        if !state.baselineComplete,
           Calendar.current.isDateInToday(state.selectedDate) {
            return "仍在基线期：今天只记录，不弹出确认。"
        }
        if audit.frequentSwitchEpisodes == 0 {
            return "今天没有进入高频切换段，FocusTrace 不会为了正常切换打断你。"
        }
        if audit.promptsShown == 0 {
            return "检测到高频切换段，但没有策略确认记录；旧数据或当时未启用确认不会被补算。"
        }
        guard let quietRate = audit.quietAfterPromptRate else {
            return "确认后的 10 分钟观察窗尚未结束，暂不判断这次干预是否有效。"
        }
        return quietRate >= 0.5
            ? "确认后多数观察窗恢复稳定；继续观察，不增加弹出频率。"
            : "确认后仍常继续切换；当前干预效果不足，不应提高弹出频率。"
    }

    private func interventionStatusIcon(
        _ audit: WorkflowInterventionAudit
    ) -> String {
        guard let rate = audit.quietAfterPromptRate else {
            return "info.circle"
        }
        return rate >= 0.5 ? "checkmark.circle" : "exclamationmark.circle"
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
