import SwiftUI
import FocusTraceCore

struct TaskEditorSheet: View {
    @ObservedObject var state: ApplicationState
    let editingTask: FocusTaskModel?
    let bindCurrentSpaceOnCreate: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var outcome: String
    @State private var selectedApps: Set<String>
    @State private var runningApps: [AppIdentity] = []
    @State private var showDetails: Bool

    private var reusableTasks: [FocusTaskModel] {
        state.activeTasks.filter { $0.id != editingTask?.id && !$0.allowedBundleIDs.isEmpty }
    }

    init(
        state: ApplicationState,
        editingTask: FocusTaskModel? = nil,
        bindCurrentSpaceOnCreate: Bool = false
    ) {
        self.state = state
        self.editingTask = editingTask
        self.bindCurrentSpaceOnCreate = bindCurrentSpaceOnCreate
        _title = State(initialValue: editingTask?.title ?? "")
        _outcome = State(initialValue: editingTask?.expectedOutcome ?? "")
        _selectedApps = State(initialValue: Set(editingTask?.allowedBundleIDs ?? []))
        _showDetails = State(initialValue: editingTask != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                FocusTraceBrandMark(size: 38)
                Text(editingTask == nil ? "新建工作流" : "编辑工作流")
                    .font(.system(.title2, design: .rounded, weight: .bold))
            }
            TextField("工作流名称", text: $title)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("先保存名称就可以开始；其余信息只在你需要专注训练时再补。")
                .font(.caption)
                .foregroundStyle(.secondary)

            DisclosureGroup("目标与允许应用（可稍后设置）", isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("期望产出 / 当前上下文（可选）", text: $outcome)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("专注时允许的工具")
                            .font(.headline)
                        Spacer()
                        Menu("复用其他工作流") {
                            ForEach(reusableTasks) { task in
                                Button(task.title) { reuseApps(from: task) }
                            }
                        }
                        .disabled(reusableTasks.isEmpty)
                    }
                    Text("只影响专注提醒；普通记录不要求设置。Chrome 可以同时属于多个工作流。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("已选择 \(selectedApps.count) 个应用")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        if selectedApps.isEmpty {
                            Text("首次专注前再设置即可")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }

                    List(runningApps, id: \.bundleID) { app in
                        Toggle(isOn: binding(for: app.bundleID)) {
                            VStack(alignment: .leading) {
                                Text(app.name)
                                Text(app.bundleID)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .frame(height: 245)
                }
                .padding(.top, 10)
            }

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button(editingTask == nil ? "创建工作流" : "保存") {
                    let didSave: Bool
                    if let editingTask {
                        didSave = state.updateTask(
                            id: editingTask.id,
                            title: title,
                            expectedOutcome: outcome,
                            allowedBundleIDs: selectedApps
                        )
                    } else {
                        if bindCurrentSpaceOnCreate {
                            didSave = state.createWorkflowAndBindCurrentSpace(
                                title: title,
                                expectedOutcome: outcome,
                                allowedBundleIDs: selectedApps
                            )
                        } else {
                            didSave = state.createTask(
                                title: title,
                                expectedOutcome: outcome,
                                allowedBundleIDs: selectedApps
                            )
                        }
                    }
                    if didSave { dismiss() }
                }
                .buttonStyle(FocusTracePrimaryButtonStyle())
                .disabled(
                    WorkflowNamePolicy.normalizedTitle(title) == nil
                        || validationMessage != nil
                )
            }
        }
        .padding(22)
        .frame(width: 560, height: showDetails ? 560 : 230)
        .focusTraceScreen()
        .focusTraceVisualSystem()
        .onAppear { loadVisibleApps() }
    }

    private var validationMessage: String? {
        guard WorkflowNamePolicy.normalizedTitle(title) != nil else {
            return nil
        }
        return state.workflowNameValidationMessage(
            for: title,
            excluding: editingTask?.id
        )
    }

    private func binding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { selectedApps.contains(bundleID) },
            set: { selected in
                if selected { selectedApps.insert(bundleID) }
                else { selectedApps.remove(bundleID) }
            }
        )
    }

    private func reuseApps(from task: FocusTaskModel) {
        selectedApps = Set(task.allowedBundleIDs)
        loadVisibleApps()
    }

    private func loadVisibleApps() {
        var apps = state.availableApps()
        let visibleBundleIDs = Set(apps.map(\.bundleID))
        for bundleID in selectedApps.subtracting(visibleBundleIDs) {
            apps.append(AppIdentity(bundleID: bundleID, name: bundleID))
        }
        runningApps = apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

struct TaskSwitcherSheet: View {
    @ObservedObject var state: ApplicationState
    @Environment(\.dismiss) private var dismiss
    @State private var showingNewTask = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.isSpaceWorkflowModeEnabled ? "绑定当前桌面到工作流" : "切换工作流")
                .font(.title2.bold())
            List(state.activeTasks) { task in
                Button {
                    if state.isSpaceWorkflowModeEnabled {
                        state.bindCurrentSpace(to: task.id)
                    } else {
                        state.switchTask(to: task.id)
                    }
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(task.title)
                            if !task.expectedOutcome.isEmpty {
                                Text(task.expectedOutcome)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if task.id == state.currentTaskID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack {
                Button("新建工作流") { showingNewTask = true }
                Spacer()
                Button("取消") {
                    state.showTaskSwitcher = false
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(width: 480, height: 420)
        .focusTraceScreen()
        .focusTraceVisualSystem()
        .sheet(isPresented: $showingNewTask) {
            TaskEditorSheet(
                state: state,
                bindCurrentSpaceOnCreate: state.currentSpaceWorkflowID == nil
            )
        }
    }
}

struct TaskParkingSheet: View {
    @ObservedObject var state: ApplicationState
    @Environment(\.dismiss) private var dismiss
    @State private var resumeCue = ""
    @State private var reminderMinutes: Int? = 10
    @State private var destinationTaskID: UUID?
    private let examples = [
        "查看 Agent 结果，然后运行测试",
        "确认构建结果，处理第一个错误",
        "检查改动 diff，决定是否继续"
    ]

    private var destinationTasks: [FocusTaskModel] {
        state.activeTasks.filter { $0.id != state.currentTaskID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("保存返回点，再切去别的工作流")
                    .font(.title2.bold())
                Text("当前：\(state.currentTask?.title ?? "未选择工作流")")
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bookmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(FocusTraceTheme.mint)
                Text("当 Agent、编译或测试还在运行，而你想先做别的事时，用这里记下“回来后立刻做的第一步”。它不是工作总结，也不会把文字交给 Codex。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                FocusTraceTheme.mint.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )

            VStack(alignment: .leading, spacing: 7) {
                Text("回来后立刻做什么？")
                    .font(.headline)
                TextField("例如：查看 Agent 输出，然后跑一次测试", text: $resumeCue)
                    .textFieldStyle(.roundedBorder)
                Text("写动作，不写背景。例如“看结果并跑测试”，而不是“继续这个问题”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(examples, id: \.self) { example in
                        Button(example) {
                            resumeCue = example
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }

            Picker("提醒我返回", selection: $reminderMinutes) {
                Text("不提醒").tag(Int?.none)
                Text("5 分钟").tag(Int?.some(5))
                Text("10 分钟").tag(Int?.some(10))
                Text("20 分钟").tag(Int?.some(20))
                Text("30 分钟").tag(Int?.some(30))
            }

            if state.isSpaceWorkflowModeEnabled {
                Label("保存后手动切换 macOS 桌面；回到这个桌面时，FocusTrace 会把这一步重新显示出来。", systemImage: "rectangle.2.swap")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("接下来做", selection: $destinationTaskID) {
                    Text("暂不选择").tag(UUID?.none)
                    ForEach(destinationTasks) { task in
                        Text(task.title).tag(UUID?.some(task.id))
                    }
                }
            }

            if state.currentFocusID != nil {
                Label("保存返回点会结束当前专注轮次，并请你记录本轮结果。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("取消") {
                    state.showTaskParking = false
                    dismiss()
                }
                Spacer()
                Button(parkingButtonTitle) {
                    state.parkCurrentTask(
                        resumeCue: resumeCue,
                        reminderMinutes: reminderMinutes,
                        switchTo: state.isSpaceWorkflowModeEnabled ? nil : destinationTaskID
                    )
                    dismiss()
                }
                .buttonStyle(FocusTracePrimaryButtonStyle())
                .disabled(resumeCue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 620)
        .focusTraceScreen()
        .focusTraceVisualSystem()
        .onAppear {
            if !state.isSpaceWorkflowModeEnabled && destinationTaskID == nil {
                destinationTaskID = destinationTasks.first?.id
            }
        }
    }

    private var parkingButtonTitle: String {
        if state.isSpaceWorkflowModeEnabled { return "保存返回点" }
        return destinationTaskID == nil ? "保存返回点" : "保存并切换"
    }
}
