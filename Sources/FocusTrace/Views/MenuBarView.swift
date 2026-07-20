import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: ApplicationState
    @Environment(\.openWindow) private var openWindow
    @State private var workflowToComplete: FocusTaskModel?
    @State private var showingQuickWorkflowCreator = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: state.currentFocusID == nil ? "scope" : "timer")
                    .font(.title2)
                    .foregroundStyle(state.currentFocusID == nil ? Color.secondary : Color.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(menuTitle)
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if state.currentFocusID != nil {
                ProgressView(
                    value: Double(state.focusElapsedSeconds),
                    total: Double(max(1, state.currentFocus?.targetSeconds ?? 1))
                )
                HStack {
                    Text(focusProgressText)
                        .monospacedDigit()
                    Spacer()
                    Button("结束并记录") { state.endFocus() }
                }
            } else if state.currentTaskID != nil {
                Button("开始 \(state.currentPlan.focusMinutes) 分钟专注") {
                    state.startFocus()
                }
                .buttonStyle(.borderedProminent)
            } else if state.activeTasks.isEmpty {
                Button("新建工作流并绑定当前桌面") {
                    showingQuickWorkflowCreator = true
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("选择当前任务") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                    state.showTaskSwitcher = true
                }
                .buttonStyle(.borderedProminent)
            }

            if state.currentTaskID != nil {
                Button("Agent 等待：挂起当前任务") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                    state.showTaskParking = true
                }
            }

            if !state.activeTaskParkings.isEmpty {
                Menu("待返回任务（\(state.activeTaskParkings.count)）") {
                    ForEach(state.activeTaskParkings) { parking in
                        Button {
                            state.resumeTaskParking(parking.id)
                        } label: {
                            Text("\(state.taskName(for: parking.taskID)) · \(parking.resumeCue)")
                        }
                    }
                }
            }

            Divider()
            spaceWorkflowSection

            if let undo = state.pendingWorkflowUndo {
                HStack(spacing: 8) {
                    Text("已完成“\(undo.title)”")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button("撤销") { state.undoWorkflowCompletion() }
                }
            }

            Divider()

            if state.isSpaceWorkflowModeEnabled {
                Label("切换工作流：切换 macOS 桌面", systemImage: "rectangle.2.swap")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Menu("切换任务") {
                    ForEach(state.activeTasks) { task in
                        Button {
                            state.switchTask(to: task.id)
                        } label: {
                            if task.id == state.currentTaskID {
                                Label(task.title, systemImage: "checkmark")
                            } else {
                                Text(task.title)
                            }
                        }
                    }
                    Divider()
                    Button("停止当前任务") { state.switchTask(to: nil) }
                }
            }

            Button(state.preferences.capturePaused ? "恢复记录" : "暂停记录") {
                state.setCapturePaused(!state.preferences.capturePaused)
            }

            HStack {
                Button("打开今日回顾") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
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
            Text("会结束当前区间并释放它的桌面绑定；30 秒内可以撤销，撤销后需重新绑定桌面。")
        }
        .sheet(isPresented: $showingQuickWorkflowCreator) {
            QuickWorkflowCreatorSheet(state: state)
        }
    }

    @ViewBuilder
    private var spaceWorkflowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: state.currentSpaceWorkflowID == nil ? "rectangle.on.rectangle" : "rectangle.fill.on.rectangle.fill")
                    .foregroundStyle(state.currentSpaceWorkflowID == nil ? Color.secondary : Color.blue)
                Text(state.spaceContextText)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
            }

            if !state.needsRebindBindings.isEmpty && !state.isSpaceWorkflowModeEnabled {
                Text("重启后需逐个访问原桌面并重新绑定（\(state.needsRebindBindings.count) 个待恢复）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if state.currentSpaceWorkflowID != nil {
                HStack {
                    Button("解除当前桌面") { state.unbindCurrentSpace() }
                    Spacer()
                    if let workflow = state.currentSpaceWorkflow {
                        Button("完成工作流") { workflowToComplete = workflow }
                    }
                }
            } else {
                if !state.activeTasks.isEmpty {
                    Menu(state.isSpaceWorkflowModeEnabled ? "绑定当前桌面到…" : "启用并绑定当前桌面到…") {
                        ForEach(state.activeTasks) { workflow in
                            Button(workflow.title) {
                                state.bindCurrentSpace(to: workflow.id)
                            }
                        }
                    }
                }
                Button("新建工作流并绑定此桌面") {
                    showingQuickWorkflowCreator = true
                }
            }
        }
    }

    private var statusText: String {
        if let focus = state.currentFocus {
            if state.isCurrentFocusPaused {
                return "专注已暂停 · 回到“\(state.focusWorkflowName)”桌面自动恢复"
            }
            if let grace = state.focusDepartureGraceRemaining {
                return "暂时离开 · \(grace) 秒内返回不暂停"
            }
            return "专注中 · 目标 \(focus.targetSeconds / 60) 分钟"
        }
        if state.preferences.capturePaused { return "记录已暂停" }
        if state.activeTasks.isEmpty { return "仅记录应用切换 · 还没有任务" }
        if state.isSpaceWorkflowModeEnabled && state.currentSpaceWorkflowID == nil {
            return "桌面未绑定 · 不归因到旧工作流"
        }
        if state.currentTaskID == nil { return "仅记录应用切换 · 未选主任务" }
        return state.isRecording ? "应用切换记录中" : "工作时段之外"
    }

    private var menuTitle: String {
        state.currentFocus == nil
            ? (state.currentTask?.title ?? "未选择任务")
            : state.focusWorkflowName
    }

    private var focusProgressText: String {
        if state.isCurrentFocusPaused { return "计时已暂停" }
        if let grace = state.focusDepartureGraceRemaining {
            return "离开宽限 \(grace) 秒"
        }
        return state.focusRemainingSeconds > 0
            ? "剩余 \(format(state.focusRemainingSeconds))"
            : "目标已完成"
    }

    private func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct QuickWorkflowCreatorSheet: View {
    @ObservedObject var state: ApplicationState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var expectedOutcome = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建并绑定当前桌面")
                .font(.title2.bold())
            Text("只需先给工作流起名；期望产出和允许应用可以稍后补充。")
                .foregroundStyle(.secondary)
            TextField("工作流名称", text: $title)
                .textFieldStyle(.roundedBorder)
            TextField("期望产出（可选）", text: $expectedOutcome)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("创建并绑定") {
                    state.createWorkflowAndBindCurrentSpace(
                        title: title,
                        expectedOutcome: expectedOutcome
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear {
            if title.isEmpty { title = state.suggestedWorkflowTitle }
        }
    }
}
