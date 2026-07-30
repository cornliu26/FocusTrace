import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: ApplicationState
    @ObservedObject private var preferences: AppPreferences
    @EnvironmentObject private var updateManager: UpdateManager
    @State private var showingDeletionScopeConfirmation = false

    init(state: ApplicationState) {
        self.state = state
        self.preferences = state.preferences
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSectionCard(
                    title: "自动记录",
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
                    systemImage: "bell.badge"
                ) {
                    VStack(alignment: .leading, spacing: 13) {
                        Toggle(
                            "高频工作流切换确认",
                            isOn: $preferences.attentionCueEnabled
                        )
                        Stepper(
                            "非允许应用停留 \(preferences.reminderThresholdSeconds) 秒后提醒",
                            value: $preferences.reminderThresholdSeconds,
                            in: 5...120,
                            step: 5
                        )
                        Text("基线前三个工作日不会发送提醒。连续专注时不弹奖励或完成通知。未由你确认的事件始终只算疑似分心。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("只在 10 分钟内第 3 次已绑定工作流切换时居中询问，之后冷却 10 分钟。连续找桌面会在最后一次变化稳定 1.2 秒后只记录最终工作流；10 秒未选择会自动放行。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                }

                SettingsSectionCard(
                    title: "数据与保留",
                    systemImage: "externaldrive"
                ) {
                    VStack(spacing: 0) {
                        SettingsControlRow(
                            title: "自动保留行为数据",
                            detail: "到期数据会在本机自动清理"
                        ) {
                            Menu("\(preferences.retentionDays) 天") {
                                ForEach([30, 90, 365], id: \.self) { days in
                                    Button {
                                        preferences.retentionDays = days
                                    } label: {
                                        if preferences.retentionDays == days {
                                            Label("\(days) 天", systemImage: "checkmark")
                                        } else {
                                            Text("\(days) 天")
                                        }
                                    }
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }

                        Divider()
                            .padding(.vertical, 12)

                        SettingsControlRow(
                            title: "导出副本",
                            detail: "生成本地文件，不会上传数据"
                        ) {
                            Group {
                                Button {
                                    exportJSON()
                                } label: {
                                    Label("JSON", systemImage: "doc.text")
                                }
                                Button {
                                    exportCSV()
                                } label: {
                                    Label("活动 CSV", systemImage: "tablecells")
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        Divider()
                            .padding(.vertical, 12)

                        SettingsControlRow(
                            title: "删除数据",
                            detail: "可删除某一天或清空全部"
                        ) {
                            Button(role: .destructive) {
                                showingDeletionScopeConfirmation = true
                            } label: {
                                Label("删除数据…", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .tint(FocusTraceTheme.coral)
                        }
                    }
                    .padding(4)
                }

                SettingsSectionCard(
                    title: "软件更新",
                    systemImage: "arrow.triangle.2.circlepath"
                ) {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Text("当前版本")
                            Spacer()
                            Text(updateManager.currentVersionText)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Toggle(
                            "每天自动检查一次更新",
                            isOn: $preferences.automaticUpdateChecks
                        )
                        HStack {
                            if let release = updateManager.availableRelease {
                                Button("安装 \(release.version) 并重启") {
                                    Task { await updateManager.installAvailableUpdate() }
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button("立即检查") {
                                    Task { await updateManager.checkForUpdates() }
                                }
                            }
                            Spacer()
                            if updateManager.isBusy {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        if !updateManager.detail.isEmpty {
                            Text(updateManager.detail)
                                .font(.caption)
                                .foregroundStyle(
                                    updateManager.state == .failed
                                        ? Color.red
                                        : Color.secondary
                                )
                                .textSelection(.enabled)
                        }
                        if updateManager.state == .failed {
                            HStack(spacing: 10) {
                                Link(
                                    "手动下载最新版",
                                    destination: updateManager.manualDownloadURL
                                )
                                .buttonStyle(.bordered)
                                if let feedbackURL = updateManager.feedbackURL {
                                    Button("报告更新问题") {
                                        NSWorkspace.shared.open(feedbackURL)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            Text("反馈只会预填版本、macOS、失败阶段和错误代码；不会上传行为记录、工作流名称或应用使用数据。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("更新从公开 GitHub Release 下载，并在替换前校验文件哈希、版本和代码签名。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                }

                SettingsSectionCard(
                    title: "隐私边界",
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
            .focusTracePageContent()
        }
        .focusTraceScreen()
        .confirmationDialog(
            "要删除哪些行为数据？",
            isPresented: $showingDeletionScopeConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "只删除 \(state.selectedDate.formatted(date: .abbreviated, time: .omitted))",
                role: .destructive
            ) {
                state.deleteSelectedDay()
            }
            Button("清空所有行为数据", role: .destructive) { state.deleteAllBehaviorData() }
        } message: {
            Text("将删除对应的时间轴、训练和分析记录；工作流定义会保留。此操作不可撤销。")
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

private struct SettingsControlRow<Controls: View>: View {
    let title: String
    let detail: String
    private let controls: Controls

    init(
        title: String,
        detail: String,
        @ViewBuilder controls: () -> Controls
    ) {
        self.title = title
        self.detail = detail
        self.controls = controls()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            HStack(spacing: 8) {
                controls
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minHeight: 42)
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

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
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
            }

            Divider()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .focusTraceSurfaceCard()
    }
}
