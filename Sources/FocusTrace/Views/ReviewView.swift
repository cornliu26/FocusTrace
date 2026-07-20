import SwiftUI
import FocusTraceCore

struct ReviewView: View {
    @ObservedObject var state: ApplicationState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dailySummary
                unresolvedReview
                phaseTwoAnalysis
                trainingHistory
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private var dailySummary: some View {
        let summary = state.selectedSummary
        return GroupBox("\(state.selectedDate.formatted(date: .abbreviated, time: .omitted)) 回顾") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    DatePicker("日期", selection: $state.selectedDate, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.field)
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
                    MetricCard(title: "任务停车", value: "\(summary.taskParkingCount)", detail: "有意挂起")
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
        GroupBox("训练计划版本") {
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

    private func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 { return String(format: "%d 小时 %02d 分", total / 3600, total / 60 % 60) }
        return "\(total / 60) 分 \(total % 60) 秒"
    }
}
