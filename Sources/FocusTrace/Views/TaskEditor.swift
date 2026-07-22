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
            Text(editingTask == nil ? "新建工作流" : "编辑工作流")
                .font(.title2.bold())
            TextField("工作流名称", text: $title)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
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
                    if let editingTask {
                        state.updateTask(
                            id: editingTask.id,
                            title: title,
                            expectedOutcome: outcome,
                            allowedBundleIDs: selectedApps
                        )
                    } else {
                        if bindCurrentSpaceOnCreate {
                            state.createWorkflowAndBindCurrentSpace(
                                title: title,
                                expectedOutcome: outcome,
                                allowedBundleIDs: selectedApps
                            )
                        } else {
                            state.createTask(
                                title: title,
                                expectedOutcome: outcome,
                                allowedBundleIDs: selectedApps
                            )
                        }
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560, height: showDetails ? 560 : 230)
        .onAppear { loadVisibleApps() }
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

    private var destinationTasks: [FocusTaskModel] {
        state.activeTasks.filter { $0.id != state.currentTaskID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("挂起当前工作流")
                    .font(.title2.bold())
                Text(state.currentTask?.title ?? "未选择工作流")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("回来后的第一步")
                    .font(.headline)
                TextField("例如：查看 Agent 输出，然后跑一次测试", text: $resumeCue)
                    .textFieldStyle(.roundedBorder)
                Text("留下一个可执行的恢复线索，不用在脑中反复记着进度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("提醒我返回", selection: $reminderMinutes) {
                Text("不提醒").tag(Int?.none)
                Text("5 分钟").tag(Int?.some(5))
                Text("10 分钟").tag(Int?.some(10))
                Text("20 分钟").tag(Int?.some(20))
                Text("30 分钟").tag(Int?.some(30))
            }

            if state.isSpaceWorkflowModeEnabled {
                Label("挂起后直接切换 macOS 桌面，目标工作流会自动恢复。", systemImage: "rectangle.2.swap")
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
                Label("挂起会结束当前专注轮次，并请你记录本轮结果。", systemImage: "info.circle")
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
                .buttonStyle(.borderedProminent)
                .disabled(resumeCue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear {
            if !state.isSpaceWorkflowModeEnabled && destinationTaskID == nil {
                destinationTaskID = destinationTasks.first?.id
            }
        }
    }

    private var parkingButtonTitle: String {
        if state.isSpaceWorkflowModeEnabled { return "挂起，接着切换桌面" }
        return destinationTaskID == nil ? "挂起工作流" : "挂起并切换"
    }
}
