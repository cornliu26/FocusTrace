import AppKit
import SwiftUI
import FocusTraceCore

struct MenuBarView: View {
    @ObservedObject var state: ApplicationState
    @EnvironmentObject private var updateManager: UpdateManager
    @Environment(\.openWindow) private var openWindow
    @State private var workflowToComplete: FocusTaskModel?
    @State private var showingQuickWorkflowCreator = false
    @State private var showingRequirementCapture = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if state.currentFocusID != nil {
                activeFocusPanel
            } else {
                primaryAction
            }
            quickRequirementCapture
            if let checkpoint = state.resumedWorkflowCheckpoint {
                checkpointStrip(checkpoint)
            } else if state.currentTaskID != nil {
                returnPointButton
            }
            if !state.activeTaskParkings.isEmpty {
                parkedWorkflowsMenu
            }
            if let undo = state.pendingWorkflowUndo {
                undoStrip(undo)
            }
            contextStrip
            Divider().padding(.vertical, 1)
            footer
        }
        .padding(12)
        .frame(width: CGFloat(FocusTraceUXContract.menuBarWidth))
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
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
        .sheet(isPresented: $showingRequirementCapture) {
            QuickRequirementCaptureSheet(state: state)
        }
        .onAppear {
            state.start()
            state.refreshSpaceContextForMenuPresentation()
            Task {
                await updateManager.checkAutomatically(
                    enabled: state.preferences.automaticUpdateChecks
                )
            }
        }
    }

    private var quickRequirementCapture: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let queuePrompt = requirementQueuePrompt {
                Button {
                    openMain(.inbox)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: queuePrompt.icon)
                            .foregroundStyle(queuePrompt.color)
                        Text(queuePrompt.title)
                        Spacer()
                        Text("查看")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(queuePrompt.color)
                    }
                    .font(.caption.weight(.medium))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .background(
                    queuePrompt.color.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }

            Button {
                showingRequirementCapture = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(FocusTraceTheme.sky)
                    Text("收下一个需求")
                    Spacer()
                }
                .font(.caption.weight(.medium))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("先记下来，不切换或绑定当前工作流")
        }
    }

    private var requirementQueuePrompt: (
        title: String,
        icon: String,
        color: Color
    )? {
        let summary = state.requirementQueueSummary
        if summary.overdueCount > 0 {
            return (
                "\(summary.overdueCount) 个需求已逾期",
                "exclamationmark.circle.fill",
                FocusTraceTheme.coral
            )
        }
        if summary.dueTodayCount > 0 {
            return (
                "\(summary.dueTodayCount) 个需求今天截止",
                "calendar.badge.clock",
                FocusTraceTheme.amber
            )
        }
        if summary.needsPlanningCount > 0 {
            return (
                "\(summary.needsPlanningCount) 个需求待整理",
                "tray.full",
                FocusTraceTheme.sky
            )
        }
        return nil
    }

    private var header: some View {
        HStack(spacing: 9) {
            FocusTraceBrandMark(size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(menuTitle)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if state.currentFocusID != nil {
                Text(format(state.focusRemainingSeconds))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .monospacedDigit()
            }
        }
    }

    private var activeFocusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(
                value: Double(state.focusElapsedSeconds),
                total: Double(max(1, state.currentFocus?.targetSeconds ?? 1))
            )
            HStack(spacing: 8) {
                Text(focusProgressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("保存返回点") { showReturnPointSheet() }
                    .buttonStyle(.borderless)
                Button("结束") { state.endFocus() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    @ViewBuilder
    private var primaryAction: some View {
        let guidance = state.flowGuidance
        switch guidance.action {
        case .bindWorkflow:
            Menu {
                ForEach(state.activeTasks) { workflow in
                    Button(workflow.title) { state.bindCurrentSpace(to: workflow.id) }
                }
                Divider()
                Button("新建工作流") { showingQuickWorkflowCreator = true }
            } label: {
                primaryActionLabel(
                    guidance.buttonTitle,
                    systemImage: "rectangle.on.rectangle"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        default:
            Button {
                perform(guidance.action)
            } label: {
                primaryActionLabel(
                    guidance.buttonTitle,
                    systemImage: primaryActionIcon(guidance.action)
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func primaryActionLabel(
        _ title: String,
        systemImage: String
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .opacity(0.72)
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity)
    }

    private var returnPointButton: some View {
        Button {
            showReturnPointSheet()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "bookmark")
                Text("Agent 还在运行？保存返回点")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private func checkpointStrip(
        _ checkpoint: ResumedWorkflowCheckpoint
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundStyle(FocusTraceTheme.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text("回来先做")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(checkpoint.nextStep)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button {
                state.acknowledgeResumedWorkflowCheckpoint()
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderless)
            .help("这一步已开始")
        }
        .padding(9)
        .background(
            FocusTraceTheme.mint.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    private var parkedWorkflowsMenu: some View {
        Menu {
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
        } label: {
            Label(
                "待返回工作流 \(state.activeTaskParkings.count)",
                systemImage: "tray"
            )
            .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func undoStrip(_ undo: PendingWorkflowUndo) -> some View {
        HStack(spacing: 8) {
            Text("已完成“\(undo.title)”")
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Button("撤销") { state.undoWorkflowCompletion() }
                .buttonStyle(.borderless)
        }
    }

    private var contextStrip: some View {
        HStack(spacing: 7) {
            Image(systemName: state.currentSpaceWorkflowID == nil
                  ? "rectangle.on.rectangle"
                  : "rectangle.fill.on.rectangle.fill")
                .foregroundStyle(state.currentSpaceWorkflowID == nil
                                 ? Color.secondary
                                 : FocusTraceTheme.sky)
            Text(state.spaceContextText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 1)
    }

    private var footer: some View {
        HStack(spacing: 11) {
            Button {
                openMain(.inbox)
            } label: {
                Label("需求", systemImage: "tray")
            }
            Button {
                openMain(.review)
            } label: {
                Label("回顾", systemImage: "chart.line.uptrend.xyaxis")
            }
            Button {
                openMain(.focus)
            } label: {
                Label("训练", systemImage: "scope")
            }
            Spacer()
            moreMenu
        }
        .font(.caption)
        .buttonStyle(.borderless)
    }

    private var moreMenu: some View {
        Menu {
            Button("查看三步使用方法") {
                openMain(.focus)
                state.showQuickStart = true
            }
            Button("新建工作流并绑定当前桌面") {
                showingQuickWorkflowCreator = true
            }
            if state.currentTaskID != nil {
                Button("保存返回点") { showReturnPointSheet() }
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
            if state.currentSpaceWorkflowID != nil {
                Divider()
                Button("解除当前桌面") { state.unbindCurrentSpace() }
                if let workflow = state.currentSpaceWorkflow {
                    Button("完成当前工作流") { workflowToComplete = workflow }
                }
            }
            Divider()
            Button(state.preferences.capturePaused ? "恢复记录" : "暂停记录") {
                state.setCapturePaused(!state.preferences.capturePaused)
            }
            Button("设置") { openMain(.settings) }
            if let release = updateManager.availableRelease {
                Button("可更新到 \(release.version)…") { openMain(.settings) }
            } else {
                Button("检查更新") {
                    Task { await updateManager.checkForUpdates() }
                }
            }
            Divider()
            Button("退出 FocusTrace") { NSApp.terminate(nil) }
        } label: {
            Label("更多", systemImage: "ellipsis.circle")
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
        openWindow(id: FocusTraceWindowContract.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showReturnPointSheet() {
        openWindow(id: FocusTraceWindowContract.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
        state.showTaskParking = true
    }

    private var statusText: String {
        if let focus = state.currentFocus {
            if state.isCurrentFocusPaused {
                return "专注暂停"
            }
            if let grace = state.focusDepartureGraceRemaining {
                return "离开宽限 \(grace) 秒"
            }
            return "专注中 · \(focus.targetSeconds / 60) 分钟目标"
        }
        if state.preferences.capturePaused { return "记录暂停" }
        if state.activeTasks.isEmpty { return "未设置工作流" }
        if state.isSpaceWorkflowModeEnabled && state.currentSpaceWorkflowID == nil {
            return "当前桌面未绑定"
        }
        if state.currentTaskID == nil { return "当前桌面未绑定" }
        return state.isRecording ? "记录中" : "工作时段外"
    }

    private var statusColor: Color {
        if state.currentFocusID != nil {
            return state.isCurrentFocusPaused
                ? FocusTraceTheme.amber
                : FocusTraceTheme.mint
        }
        if state.preferences.capturePaused {
            return FocusTraceTheme.coral
        }
        return state.isRecording ? FocusTraceTheme.mint : Color.secondary
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

    private func primaryActionIcon(_ action: FlowNextAction) -> String {
        switch action {
        case .resumeCapture: return "record.circle"
        case .createWorkflow: return "plus"
        case .bindWorkflow: return "rectangle.on.rectangle"
        case .viewFocus: return "scope"
        case .openSchedule: return "calendar"
        case .startFocus: return "play.fill"
        }
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
