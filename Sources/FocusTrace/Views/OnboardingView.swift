import SwiftUI
import FocusTraceCore

struct OnboardingView: View {
    @ObservedObject var state: ApplicationState
    @ObservedObject private var preferences: AppPreferences
    @State private var taskTitle = "今天的主线工作"
    @State private var expectedOutcome = ""
    @State private var runningApps: [AppIdentity] = []
    @State private var selectedApps = Set<String>()
    @State private var showSchedule = false
    @State private var showDetails = false

    init(state: ApplicationState) {
        self.state = state
        self.preferences = state.preferences
    }

    var body: some View {
        ScrollView {
            Group {
                if state.activeTasks.isEmpty {
                    setupForm
                } else {
                    firstUseGuide
                }
            }
            .padding(26)
        }
        .frame(width: 690, height: 620)
        .focusTraceScreen()
        .focusTraceVisualSystem()
        .onAppear {
            runningApps = state.runningApps().filter { $0.bundleID != "com.apple.loginwindow" }
        }
    }

    private var setupForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                FocusTraceBrandMark(size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置第一个工作流")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("先起一个名字；下一页会告诉你怎样真正开始记录。")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("第一个工作流") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("例如：完成登录问题修复", text: $taskTitle)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .accessibilityIdentifier(
                            FocusTraceUXContract.workflowNameInputIdentifier
                        )
                    Text("现在只填名称即可；不会绑定 FocusTrace 窗口所在的桌面。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox {
                DisclosureGroup(
                    "自动记录：\(workScheduleSummary)",
                    isExpanded: $showSchedule
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        WeekdayPicker(preferences: preferences)
                        HStack {
                            TimePicker(title: "开始", minutes: $preferences.workStartMinutes)
                            TimePicker(title: "结束", minutes: $preferences.workEndMinutes)
                        }
                        if !preferences.isWithinWorkSchedule(Date()) {
                            Label("当前不在这个时段内，设置完成后会等到下个记录时段自动开始。", systemImage: "clock.badge.exclamationmark")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.top, 10)
                }
                .focusTraceDisclosureHitTarget(isExpanded: $showSchedule)
                .padding(8)
            }

            GroupBox {
                DisclosureGroup(
                    "可选：补充目标和专注时允许的应用",
                    isExpanded: $showDetails
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("期望产出（可选）", text: $expectedOutcome)
                            .textFieldStyle(.roundedBorder)

                        Text("允许应用只在专注训练时使用，前三天基线记录不要求现在设置。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        List(runningApps, id: \.bundleID) { app in
                            Toggle(isOn: appBinding(app.bundleID)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                    Text(app.bundleID)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .frame(height: 170)
                    }
                    .padding(.top, 10)
                }
                .focusTraceDisclosureHitTarget(isExpanded: $showDetails)
                .padding(8)
            }

            GroupBox {
                Label {
                    Text("只记录前台应用、工作流标签和时间；不读取窗口标题、网页地址、聊天对象或键盘内容。数据只保存在本机，也不用于 ADHD 诊断。")
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .foregroundStyle(.secondary)
                .padding(5)
            }

            HStack {
                Text("必填项只有工作流名称，其余都可以稍后设置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("创建并继续") {
                    state.createFirstWorkflowForOnboarding(
                        title: taskTitle,
                        expectedOutcome: expectedOutcome,
                        allowedBundleIDs: selectedApps
                    )
                }
                .buttonStyle(FocusTracePrimaryButtonStyle())
                .controlSize(.large)
                .disabled(
                    preferences.workdayNumbers.isEmpty
                        || taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
    }

    private var firstUseGuide: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                FocusTraceBrandMark(size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("工作流已创建")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("再看完这三步，你就可以关掉主窗口正常工作。")
                        .foregroundStyle(.secondary)
                }
            }

            Label(
                state.activeTasks.first?.title ?? "第一个工作流",
                systemImage: "checkmark.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(FocusTraceTheme.mint)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                FocusTraceTheme.mint.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

            VStack(spacing: 10) {
                ForEach(
                    FocusTraceGettingStartedContract.steps.filter {
                        $0.id != .createWorkflow
                    }
                ) { step in
                    gettingStartedStep(
                        step,
                        isCurrent: step.id == state.gettingStartedPhase
                    )
                }
            }

            Label(
                "桌面绑定只能从屏幕顶部状态栏完成，因为主窗口可能正在另一个桌面。",
                systemImage: "menubar.rectangle"
            )
            .font(.callout)
            .padding(12)
            .background(
                FocusTraceTheme.sky.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

            HStack {
                Text("以后可从状态栏“更多 → 查看新手教学”随时重看。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(
                    state.gettingStartedPhase == .bindDesktop
                        ? "完成设置，去状态栏绑定"
                        : "完成设置"
                ) {
                    state.completeOnboarding()
                }
                .buttonStyle(FocusTracePrimaryButtonStyle())
                .controlSize(.large)
            }
        }
    }

    private func gettingStartedStep(
        _ step: FocusTraceGettingStartedStep,
        isCurrent: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isCurrent ? "arrow.right.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isCurrent ? FocusTraceTheme.sky : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(step.title)
                        .font(.headline)
                    if isCurrent {
                        Text("下一步")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(FocusTraceTheme.sky)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                FocusTraceTheme.sky.opacity(0.1),
                                in: Capsule()
                            )
                    }
                }
                Text(step.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(12)
        .background(
            isCurrent ? FocusTraceTheme.sky.opacity(0.06) : Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private var workScheduleSummary: String {
        let start = timeText(preferences.workStartMinutes)
        let end = timeText(preferences.workEndMinutes)
        return "每周 \(preferences.workdayNumbers.count) 天，\(start)–\(end)"
    }

    private func timeText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func appBinding(_ bundleID: String) -> Binding<Bool> {
        Binding(
            get: { selectedApps.contains(bundleID) },
            set: { selected in
                if selected { selectedApps.insert(bundleID) }
                else { selectedApps.remove(bundleID) }
            }
        )
    }
}

struct QuickStartSheet: View {
    @ObservedObject var state: ApplicationState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                FocusTraceBrandMark(size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("FocusTrace 新手教学")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("完成当前一步就够了；训练和 Codex 都可以以后再开。")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 9) {
                ForEach(
                    Array(FocusTraceGettingStartedContract.steps.enumerated()),
                    id: \.element.id
                ) { index, step in
                    guideStep(
                        number: index + 1,
                        step: step,
                        isCurrent: step.id == state.gettingStartedPhase
                    )
                }
            }

            Text("被消息或 Agent 等待打断时：新事情先放进需求箱；离开当前工作流前，保存一句“回来后第一步”。")
                .font(.callout)
                .padding(12)
                .background(
                    FocusTraceTheme.mint.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                Button(primaryActionTitle) {
                    performPrimaryAction()
                }
                .buttonStyle(FocusTracePrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620)
        .focusTraceScreen()
        .focusTraceVisualSystem()
    }

    private var primaryActionTitle: String {
        switch state.gettingStartedPhase {
        case .createWorkflow:
            return "创建工作流"
        case .bindDesktop:
            return "关闭后去状态栏绑定"
        case .workNormally:
            return "开始正常工作"
        case .reviewEvidence:
            return "打开回顾分析"
        }
    }

    private func performPrimaryAction() {
        switch state.gettingStartedPhase {
        case .createWorkflow:
            dismiss()
            state.showTaskCreator = true
        case .bindDesktop, .workNormally:
            dismiss()
        case .reviewEvidence:
            state.selectedAppSection = .review
            dismiss()
        }
    }

    private func guideStep(
        number: Int,
        step: FocusTraceGettingStartedStep,
        isCurrent: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 30, height: 30)
                .foregroundStyle(isCurrent ? Color.white : Color.primary)
                .background(
                    isCurrent ? FocusTraceTheme.sky : Color.primary.opacity(0.08),
                    in: Circle()
                )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(step.title).font(.headline)
                    if isCurrent {
                        Text("当前")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(FocusTraceTheme.sky)
                    }
                }
                Text(step.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
        }
        .padding(10)
        .background(
            isCurrent ? FocusTraceTheme.sky.opacity(0.06) : Color.clear,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }
}

struct WeekdayPicker: View {
    @ObservedObject var preferences: AppPreferences
    private let days = [
        (2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六"), (1, "日")
    ]

    var body: some View {
        HStack {
            Text("工作日")
            ForEach(days, id: \.0) { day in
                Toggle(
                    day.1,
                    isOn: Binding(
                        get: { preferences.workdayNumbers.contains(day.0) },
                        set: { isOn in
                            if isOn {
                                preferences.workdayNumbers.insert(day.0)
                            } else {
                                preferences.workdayNumbers.remove(day.0)
                            }
                        }
                    )
                )
                .toggleStyle(.button)
            }
        }
    }
}

struct TimePicker: View {
    let title: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(title, selection: dateBinding, displayedComponents: .hourAndMinute)
            .datePickerStyle(.field)
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                let start = Calendar.current.startOfDay(for: Date())
                return Calendar.current.date(byAdding: .minute, value: minutes, to: start) ?? start
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }
}
