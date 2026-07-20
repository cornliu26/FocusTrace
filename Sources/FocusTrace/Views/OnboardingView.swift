import SwiftUI
import FocusTraceCore

struct OnboardingView: View {
    @ObservedObject var state: ApplicationState
    @ObservedObject private var preferences: AppPreferences
    @State private var taskTitle = "今天的主线工作"
    @State private var expectedOutcome = ""
    @State private var runningApps: [AppIdentity] = []
    @State private var selectedApps = Set<String>()

    init(state: ApplicationState) {
        self.state = state
        self.preferences = state.preferences
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("先告诉 FocusTrace 你在做什么", systemImage: "scope")
                    .font(.largeTitle.bold())

                Text("完成下面两项后就会开始记录。以后只要切换主任务，正常使用 Codex、终端和浏览器不需要反复操作。")
                    .foregroundStyle(.secondary)

                GroupBox("1 · 自动记录时段") {
                    VStack(alignment: .leading, spacing: 14) {
                        WeekdayPicker(preferences: preferences)
                        HStack {
                            TimePicker(title: "开始", minutes: $preferences.workStartMinutes)
                            TimePicker(title: "结束", minutes: $preferences.workEndMinutes)
                        }
                    }
                    .padding(8)
                }

                GroupBox("2 · 创建第一个主任务") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("任务名称", text: $taskTitle)
                            .textFieldStyle(.roundedBorder)
                        TextField("期望产出 / 当前上下文（可选）", text: $expectedOutcome)
                            .textFieldStyle(.roundedBorder)

                        Text("勾选这个任务确实会用到的应用")
                            .font(.headline)
                        Text("这些工具可以同时属于多个任务；应用列表不是任务归属规则。工具间切换会记录，但不会被当作偏离任务。")
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
                        .frame(height: 185)
                    }
                    .padding(8)
                }

                GroupBox {
                    Label {
                        Text("只记录前台应用、任务标签和时间；不读取窗口标题、网页地址、聊天对象或键盘内容。数据只保存在本机，也不用于 ADHD 诊断。")
                    } icon: {
                        Image(systemName: "lock.shield")
                    }
                    .foregroundStyle(.secondary)
                    .padding(5)
                }

                HStack {
                    Text(selectedApps.isEmpty ? "请先选择至少一个工作应用" : "之后：选任务 → 开始专注 → 需要时挂起")
                        .font(.caption)
                        .foregroundStyle(selectedApps.isEmpty ? .orange : .secondary)
                    Spacer()
                    Button("创建任务并开始记录") {
                        state.completeOnboardingAndCreateTask(
                            title: taskTitle,
                            expectedOutcome: expectedOutcome,
                            allowedBundleIDs: selectedApps
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(
                        preferences.workdayNumbers.isEmpty
                            || selectedApps.isEmpty
                            || taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
            .padding(26)
        }
        .frame(width: 690, height: 700)
        .onAppear {
            runningApps = state.runningApps().filter { $0.bundleID != "com.apple.loginwindow" }
        }
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
            VStack(alignment: .leading, spacing: 5) {
                Label("FocusTrace 的正确姿势", systemImage: "figure.mind.and.body")
                    .font(.title2.bold())
                Text("平时只需要记住三步，不用盯着时间轴工作。")
                    .foregroundStyle(.secondary)
            }

            guideStep(
                number: "1",
                title: "先选一个主任务",
                detail: "任务按“你想完成的产出”定义；Codex、终端、Chrome 只是可复用工具。它们之间的正常切换不等于任务切换或分心。"
            )
            guideStep(
                number: "2",
                title: "开始一轮 15 分钟专注",
                detail: "前 3 个工作日只采集基线，不发分心提醒。完成后只需记录是否完成和难度。"
            )
            guideStep(
                number: "3",
                title: "Agent 等待时先挂起",
                detail: "留下“回来后的第一步”，再切到另一个任务；结果出来后从菜单栏恢复，避免把并发全放在脑子里。"
            )

            Text("时间轴是下班后的描述性回顾：颜色显示主应用，柱高显示 5 分钟内的切换密度。高密度不自动等于走神。")
                .font(.callout)
                .padding(12)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                if state.currentTaskID == nil {
                    Button(state.activeTasks.isEmpty ? "创建第一个任务" : "选择当前任务") {
                        dismiss()
                        if state.activeTasks.isEmpty { state.showTaskCreator = true }
                        else { state.showTaskSwitcher = true }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
                Button("知道了") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 570)
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
