import SwiftUI

struct OnboardingView: View {
    @ObservedObject var state: ApplicationState
    @ObservedObject private var preferences: AppPreferences

    init(state: ApplicationState) {
        self.state = state
        self.preferences = state.preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("欢迎使用 FocusTrace", systemImage: "scope")
                .font(.largeTitle.bold())

            Text("它只记录前台应用、任务标签和时间，不读取窗口标题、网页地址、聊天对象或键盘内容。所有数据只保存在这台 Mac。")
                .foregroundStyle(.secondary)

            GroupBox("设置自动记录时段") {
                VStack(alignment: .leading, spacing: 14) {
                    WeekdayPicker(preferences: preferences)
                    HStack {
                        TimePicker(title: "开始", minutes: $preferences.workStartMinutes)
                        TimePicker(title: "结束", minutes: $preferences.workEndMinutes)
                    }
                }
                .padding(8)
            }

            GroupBox {
                Label {
                    Text("FocusTrace 用于观察和训练工作习惯，不提供 ADHD 诊断或治疗。若注意力问题持续显著影响工作或生活，请考虑寻求专业评估。")
                } icon: {
                    Image(systemName: "heart.text.square")
                }
                .foregroundStyle(.secondary)
                .padding(6)
            }

            HStack {
                Spacer()
                Button("开始 3 个工作日的基线记录") {
                    state.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(preferences.workdayNumbers.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 650)
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
