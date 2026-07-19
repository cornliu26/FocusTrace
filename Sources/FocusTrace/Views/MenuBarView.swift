import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: ApplicationState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: state.currentFocusID == nil ? "scope" : "timer")
                    .font(.title2)
                    .foregroundStyle(state.currentFocusID == nil ? Color.secondary : Color.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.currentTask?.title ?? "未选择任务")
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
                    Text(state.focusRemainingSeconds > 0 ? "剩余 \(format(state.focusRemainingSeconds))" : "目标已完成")
                        .monospacedDigit()
                    Spacer()
                    Button("结束并记录") { state.endFocus() }
                }
            } else if state.currentTaskID != nil {
                Button("开始 \(state.currentPlan.focusMinutes) 分钟专注") {
                    state.startFocus()
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

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
    }

    private var statusText: String {
        if let focus = state.currentFocus {
            return "专注中 · 目标 \(focus.targetSeconds / 60) 分钟"
        }
        if state.preferences.capturePaused { return "记录已暂停" }
        return state.isRecording ? "应用切换记录中" : "工作时段之外"
    }

    private func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
