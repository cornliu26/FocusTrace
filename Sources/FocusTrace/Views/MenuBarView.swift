import AppKit
import SwiftUI
import FocusTraceCore

struct MenuBarView: View {
    @ObservedObject var state: ApplicationState
    @Environment(\.openWindow) private var openWindow
    @State private var workflowToComplete: FocusTaskModel?
    @State private var showingQuickWorkflowCreator = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                FocusTraceBrandMark(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FOCUSTRACE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(FocusTraceTheme.mint)
                    Text(menuTitle)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
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
            } else {
                primaryAction
            }

            if state.currentTaskID != nil {
                Button("Agent 等待：挂起当前工作流") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                    state.showTaskParking = true
                }
            }

            if !state.activeTaskParkings.isEmpty {
                Menu("待返回工作流（\(state.activeTaskParkings.count)）") {
                    ForEach(state.activeTaskParkings) { parking in
                        if state.isSpaceWorkflowModeEnabled {
                            Label(
                                "\(state.taskName(for: parking.taskID)) · 切回对应桌面",
                                systemImage: "rectangle.2.swap"
                            )
                        } else {
                            Button {
                                state.resumeTaskParking(parking.id)
                            } label: {
                                Text("\(state.taskName(for: parking.taskID)) · \(parking.resumeCue)")
                            }
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

            HStack {
                Button("打开今日回顾") {
                    openMain(.review)
                }
                Spacer()
                moreMenu
            }
        }
        .padding(16)
        .frame(width: 340)
        .focusTraceScreen()
        .focusTraceVisualSystem()
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
        .onAppear {
            state.start()
            state.refreshSpaceContextForMenuPresentation()
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        let guidance = state.flowGuidance
        switch guidance.action {
        case .bindWorkflow:
            Menu(guidance.buttonTitle) {
                ForEach(state.activeTasks) { workflow in
                    Button(workflow.title) { state.bindCurrentSpace(to: workflow.id) }
                }
                Divider()
                Button("新建工作流") { showingQuickWorkflowCreator = true }
            }
            .buttonStyle(.borderedProminent)
        default:
            Button(guidance.buttonTitle) { perform(guidance.action) }
                .buttonStyle(FocusTracePrimaryButtonStyle())
        }
    }

    private var moreMenu: some View {
        Menu("更多") {
            Button("打开专注训练") { openMain(.focus) }
            Button("查看三步使用方法") {
                openMain(.focus)
                state.showQuickStart = true
            }
            Button("新建工作流并绑定当前桌面") {
                showingQuickWorkflowCreator = true
            }
            if !state.isSpaceWorkflowModeEnabled && !state.activeTasks.isEmpty {
                Menu("手动切换工作流") {
                    ForEach(state.activeTasks) { task in
                        Button(task.title) { state.switchTask(to: task.id) }
                    }
                    Divider()
                    Button("停止当前工作流") { state.switchTask(to: nil) }
                }
            }
            Divider()
            Button(state.preferences.capturePaused ? "恢复记录" : "暂停记录") {
                state.setCapturePaused(!state.preferences.capturePaused)
            }
            Button("设置") { openMain(.settings) }
            Divider()
            Button("退出 FocusTrace") { NSApp.terminate(nil) }
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
                Text("桌面识别算法已修正，旧绑定需在目标桌面重新绑定（\(state.needsRebindBindings.count) 个待恢复）。")
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
            } else if !state.activeTasks.isEmpty {
                Label("从上方选择一次；之后切桌面会自动恢复", systemImage: "arrow.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .background(
            FocusTraceTheme.mint.opacity(0.065),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(FocusTraceTheme.mint.opacity(0.12), lineWidth: 1)
        }
    }

    private func perform(_ action: FlowNextAction) {
        switch action {
        case .resumeCapture:
            state.setCapturePaused(false)
        case .createWorkflow:
            showingQuickWorkflowCreator = true
        case .bindWorkflow:
            break
        case .viewFocus:
            openMain(.focus)
        case .openSchedule:
            openMain(.settings)
        case let .startFocus(minutes):
            state.requestStartFocus(minutes: minutes)
            if state.showFocusToolSetup {
                openMain(.focus)
            }
        }
    }

    private func openMain(_ section: AppSection) {
        state.selectedAppSection = section
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
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
        if state.activeTasks.isEmpty { return "还没有工作流" }
        if state.isSpaceWorkflowModeEnabled && state.currentSpaceWorkflowID == nil {
            return "桌面未绑定 · 不归因到旧工作流"
        }
        if state.currentTaskID == nil { return "当前桌面未绑定工作流" }
        return state.isRecording ? "应用切换记录中" : "工作时段之外"
    }

    private var menuTitle: String {
        state.currentFocus == nil
            ? (state.currentTask?.title ?? "等待绑定工作流")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建并绑定当前桌面")
                .font(.title2.bold())
            Text("只需给工作流起名。创建后自动绑定当前桌面，其余设置稍后再补。")
                .foregroundStyle(.secondary)
            TextField("例如：排查登录问题", text: $title)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("创建并绑定") {
                    state.createWorkflowAndBindCurrentSpace(
                        title: title,
                        expectedOutcome: ""
                    )
                    dismiss()
                }
                .buttonStyle(FocusTracePrimaryButtonStyle())
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440)
        .focusTraceScreen()
        .focusTraceVisualSystem()
    }
}
