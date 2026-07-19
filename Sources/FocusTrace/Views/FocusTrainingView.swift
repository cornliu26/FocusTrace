import SwiftUI
import FocusTraceCore

struct FocusTrainingView: View {
    @ObservedObject var state: ApplicationState
    @State private var showingNewTask = false
    @State private var editingTask: FocusTaskModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                baselineCard
                currentSessionCard
                if let proposal = state.trainingProposal {
                    proposalCard(proposal)
                }
                taskCard
                privacyNote
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .sheet(isPresented: $showingNewTask) {
            TaskEditorSheet(state: state)
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(state: state, editingTask: task)
        }
    }

    private var baselineCard: some View {
        GroupBox {
            HStack(spacing: 16) {
                Image(systemName: state.baselineComplete ? "checkmark.seal.fill" : "calendar.badge.clock")
                    .font(.title)
                    .foregroundStyle(state.baselineComplete ? .green : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.baselineProgressText)
                        .font(.headline)
                    Text(state.baselineComplete
                         ? "提醒和渐进训练已启用。"
                         : "前三个工作日只观察，不发送分心提醒。请通过菜单栏及时切换任务标签。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
        }
    }

    private var currentSessionCard: some View {
        GroupBox("当前训练") {
            VStack(alignment: .leading, spacing: 16) {
                if let focus = state.currentFocus {
                    HStack(alignment: .firstTextBaseline) {
                        Text(format(state.focusRemainingSeconds))
                            .font(.system(size: 54, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Spacer()
                        Text("目标 \(focus.targetSeconds / 60) 分钟")
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(
                        value: Double(state.focusElapsedSeconds),
                        total: Double(max(1, focus.targetSeconds))
                    )
                    Text("主任务：\(state.currentTask?.title ?? "未知")")
                    HStack {
                        Button("结束并记录结果") { state.endFocus() }
                            .buttonStyle(.borderedProminent)
                        Button("切换任务") { state.showTaskSwitcher = true }
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(state.currentTask?.title ?? "请先选择一个主任务")
                                .font(.title2.bold())
                            if let outcome = state.currentTask?.expectedOutcome, !outcome.isEmpty {
                                Text("期望产出：\(outcome)")
                                    .foregroundStyle(.secondary)
                            }
                            Text("今日已开始 \(state.todayTrainingCount)/\(state.currentPlan.sessionsPerDay) 次")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if state.currentTaskID != nil {
                            Button("开始 \(state.currentPlan.focusMinutes) 分钟") {
                                state.startFocus()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        } else {
                            Button("选择任务") { state.showTaskSwitcher = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private func proposalCard(_ proposal: TrainingProposal) -> some View {
        GroupBox("训练计划建议") {
            VStack(alignment: .leading, spacing: 10) {
                Text(proposal.title).font(.headline)
                Text(proposal.evidence).foregroundStyle(.secondary)
                HStack {
                    Button("采用") { state.acceptTrainingProposal() }
                        .buttonStyle(.borderedProminent)
                    Button("暂不调整") { state.dismissTrainingProposal() }
                }
            }
            .padding(8)
        }
    }

    private var taskCard: some View {
        GroupBox("任务与允许应用") {
            VStack(spacing: 0) {
                ForEach(state.activeTasks) { task in
                    HStack {
                        Button {
                            state.switchTask(to: task.id)
                        } label: {
                            HStack {
                                Image(systemName: task.id == state.currentTaskID ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.id == state.currentTaskID ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title).font(.headline)
                                    Text("允许 \(task.allowedBundleIDs.count) 个应用")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button("编辑") { editingTask = task }
                        Button(role: .destructive) {
                            state.archiveTask(task.id)
                        } label: {
                            Image(systemName: "archivebox")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 9)
                    if task.id != state.activeTasks.last?.id { Divider() }
                }
                if state.activeTasks.isEmpty {
                    ContentUnavailableView(
                        "还没有任务",
                        systemImage: "checklist",
                        description: Text("新建任务并选择它需要使用的应用。")
                    )
                    .frame(height: 150)
                }
                HStack {
                    Button("新建任务", systemImage: "plus") { showingNewTask = true }
                    Spacer()
                }
                .padding(.top, 12)
            }
            .padding(8)
        }
    }

    private var privacyNote: some View {
        Label(
            "只判断当前应用是否属于任务允许集合；不会读取应用内部内容。",
            systemImage: "lock.shield"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func format(_ seconds: Int) -> String {
        if seconds == 0 && state.currentFocusID != nil { return "已完成" }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct SessionReviewSheet: View {
    @ObservedObject var state: ApplicationState
    let review: PendingSessionReview
    @State private var outcome: FocusOutcome = .completed
    @State private var difficulty = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("记录本轮结果")
                .font(.title2.bold())
            Text("目标 \(review.targetMinutes) 分钟，实际 \(review.elapsedSeconds / 60) 分 \(review.elapsedSeconds % 60) 秒")
                .foregroundStyle(.secondary)

            Picker("目标完成情况", selection: $outcome) {
                Text("已完成").tag(FocusOutcome.completed)
                Text("部分完成").tag(FocusOutcome.partial)
                Text("未完成").tag(FocusOutcome.notCompleted)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading) {
                Text("主观专注难度：\(difficulty)/5")
                Slider(value: Binding(
                    get: { Double(difficulty) },
                    set: { difficulty = Int($0.rounded()) }
                ), in: 1...5, step: 1)
            }

            Text("训练成功还要求达到目标时长，且没有确认的非必要偏离。必要工具切换不会导致失败。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("保存结果") {
                    state.completeSessionReview(id: review.id, outcome: outcome, difficulty: difficulty)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
