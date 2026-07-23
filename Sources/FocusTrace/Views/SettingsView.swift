import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: ApplicationState
    @ObservedObject private var preferences: AppPreferences
    @State private var showingDeleteDayConfirmation = false
    @State private var showingDeleteAllConfirmation = false

    init(state: ApplicationState) {
        self.state = state
        self.preferences = state.preferences
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FocusTracePageHeader(
                    eyebrow: "CONTROL",
                    title: "设置与数据",
                    detail: "记录、提醒、数据与隐私控制都在这里。",
                    systemImage: "slider.horizontal.3"
                )

                SettingsSectionCard(
                    title: "自动记录",
                    detail: "决定什么时候记录，以及是否随登录启动。",
                    systemImage: "calendar.badge.clock"
                ) {
                    VStack(alignment: .leading, spacing: 13) {
                        WeekdayPicker(preferences: preferences)
                        HStack {
                            TimePicker(title: "开始", minutes: $preferences.workStartMinutes)
                            TimePicker(title: "结束", minutes: $preferences.workEndMinutes)
                        }
                        Toggle(
                            "暂停应用切换记录",
                            isOn: Binding(
                                get: { preferences.capturePaused },
                                set: { state.setCapturePaused($0) }
                            )
                        )
                        Toggle(
                            "登录时启动",
                            isOn: Binding(
                                get: { preferences.launchAtLogin },
                                set: { state.setLaunchAtLogin($0) }
                            )
                        )
                        Text("登录项状态：\(LoginItemManager.statusDescription)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                }

                SettingsSectionCard(
                    title: "专注提醒",
                    detail: "控制屏幕护栏和非允许应用的提醒时机。",
                    systemImage: "bell.badge"
                ) {
                    VStack(alignment: .leading, spacing: 13) {
                        Toggle(
                            "屏幕边缘专注护栏",
                            isOn: $preferences.attentionCueEnabled
                        )
                        Stepper(
                            "非允许应用停留 \(preferences.reminderThresholdSeconds) 秒后提醒",
                            value: $preferences.reminderThresholdSeconds,
                            in: 5...120,
                            step: 5
                        )
                        Text("基线前三个工作日不会发送提醒。未由你确认的事件始终只算疑似分心。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("护栏每 5 分钟给予一次坚持反馈；10 分钟内稳定切换 3 次工作流才提示，主动挂起和原始 Space 事件不计入。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                }

                SettingsSectionCard(
                    title: "数据与保留",
                    detail: "所有导出、保留和删除操作都只作用于本机。",
                    systemImage: "externaldrive"
                ) {
                    VStack(alignment: .leading, spacing: 13) {
                        Picker("自动保留", selection: $preferences.retentionDays) {
                            Text("30 天").tag(30)
                            Text("90 天").tag(90)
                            Text("365 天").tag(365)
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            Button("导出 JSON") { exportJSON() }
                            Button("导出活动 CSV") { exportCSV() }
                            Spacer()
                        }
                        HStack {
                            Button("删除所选日期数据", role: .destructive) {
                                showingDeleteDayConfirmation = true
                            }
                            Button("清空所有行为数据", role: .destructive) {
                                showingDeleteAllConfirmation = true
                            }
                            Spacer()
                        }
                    }
                    .padding(4)
                }

                SettingsSectionCard(
                    title: "隐私边界",
                    detail: "清楚说明 FocusTrace 会记录什么、不会记录什么。",
                    systemImage: "lock.shield"
                ) {
                    VStack(alignment: .leading, spacing: 11) {
                        Label(
                            "仅保存应用名称、Bundle ID、时间、手动工作流标签和训练反馈",
                            systemImage: "checkmark.shield"
                        )
                        Label(
                            "不读取窗口标题、网页地址、聊天对象、键盘内容或手机数据",
                            systemImage: "xmark.shield"
                        )
                        Text("FocusTrace 是工作习惯工具，不提供 ADHD 诊断或治疗。")
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .focusTraceScreen()
        .confirmationDialog(
            "删除 \(state.selectedDate.formatted(date: .abbreviated, time: .omitted)) 的行为数据？",
            isPresented: $showingDeleteDayConfirmation
        ) {
            Button("删除当天数据", role: .destructive) { state.deleteSelectedDay() }
        }
        .confirmationDialog(
            "清空所有时间轴、训练和分析数据？工作流定义会保留。此操作不可撤销。",
            isPresented: $showingDeleteAllConfirmation
        ) {
            Button("清空所有行为数据", role: .destructive) { state.deleteAllBehaviorData() }
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "FocusTrace-\(dateStamp()).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.writeJSON(to: url)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "FocusTrace-activities-\(dateStamp()).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.writeCSV(to: url)
    }

    private func dateStamp() -> String {
        Date().formatted(.iso8601.year().month().day())
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FocusTraceTheme.accentGradient)
                    .frame(width: 38, height: 38)
                    .background(
                        FocusTraceTheme.mint.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(
            FocusTraceTheme.cardFill(colorScheme),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FocusTraceTheme.cardBorder(colorScheme), lineWidth: 1)
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.13 : 0.055),
            radius: 16,
            x: 0,
            y: 7
        )
    }
}
