import AppKit
import SwiftUI
import FocusTraceCore

enum AppSection: String, CaseIterable, Identifiable {
    case timeline = "时间轴"
    case inbox = "需求箱"
    case focus = "专注训练"
    case review = "回顾分析"
    case settings = "设置与数据"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .timeline: return FocusTraceUXContract.sidebarTimelineIcon
        case .inbox: return "tray.full"
        case .focus: return "scope"
        case .review: return "chart.xyaxis.line"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @ObservedObject var state: ApplicationState

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                FocusTraceBrandLockup()
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 4) {
                    ForEach(AppSection.allCases) { section in
                        sidebarButton(section)
                    }
                }
                .padding(.horizontal, 10)

                Spacer(minLength: 12)
                captureStatus
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FocusTraceTheme.navy.opacity(0.025))
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 260)
        } detail: {
            Group {
                switch state.selectedAppSection ?? .focus {
                case .timeline:
                    TimelineView(state: state)
                case .inbox:
                    RequirementsView(state: state)
                case .focus:
                    FocusTrainingView(state: state)
                case .review:
                    ReviewView(state: state)
                case .settings:
                    SettingsView(state: state)
                }
            }
            .navigationTitle((state.selectedAppSection ?? .focus).rawValue)
        }
        .focusTraceVisualSystem()
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
        .sheet(isPresented: $state.showTaskCreator) {
            TaskEditorSheet(state: state)
        }
        .sheet(isPresented: $state.showTaskParking) {
            TaskParkingSheet(state: state)
        }
        .sheet(isPresented: $state.showQuickStart) {
            QuickStartSheet(state: state)
        }
        .sheet(isPresented: $state.showFocusToolSetup) {
            FocusToolSetupSheet(state: state)
                .interactiveDismissDisabled()
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

    private func sidebarButton(_ section: AppSection) -> some View {
        let isSelected = state.selectedAppSection == section
        return Button {
            state.selectedAppSection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isSelected ? FocusTraceTheme.mint : Color.secondary)
                    .frame(
                        width: CGFloat(FocusTraceUXContract.sidebarIconCanvasSize),
                        height: CGFloat(FocusTraceUXContract.sidebarIconCanvasSize)
                    )
                    .frame(width: 24, height: 24)
                Text(section.rawValue)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .contentShape(Rectangle())
            .background(
                isSelected ? FocusTraceTheme.mint.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var captureStatus: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle()
                    .fill(state.isRecording ? FocusTraceTheme.mint : Color.secondary)
                    .frame(width: 8, height: 8)
                    .shadow(
                        color: state.isRecording ? FocusTraceTheme.mint.opacity(0.45) : .clear,
                        radius: 4
                    )
                Text(state.isRecording ? "工作时段记录中" : "当前未记录")
                    .font(.caption.weight(.semibold))
            }
            Text(state.currentTask?.title ?? "尚未绑定工作流")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            FocusTraceTheme.mint.opacity(state.isRecording ? 0.08 : 0.035),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(FocusTraceTheme.mint.opacity(state.isRecording ? 0.16 : 0.07))
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }
}
