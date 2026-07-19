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
            TextField("期望产出（可选）", text: $outcome)

            Text("此任务允许使用的应用")
                .font(.headline)
            Text("这些应用之间的切换仍会记录，但不会被当作偏离任务。")
                .font(.caption)
                .foregroundStyle(.secondary)

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
        .onAppear { runningApps = state.runningApps() }
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
}

struct TaskSwitcherSheet: View {
    @ObservedObject var state: ApplicationState
    @Environment(\.dismiss) private var dismiss
    @State private var showingNewTask = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("切换主任务")
                .font(.title2.bold())
            List(state.activeTasks) { task in
                Button {
                    state.switchTask(to: task.id)
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
