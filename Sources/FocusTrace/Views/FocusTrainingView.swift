import SwiftUI
import FocusTraceCore

struct FocusTrainingView: View {
    @ObservedObject var state: ApplicationState
    @State private var showingNewTask = false
    @State private var editingTask: FocusTaskModel?
    @State private var workflowToComplete: FocusTaskModel?
    @State private var showCompletedWorkflows = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                baselineCard
                currentSessionCard
                if !state.activeTaskParkings.isEmpty {
                    parkedTasksCard
                }
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
        .confirmationDialog(
            "完成这个工作流？",
            isPresented: Binding(
                get: { workflowToComplete != nil },
                set: { if !$0 { workflowToComplete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let workflowToComplete {
                Button("完成“\(workflowToComplete.title)”") {
                    state.completeWorkflow(workflowToComplete.id)
                    self.workflowToComplete = nil
                }
                Button("取消", role: .cancel) { self.workflowToComplete = nil }
            }
        } message: {
            Text("会闭合当前区间并释放桌面绑定；30 秒内可以撤销。")
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
                         : baselineGuidance)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
        }
    }

    private var baselineGuidance: String {
        if state.activeTasks.isEmpty {
            return "还没有任务：当前记录不会累积基线。请先创建任务。"
        }
        if state.currentTaskID == nil {
            return "请先选择当前任务；未标注的时间不计入 3 日基线。"
        }
        return "前三个工作日只观察，不发送分心提醒。请通过菜单栏及时切换任务标签。"
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
                    Text("训练工作流：\(state.focusWorkflowName)")
                    if state.isCurrentFocusPaused {
                        Label(
                            "计时已暂停；回到这个工作流绑定的桌面后自动恢复。",
                            systemImage: "pause.circle.fill"
                        )
                        .foregroundStyle(.orange)
                    } else if let grace = state.focusDepartureGraceRemaining {
                        Label(
                            "暂时离开；\(grace) 秒内返回不会暂停本轮训练。",
                            systemImage: "arrow.uturn.backward.circle"
                        )
                        .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("结束并记录结果") { state.endFocus() }
                            .buttonStyle(.borderedProminent)
                        if state.isSpaceWorkflowModeEnabled {
                            Text("切换工作流请切换 macOS 桌面")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("切换任务") { state.showTaskSwitcher = true }
                        }
                        Button("Agent 等待：挂起并切换") { state.showTaskParking = true }
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
                            VStack(alignment: .trailing, spacing: 8) {
                                Button("开始 \(state.currentPlan.focusMinutes) 分钟") {
                                    state.startFocus()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                Button("先挂起当前任务") {
                                    state.showTaskParking = true
                                }
                            }
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

    private var parkedTasksCard: some View {
        GroupBox("待返回任务") {
            VStack(spacing: 0) {
                ForEach(state.activeTaskParkings) { parking in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .foregroundStyle(.blue)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(state.taskName(for: parking.taskID))
                                .font(.headline)
                            Text(parking.resumeCue)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Text("挂起于")
                                Text(parking.parkedAt, style: .relative)
                                if let remindAt = parking.remindAt {
                                    Text("· 提醒")
                                    Text(remindAt, style: .time)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("不再返回") { state.dismissTaskParking(parking.id) }
                            .buttonStyle(.borderless)
                        Button("继续任务") { state.resumeTaskParking(parking.id) }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 10)
                    if parking.id != state.activeTaskParkings.last?.id { Divider() }
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
        GroupBox("工作流、桌面与允许应用") {
            VStack(spacing: 0) {
                ForEach(state.activeTasks) { task in
                    HStack {
                        Button {
                            if state.isSpaceWorkflowModeEnabled {
                                state.bindCurrentSpace(to: task.id)
                            } else {
                                state.switchTask(to: task.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: task.id == state.currentTaskID ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.id == state.currentTaskID ? .green : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title).font(.headline)
                                    let bindingCount = state.verifiedSpaceBindingCount(for: task.id)
                                    Text(bindingCount == 0
                                         ? "允许 \(task.allowedBundleIDs.count) 个应用 · 尚未绑定桌面"
                                         : "允许 \(task.allowedBundleIDs.count) 个应用 · 已绑定 \(bindingCount) 个桌面")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        if state.currentSpaceWorkflowID == task.id {
                            Label("当前桌面", systemImage: "rectangle.fill.on.rectangle.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        } else if state.currentSpaceWorkflowID == nil {
                            Button {
                                state.bindCurrentSpace(to: task.id)
                            } label: {
                                Label("绑定此桌面", systemImage: "rectangle.badge.plus")
                            }
                        }
                        Button("编辑") { editingTask = task }
                        Button {
                            workflowToComplete = task
                        } label: {
                            Label("完成", systemImage: "checkmark.circle")
                        }
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

                if !state.completedWorkflows.isEmpty {
                    Divider().padding(.vertical, 10)
                    DisclosureGroup(
                        "已完成工作流（\(state.completedWorkflows.count)）",
                        isExpanded: $showCompletedWorkflows
                    ) {
                        ForEach(state.completedWorkflows) { workflow in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workflow.title)
                                    if let completedAt = workflow.completedAt {
                                        Text("完成于 \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("重新打开") { state.reopenWorkflow(workflow.id) }
                                Button("归档") { state.archiveTask(workflow.id) }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private var privacyNote: some View {
        Label(
            "桌面只用于识别工作流边界；应用切换仍只按 Bundle ID 记录，不读取窗口标题、网页地址或输入内容。",
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
