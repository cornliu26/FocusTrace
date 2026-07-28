import SwiftUI
import FocusTraceCore

struct FocusTrainingView: View {
    @ObservedObject var state: ApplicationState
    @State private var showingNewTask = false
    @State private var editingTask: FocusTaskModel?
    @State private var workflowToComplete: FocusTaskModel?
    @State private var showCompletedWorkflows = false
    @State private var showWorkflowManagement = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let checkpoint = state.resumedWorkflowCheckpoint {
                    resumedCheckpointCard(checkpoint)
                }
                currentSessionCard
                if !state.activeTaskParkings.isEmpty {
                    parkedTasksCard
                }
                if let proposal = state.trainingProposal {
                    proposalCard(proposal)
                }
                baselineCard
                taskCard
                privacyNote
            }
            .focusTracePageContent()
        }
        .focusTraceScreen()
        .sheet(isPresented: $showingNewTask) {
            TaskEditorSheet(
                state: state,
                bindCurrentSpaceOnCreate: state.currentSpaceWorkflowID == nil
            )
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

    private func resumedCheckpointCard(
        _ checkpoint: ResumedWorkflowCheckpoint
    ) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title2)
                    .foregroundStyle(FocusTraceTheme.mint)
                VStack(alignment: .leading, spacing: 5) {
                    Text("你已回到“\(checkpoint.taskTitle)”")
                        .font(.headline)
                    Text("现在先做：\(checkpoint.nextStep)")
                        .font(.title3.weight(.semibold))
                    Text("这就是刚才保存的返回点；执行第一步后，大脑不需要重新回忆整个上下文。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("开始做") {
                    state.acknowledgeResumedWorkflowCheckpoint()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(8)
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
            return "还没有工作流：当前记录不会累积基线。请先创建工作流。"
        }
        if state.currentTaskID == nil {
            return "请先绑定当前工作流；未标注的时间不计入 3 日基线。"
        }
        return "前三个工作日只观察，不发送分心提醒。之后切换桌面即可切换工作流。"
    }

    private var currentSessionCard: some View {
        GroupBox(state.currentFocus == nil ? "下一步" : "当前训练") {
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
                            Button("切换工作流") { state.showTaskSwitcher = true }
                        }
                        Button("Agent 还在运行：保存返回点") {
                            state.showTaskParking = true
                        }
                    }
                } else {
                    idleGuidance
                }
            }
            .padding(8)
        }
    }

    private var idleGuidance: some View {
        let guidance = state.flowGuidance
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(guidance.title)
                        .font(.title2.bold())
                    Text(guidance.detail)
                        .foregroundStyle(.secondary)
                    if state.currentTaskID != nil {
                        Text("今日已开始 \(state.todayTrainingCount)/\(state.currentPlan.sessionsPerDay) 次")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Button(guidance.buttonTitle) {
                    perform(guidance.action)
                }
                .buttonStyle(FocusTracePrimaryButtonStyle())
                .controlSize(.large)
            }
            if state.currentTaskID != nil {
                Button("Agent 还在运行？保存返回点再切走") {
                    state.showTaskParking = true
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var parkedTasksCard: some View {
        GroupBox("待返回工作流") {
            VStack(spacing: 0) {
                ForEach(state.activeTaskParkings) { parking in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .foregroundStyle(.blue)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(state.taskName(for: parking.taskID))
                                .font(.headline)
                            Text("回来先做：\(parking.resumeCue)")
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Text("离开于")
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
                        if state.isSpaceWorkflowModeEnabled {
                            Label("切回对应桌面继续", systemImage: "rectangle.2.swap")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.blue)
                        } else {
                            Button("继续工作流") { state.resumeTaskParking(parking.id) }
                                .buttonStyle(.borderedProminent)
                        }
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
        GroupBox {
            DisclosureGroup(
                "管理工作流与允许应用",
                isExpanded: workflowManagementExpansion
            ) {
            VStack(spacing: 0) {
                ForEach(state.activeTasks) { task in
                    let isCurrentWorkflow = state.isSpaceWorkflowModeEnabled
                        ? state.currentSpaceWorkflowID == task.id
                        : state.currentTaskID == task.id
                    HStack {
                        Button {
                            if state.isSpaceWorkflowModeEnabled {
                                state.bindCurrentSpace(to: task.id)
                            } else {
                                state.switchTask(to: task.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: isCurrentWorkflow ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isCurrentWorkflow ? FocusTraceTheme.mint : .secondary)
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
                        .help(
                            state.isSpaceWorkflowModeEnabled
                                ? "将当前桌面绑定到“\(task.title)”"
                                : "切换到“\(task.title)”"
                        )
                        Spacer()
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
                        "还没有工作流",
                        systemImage: "checklist",
                        description: Text("先起一个名称即可，允许应用可以稍后设置。")
                    )
                    .frame(height: 150)
                }
                HStack {
                    Button("新建工作流", systemImage: "plus") { showingNewTask = true }
                    Spacer()
                }
                .padding(.top, 12)

                if !state.inactiveWorkflows.isEmpty {
                    Divider().padding(.vertical, 10)
                    DisclosureGroup(
                        "已结束工作流（\(state.inactiveWorkflows.count)）",
                        isExpanded: $showCompletedWorkflows
                    ) {
                        ForEach(state.inactiveWorkflows) { workflow in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workflow.title)
                                    if workflow.workflowLifecycle == .archived {
                                        Text("已归档")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if let completedAt = workflow.completedAt {
                                        Text("完成于 \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("编辑") { editingTask = workflow }
                                Button("重新打开") { state.reopenWorkflow(workflow.id) }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .focusTraceDisclosureHitTarget(
                        isExpanded: $showCompletedWorkflows
                    )
                }
            }
            .padding(8)
            }
            .focusTraceDisclosureHitTarget(
                isExpanded: workflowManagementExpansion
            )
        }
    }

    private var workflowManagementExpansion: Binding<Bool> {
        Binding(
            get: { showWorkflowManagement || state.activeTasks.isEmpty },
            set: { showWorkflowManagement = $0 }
        )
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

    private func perform(_ action: FlowNextAction) {
        switch action {
        case .resumeCapture:
            state.setCapturePaused(false)
        case .createWorkflow:
            showingNewTask = true
            showWorkflowManagement = true
        case .bindWorkflow:
            state.showTaskSwitcher = true
        case .viewFocus:
            break
        case .openSchedule:
            state.selectedAppSection = .settings
        case let .startFocus(minutes):
            state.requestStartFocus(minutes: minutes)
        }
    }
}

struct FocusToolSetupSheet: View {
    @ObservedObject var state: ApplicationState
    @State private var apps: [AppIdentity] = []
    @State private var selectedBundleIDs = Set<String>()
    @State private var usedRecentHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("第一次专注前，确认会用到的工具")
                    .font(.title2.bold())
                Text("只设置一次，以后这个工作流直接开始专注。")
                    .foregroundStyle(.secondary)
            }

            if usedRecentHistory {
                Label("已根据这个工作流最近使用过的应用预选；请取消微信等非必要应用。", systemImage: "wand.and.stars")
                    .font(.callout)
                    .foregroundStyle(.blue)
            } else {
                Text("请选择本轮确实需要的应用。FocusTrace 不读取窗口标题或网页内容。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            List(apps, id: \.bundleID) { app in
                Toggle(isOn: binding(for: app.bundleID)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                        Text(app.bundleID)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(height: 260)

            HStack {
                Text("已选择 \(selectedBundleIDs.count) 个")
                    .font(.caption)
                    .foregroundStyle(selectedBundleIDs.isEmpty ? .orange : .secondary)
                Spacer()
                Button("取消") { state.cancelFocusToolSetup() }
                Button("确认并开始专注") {
                    state.confirmFocusToolsAndStart(selectedBundleIDs)
                }
                .buttonStyle(FocusTracePrimaryButtonStyle())
                .disabled(selectedBundleIDs.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
        .focusTraceScreen()
        .focusTraceVisualSystem()
        .onAppear { loadApps() }
    }

    private func loadApps() {
        let recent = state.suggestedAppsForCurrentWorkflow()
        if !recent.isEmpty {
            usedRecentHistory = true
            apps = recent
            selectedBundleIDs = Set(recent.map(\.bundleID))
        } else {
            usedRecentHistory = false
            apps = state.availableApps()
        }
    }

    private func binding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { selectedBundleIDs.contains(bundleID) },
            set: { selected in
                if selected { selectedBundleIDs.insert(bundleID) }
                else { selectedBundleIDs.remove(bundleID) }
            }
        )
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
                .buttonStyle(FocusTracePrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 500)
        .focusTraceScreen()
        .focusTraceVisualSystem()
    }
}
