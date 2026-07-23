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
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    FocusTraceBrandMark(size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("设置当前工作流")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("输入名称后，当前桌面会自动绑定到这个工作流。")
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("当前工作流") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("例如：完成登录问题修复", text: $taskTitle)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                        Text("现在只填名称即可；创建后会自动绑定当前桌面并开始记录。")
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
                    Text("之后通常只需切换桌面；专注计时和允许应用都可以稍后设置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("开始记录当前工作流") {
                        state.completeOnboardingAndCreateTask(
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
            .padding(26)
        }
        .frame(width: 690, height: 620)
        .focusTraceScreen()
        .focusTraceVisualSystem()
        .onAppear {
            runningApps = state.runningApps().filter { $0.bundleID != "com.apple.loginwindow" }
        }
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
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                FocusTraceBrandMark(size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("FocusTrace 平时怎么用")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("正常工作只需要记住一条：一个桌面对应一个工作流。")
                        .foregroundStyle(.secondary)
                }
            }

            guideStep(
                number: "1",
                title: "切桌面就是切工作流",
                detail: "第一次绑定后自动识别，不需要每次再选。Codex、终端和浏览器只是工具，它们之间切换不等于换工作流。"
            )
            guideStep(
                number: "2",
                title: "平时直接工作，训练时再计时",
                detail: "记录会在工作时段自动进行。想训练注意力时，再点一次“开始专注”；前三个工作日只观察，不提醒。"
            )
            guideStep(
                number: "3",
                title: "Agent 等待时留一句恢复线索",
                detail: "写下回来后的第一步，然后切到另一个桌面。这样不用在脑中同时维持多个上下文。"
            )

            Text("不需要盯着时间轴工作。下班后再打开回顾；切换密度只是描述，不自动等于走神。")
                .font(.callout)
                .padding(12)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                if state.currentTaskID == nil {
                    Button(state.activeTasks.isEmpty ? "创建第一个工作流" : "绑定当前桌面") {
                        dismiss()
                        if state.activeTasks.isEmpty { state.showTaskCreator = true }
                        else { state.showTaskSwitcher = true }
                    }
                    .buttonStyle(FocusTracePrimaryButtonStyle())
                }
                Spacer()
                Button("知道了") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 570)
        .focusTraceScreen()
        .focusTraceVisualSystem()
    }

    private func guideStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text(number)
                .font(.headline)
                .frame(width: 30, height: 30)
                .background(.tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
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
