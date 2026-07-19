import AppKit
import SwiftUI
import FocusTraceCore

enum AppSection: String, CaseIterable, Identifiable {
    case timeline = "时间轴"
    case focus = "专注训练"
    case review = "回顾分析"
    case settings = "设置与数据"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .timeline: return "timeline.selection"
        case .focus: return "scope"
        case .review: return "chart.xyaxis.line"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @ObservedObject var state: ApplicationState
    @State private var selection: AppSection = .timeline

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("FocusTrace")
            .safeAreaInset(edge: .bottom) {
                captureStatus
            }
        } detail: {
            Group {
                switch selection {
                case .timeline:
                    TimelineView(state: state)
                case .focus:
                    FocusTrainingView(state: state)
                case .review:
                    ReviewView(state: state)
                case .settings:
                    SettingsView(state: state)
                }
            }
            .navigationTitle(selection.rawValue)
        }
        .sheet(
            isPresented: Binding(
                get: { !state.preferences.hasCompletedOnboarding },
                set: { _ in }
            )
        ) {
            OnboardingView(state: state)
                .interactiveDismissDisabled()
        }
        .sheet(item: $state.pendingSessionReview) { review in
            SessionReviewSheet(state: state, review: review)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $state.showTaskSwitcher) {
            TaskSwitcherSheet(state: state)
        }
        .alert(
            "FocusTrace",
            isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { if !$0 { state.errorMessage = nil } }
            )
        ) {
            Button("好") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            state.shutdown()
        }
    }

    private var captureStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.isRecording ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(state.isRecording ? "工作时段记录中" : "当前未记录")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(.bar)
    }
}
