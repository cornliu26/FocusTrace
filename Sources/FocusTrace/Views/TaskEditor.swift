import SwiftUI
import FocusTraceCore

struct TaskEditorSheet: View {
    @ObservedObject var state: ApplicationState
    let editingTask: FocusTaskModel?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var outcome: String
    @State private var selectedApps: Set<String>
    @State private var runningApps: [AppIdentity] = []

    private var reusableTasks: [FocusTaskModel] {
        state.activeTasks.filter { $0.id != editingTask?.id && !$0.allowedBundleIDs.isEmpty }
    }

    init(state: ApplicationState, editingTask: FocusTaskModel? = nil) {
        self.state = state
        self.editingTask = editingTask
        _title = State(initialValue: editingTask?.title ?? "")
        _outcome = State(initialValue: editingTask?.expectedOutcome ?? "")
        _selectedApps = State(initialValue: Set(editingTask?.allowedBundleIDs ?? []))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editingTask == nil ? "新建任务" : "编辑任务")
                .font(.title2.bold())
            TextField("任务名称", text: $title)
            TextField("期望产出 / 当前上下文（可选）", text: $outcome)

            HStack {
                Text("此任务可能用到的工具")
                    .font(.headline)
                Spacer()
                Menu("复用已有任务的工具") {
                    ForEach(reusableTasks) { task in
                        Button(task.title) { reuseApps(from: task) }
                    }
                }
                .disabled(reusableTasks.isEmpty)
            }
            Text("允许应用是工具集合，不是任务归属规则。Chrome 可以同时属于多个任务；FocusTrace 不读取标签页，也不会把 Chrome 内部跳转推断为任务切换。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("已选择 \(selectedApps.count) 个应用")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if selectedApps.isEmpty {
                    Text("专注训练前建议至少选择一个")
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
            .frame(minHeight: 260)

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") {
                    if let editingTask {
                        state.updateTask(
                            id: editingTask.id,
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
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560, height: 520)
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
            Text(state.isSpaceWorkflowModeEnabled ? "绑定当前桌面到工作流" : "切换主任务")
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
                Button("新建任务") { showingNewTask = true }
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
            TaskEditorSheet(state: state)
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
                Text("挂起当前任务")
                    .font(.title2.bold())
                Text(state.currentTask?.title ?? "未选择任务")
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

            Picker("接下来做", selection: $destinationTaskID) {
                Text("暂不选择").tag(UUID?.none)
                ForEach(destinationTasks) { task in
                    Text(task.title).tag(UUID?.some(task.id))
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
                Button(destinationTaskID == nil ? "挂起任务" : "挂起并切换") {
                    state.parkCurrentTask(
                        resumeCue: resumeCue,
                        reminderMinutes: reminderMinutes,
                        switchTo: destinationTaskID
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
            if destinationTaskID == nil {
                destinationTaskID = destinationTasks.first?.id
            }
        }
    }
}
