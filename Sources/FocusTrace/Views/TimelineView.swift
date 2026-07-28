import AppKit
import SwiftUI
import FocusTraceCore

struct TimelineView: View {
    @ObservedObject var state: ApplicationState
    @Environment(\.colorScheme) private var colorScheme
    @State private var showRawActivities = false

    var body: some View {
        let snapshot = state.selectedTimelineSnapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                nextStepBanner
                HStack {
                    FocusTraceDateNavigator(
                        selection: $state.selectedDate,
                        latestDate: state.now
                    )
                    .equatable()
                    Button {
                        state.showQuickStart = true
                    } label: {
                        Label("使用方法", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("查看 FocusTrace 的三步使用方法")
                    Spacer()
                    Label(state.baselineProgressText, systemImage: state.baselineComplete ? "checkmark.circle" : "hourglass")
                        .foregroundStyle(.secondary)
                }

                TimelineChart(
                    snapshotID: snapshot.id,
                    taskIntervals: snapshot.taskIntervals,
                    taskNames: snapshot.taskNames,
                    buckets: snapshot.presentation.buckets,
                    eventBuckets: snapshot.presentation.eventBuckets,
                    range: snapshot.range,
                    now: snapshot.renderNow,
                    currentTaskID: state.currentTaskID,
                    colorScheme: colorScheme
                )
                .equatable()
                .frame(height: 360)

                summaryGrid(snapshot.presentation.summary)
                rawActivityList(
                    activities: snapshot.activities,
                    taskNames: snapshot.taskNames,
                    renderNow: snapshot.renderNow
                )
            }
            .focusTracePageContent()
        }
        .focusTraceScreen()
    }

    private var nextStepBanner: some View {
        let guidance = state.flowGuidance
        return HStack(spacing: 14) {
            Image(systemName: guidanceIcon)
                .font(.title2)
                .foregroundStyle(guidanceColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(guidance.title)
                    .font(.headline)
                Text(guidance.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(guidance.buttonTitle) {
                perform(guidance.action)
            }
            .buttonStyle(FocusTracePrimaryButtonStyle())
        }
        .padding(14)
        .background(guidanceColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var guidanceIcon: String {
        switch state.flowGuidance.action {
        case .resumeCapture: return "pause.circle"
        case .createWorkflow: return "plus.circle"
        case .bindWorkflow: return "rectangle.badge.plus"
        case .viewFocus: return "timer"
        case .openSchedule: return "clock.badge.exclamationmark"
        case .startFocus: return "scope"
        }
    }

    private var guidanceColor: Color {
        switch state.flowGuidance.action {
        case .resumeCapture, .createWorkflow, .bindWorkflow, .openSchedule: return .orange
        case .viewFocus, .startFocus: return FocusTraceTheme.sky
        }
    }

    private func perform(_ action: FlowNextAction) {
        switch action {
        case .resumeCapture:
            state.setCapturePaused(false)
        case .createWorkflow:
            state.showTaskCreator = true
        case .bindWorkflow:
            state.showTaskSwitcher = true
        case .viewFocus:
            state.selectedAppSection = .focus
        case .openSchedule:
            state.selectedAppSection = .settings
        case let .startFocus(minutes):
            state.requestStartFocus(minutes: minutes)
            state.selectedAppSection = .focus
        }
    }

    private func summaryGrid(_ summary: DailySummary) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
            MetricCard(title: "应用切换", value: "\(summary.appSwitchCount)", detail: "前台应用变化")
            MetricCard(
                title: "工作流切换 / 手动指定",
                value: "\(summary.workflowSwitchCount) / \(summary.taskSwitchCount)",
                detail: "绑定桌面间变化 / 菜单选择"
            )
            MetricCard(title: "疑似 / 确认分心", value: "\(summary.suspectedDistractionCount) / \(summary.confirmedDistractionCount)", detail: "可在回顾中修正")
            MetricCard(
                title: "中位连续专注",
                value: summary.medianFocusStreak.map(durationText) ?? "—",
                detail: "同工作流允许应用"
            )
        }
    }

    private func rawActivityList(
        activities: [ActivitySegmentModel],
        taskNames: [UUID: String],
        renderNow: Date
    ) -> some View {
        GroupBox {
            DisclosureGroup(isExpanded: $showRawActivities) {
                if activities.isEmpty {
                    ContentUnavailableView(
                        "当天没有记录",
                        systemImage: "timeline.selection",
                        description: Text("记录只在配置的工作时段内进行。")
                    )
                    .frame(height: 150)
                } else {
                    Table(activities) {
                        TableColumn("开始") { item in
                            Text(item.startedAt, style: .time).monospacedDigit()
                        }
                        .width(70)
                        TableColumn("时长") { item in
                            Text(durationText((item.endedAt ?? renderNow).timeIntervalSince(item.startedAt)))
                                .monospacedDigit()
                        }
                        .width(70)
                        TableColumn("应用") { item in Text(item.appName) }
                        TableColumn("工作流") { item in
                            Text(item.taskID.flatMap { taskNames[$0] } ?? "未标注")
                        }
                        TableColumn("分类") { item in ClassificationBadge(classification: item.classification) }
                    }
                    .frame(minHeight: 250)
                }
            } label: {
                HStack {
                    Label("原始应用片段（\(activities.count)）", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                    Spacer()
                    Text(showRawActivities ? "收起明细" : "需要核对时再展开")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .focusTraceDisclosureHitTarget(isExpanded: $showRawActivities)
            .padding(4)
        }
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct TimelineChart: View, Equatable {
    let snapshotID: UInt64
    let taskIntervals: [TaskIntervalModel]
    let taskNames: [UUID: String]
    let buckets: [TimelineBucket]
    let eventBuckets: [TimelineEventBucket]
    let range: DateInterval
    let now: Date
    let currentTaskID: UUID?
    let colorScheme: ColorScheme
    private let bucketMinutes = 5
    @State private var showSwitchingScale = false

    private var occupiedBuckets: [TimelineBucket] {
        buckets.filter { $0.activeSeconds > 0 }
    }

    private var averageSwitches: Double {
        guard !occupiedBuckets.isEmpty else { return 0 }
        return Double(occupiedBuckets.reduce(0) { $0 + $1.switchCount }) / Double(occupiedBuckets.count)
    }

    private var overallLevel: FragmentationLevel {
        FragmentationLevel.classify(switchCount: Int(averageSwitches.rounded()), bucketMinutes: bucketMinutes)
    }

    private var spaceSwitchCount: Int {
        buckets.reduce(0) { $0 + $1.spaceSwitchCount }
    }

    nonisolated static func == (left: TimelineChart, right: TimelineChart) -> Bool {
        left.snapshotID == right.snapshotID
            && left.currentTaskID == right.currentTaskID
            && left.colorScheme == right.colorScheme
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Button {
                    showSwitchingScale.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Text(occupiedBuckets.isEmpty ? "暂无活动" : switchingIntensityText(overallLevel))
                            .font(.headline)
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                    }
                    .foregroundStyle(occupiedBuckets.isEmpty ? Color.secondary : fragmentationColor(overallLevel))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        (occupiedBuckets.isEmpty ? Color.secondary : fragmentationColor(overallLevel)).opacity(0.12),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSwitchingScale) {
                    SwitchingScalePopover(averageSwitches: averageSwitches)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("先看工作流，再看主应用，最后找高切换区间")
                        .font(.callout.weight(.medium))
                    Text(occupiedBuckets.isEmpty
                         ? "工作时段开始后会在这里形成概览"
                         : "有记录的区间平均 \(averageSwitches, specifier: "%.1f") 次应用切换 · 桌面变化 \(spaceSwitchCount) 次（不等于分心）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack {
                Text("工作流").frame(width: 50, alignment: .leading)
                track(height: 36) { width in
                    ForEach(taskIntervals) { interval in
                        let frame = frameFor(start: interval.startedAt, end: interval.endedAt ?? now, width: width)
                        if frame.width > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(workflowColor(interval.taskID))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(
                                            VerdantTimelinePalette.segmentSeparator(colorScheme),
                                            lineWidth: 0.75
                                        )
                                }
                                .frame(width: max(1, frame.width - 1), height: 25)
                                .offset(x: frame.offset + 0.5, y: 5)
                                .help("\(taskName(interval.taskID)) · \(duration(interval.startedAt, interval.endedAt ?? now))")
                        }
                    }
                }
            }
            HStack {
                Text("主应用").frame(width: 50, alignment: .leading)
                track(height: 36) { width in
                    ForEach(applicationRuns) { run in
                        let frame = frameFor(start: run.start, end: run.end, width: width)
                        if frame.width > 0 {
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(applicationColor(run.app.bundleID))
                                .frame(width: max(1, frame.width - 1), height: 25)
                                .offset(x: frame.offset + 0.5, y: 5)
                                .help("\(timeRange(run.start, run.end)) · \(run.app.name) · 活跃 \(duration(run.activeSeconds))")
                        }
                    }
                }
            }
            HStack(alignment: .bottom) {
                Text("切换密度").frame(width: 50, alignment: .leading)
                track(height: 45) { width in
                    let maximum = max(1, buckets.map(\.switchCount).max() ?? 1)
                    ForEach(buckets) { bucket in
                        let frame = frameFor(start: bucket.start, end: bucket.end, width: width)
                        if bucket.activeSeconds > 0, frame.width > 0 {
                            let barHeight = max(4, 34 * CGFloat(bucket.switchCount) / CGFloat(maximum))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(fragmentationColor(bucket.fragmentationLevel))
                                .frame(width: max(1, frame.width - 1), height: barHeight)
                                .offset(x: frame.offset + 0.5, y: 39 - barHeight)
                                .help("\(timeRange(bucket.start, bucket.end)) · 应用切换 \(bucket.switchCount) 次 · Space \(bucket.spaceSwitchCount) 次")
                        }
                    }
                }
            }
            if !eventBuckets.isEmpty {
                HStack {
                    Text("工作节点").frame(width: 50, alignment: .leading)
                    track(height: 24) { width in
                        ForEach(eventBuckets) { bucket in
                            let frame = frameFor(start: bucket.start, end: bucket.end, width: width)
                            let kind = representativeKind(bucket.kinds)
                            ZStack {
                                Capsule()
                                    .fill(markerColor(kind).opacity(0.13))
                                if bucket.eventCount == 1 {
                                    Image(systemName: markerSymbol(kind))
                                        .font(.caption2)
                                } else {
                                    Text("\(bucket.eventCount)")
                                        .font(.caption2.bold())
                                }
                            }
                            .foregroundStyle(markerColor(kind))
                            .frame(width: max(12, frame.width - 2), height: 18)
                            .offset(x: frame.offset + 1, y: 3)
                            .help("\(timeRange(bucket.start, bucket.end)) · \(eventSummary(bucket))")
                        }
                    }
                }
            }
            HStack {
                Spacer().frame(width: 58)
                hourLabels
            }
            if !workflowLegendIDs.isEmpty {
                HStack(spacing: 10) {
                    Text("工作流")
                        .font(.caption.weight(.semibold))
                        .frame(width: 50, alignment: .leading)
                    ForEach(workflowLegendIDs, id: \.self) { id in
                        legendItem(taskName(id), workflowColor(id))
                    }
                    if workflowCount > workflowLegendIDs.count {
                        Text("+\(workflowCount - workflowLegendIDs.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            if !applicationLegend.isEmpty {
                HStack(spacing: 10) {
                    Text("主应用")
                        .font(.caption.weight(.semibold))
                        .frame(width: 50, alignment: .leading)
                    ForEach(applicationLegend, id: \.bundleID) { app in
                        legendItem(app.name, applicationColor(app.bundleID))
                    }
                    if applicationCount > applicationLegend.count {
                        Text("+\(applicationCount - applicationLegend.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            HStack(spacing: 12) {
                legend("较少 0–2", fragmentationColor(.quiet))
                legend("适中 3–5", fragmentationColor(.steady))
                legend("密集 6–10", fragmentationColor(.fragmented))
                legend("很密集 11+", fragmentationColor(.intense))
                Text("工作节点：切换理由、保存/恢复、专注状态和屏幕状态；相邻事件按 15 分钟合并")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            VerdantTimelinePalette.panelFill(colorScheme),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(VerdantTimelinePalette.panelBorder(colorScheme), lineWidth: 1)
        }
    }

    private func track<Content: View>(height: CGFloat, @ViewBuilder content: @escaping (CGFloat) -> Content) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(VerdantTimelinePalette.trackFill(colorScheme))
                ForEach(0...8, id: \.self) { index in
                    Rectangle()
                        .fill(.separator.opacity(index == 0 || index == 8 ? 0 : 0.18))
                        .frame(width: 1)
                        .offset(x: geometry.size.width * CGFloat(index) / 8)
                }
                content(geometry.size.width)
            }
        }
        .frame(height: height)
    }

    private var hourLabels: some View {
        GeometryReader { geometry in
            ForEach(0...4, id: \.self) { index in
                let fraction = Double(index) / 4
                let date = range.start.addingTimeInterval(range.duration * fraction)
                Text(date, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: geometry.size.width * fraction, y: 8)
            }
        }
        .frame(height: 18)
    }

    private func frameFor(start: Date, end: Date, width trackWidth: CGFloat) -> (offset: CGFloat, width: CGFloat) {
        let safeEnd = min(range.end, max(range.start, end))
        let safeStart = min(range.end, max(range.start, start))
        let startFraction = safeStart.timeIntervalSince(range.start) / max(1, range.duration)
        let endFraction = safeEnd.timeIntervalSince(range.start) / max(1, range.duration)
        return (
            CGFloat(startFraction) * trackWidth,
            max(0, CGFloat(endFraction - startFraction) * trackWidth)
        )
    }

    private func taskName(_ id: UUID) -> String {
        taskNames[id] ?? "已删除工作流"
    }

    private func workflowColor(_ id: UUID) -> Color {
        let rankedIDs = workflowLegendIDs.map(\.uuidString)
        guard let index = TimelineCategoryPaletteAssignment.index(
            for: id.uuidString,
            rankedIDs: rankedIDs
        ) else {
            return FocusTraceTimelinePalette.workflowOther.swiftUIColor
        }
        return FocusTraceTimelinePalette.workflows[index].swiftUIColor
    }

    private func applicationColor(_ bundleID: String) -> Color {
        let rankedIDs = applicationLegend.map(\.bundleID)
        guard let index = TimelineCategoryPaletteAssignment.index(
            for: bundleID,
            rankedIDs: rankedIDs
        ) else {
            return FocusTraceTimelinePalette.applicationOther.swiftUIColor
        }
        return FocusTraceTimelinePalette.applications[index].swiftUIColor
    }

    private var workflowLegendIDs: [UUID] {
        Array(workflowDurations.keys.sorted { left, right in
            let leftDuration = workflowDurations[left, default: 0]
            let rightDuration = workflowDurations[right, default: 0]
            if leftDuration != rightDuration { return leftDuration > rightDuration }
            return taskName(left).localizedStandardCompare(taskName(right)) == .orderedAscending
        }.prefix(TimelineCategoryPaletteAssignment.maximumColoredCategories))
    }

    private var workflowCount: Int {
        workflowDurations.count
    }

    private var workflowDurations: [UUID: TimeInterval] {
        taskIntervals.reduce(into: [:]) { result, interval in
            let start = max(range.start, interval.startedAt)
            let end = min(range.end, interval.endedAt ?? now)
            result[interval.taskID, default: 0] += max(
                0,
                end.timeIntervalSince(start)
            )
        }
    }

    private var applicationLegend: [AppIdentity] {
        Array(applicationDurations.keys.sorted { left, right in
            let leftDuration = applicationDurations[left, default: 0]
            let rightDuration = applicationDurations[right, default: 0]
            if leftDuration != rightDuration { return leftDuration > rightDuration }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }.prefix(TimelineCategoryPaletteAssignment.maximumColoredCategories))
    }

    private var applicationCount: Int {
        applicationDurations.count
    }

    private var applicationRuns: [TimelineApplicationRun] {
        TimelineApplicationRunEngine.runs(from: buckets)
    }

    private var applicationDurations: [AppIdentity: TimeInterval] {
        applicationRuns.reduce(into: [:]) { result, run in
            result[run.app, default: 0] += run.activeSeconds
        }
    }

    private func duration(_ start: Date, _ end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return seconds >= 60 ? "\(seconds / 60) 分 \(seconds % 60) 秒" : "\(seconds) 秒"
    }

    private func duration(_ seconds: TimeInterval) -> String {
        duration(Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: max(0, seconds)))
    }

    private func timeRange(_ start: Date, _ end: Date) -> String {
        "\(start.formatted(Self.timeStyle))–\(end.formatted(Self.timeStyle))"
    }

    private func switchingIntensityText(_ level: FragmentationLevel) -> String {
        switch level {
        case .quiet: return "应用切换较少"
        case .steady: return "应用切换适中"
        case .fragmented: return "应用切换密集"
        case .intense: return "应用切换非常密集"
        }
    }

    private func fragmentationColor(_ level: FragmentationLevel) -> Color {
        switch level {
        case .quiet: return FocusTraceTimelinePalette.quiet.swiftUIColor
        case .steady: return FocusTraceTimelinePalette.steady.swiftUIColor
        case .fragmented: return FocusTraceTimelinePalette.fragmented.swiftUIColor
        case .intense: return FocusTraceTimelinePalette.intense.swiftUIColor
        }
    }

    private func markerColor(_ kind: TimelineMarkerKind) -> Color {
        switch kind {
        case .reminderSent: return .orange
        case .taskParked: return .purple
        case .taskResumed: return .green
        case .focusPaused: return .orange
        case .focusResumed: return .green
        case .spaceSwitchCheckpoint: return FocusTraceTheme.mint
        case .spaceSwitchWaiting: return FocusTraceTheme.sky
        case .spaceSwitchInterrupted: return FocusTraceTheme.amber
        case .spaceSwitchUnstructured: return FocusTraceTheme.coral
        case .spaceSwitchCancelled: return .secondary
        default: return .secondary
        }
    }

    private func markerText(_ kind: TimelineMarkerKind) -> String {
        switch kind {
        case .activeSpaceChanged: return "Mac 桌面发生变化"
        case .screenSlept: return "屏幕休眠"
        case .screenWoke: return "屏幕唤醒"
        case .sessionBecameInactive: return "会话锁定"
        case .sessionBecameActive: return "会话恢复"
        case .taskChanged: return "手动工作流切换"
        case .workflowChanged: return "桌面工作流切换"
        case .reminderSent: return "发送温和提醒"
        case .taskParked: return "保存返回点"
        case .taskResumed: return "恢复工作流"
        case .focusPaused: return "跨桌面暂停专注"
        case .focusResumed: return "返回后恢复专注"
        case .spaceSwitchCheckpoint: return "阶段已到后切换"
        case .spaceSwitchWaiting: return "等待结果时切换"
        case .spaceSwitchInterrupted: return "被迫中断后切换"
        case .spaceSwitchUnstructured: return "未选择理由的切换"
        case .spaceSwitchCancelled: return "滑回并取消切换"
        }
    }

    private func representativeKind(_ kinds: [TimelineMarkerKind]) -> TimelineMarkerKind {
        let priority: [TimelineMarkerKind] = [
            .spaceSwitchInterrupted, .spaceSwitchUnstructured,
            .spaceSwitchCheckpoint, .spaceSwitchWaiting, .spaceSwitchCancelled,
            .reminderSent, .focusPaused, .focusResumed, .taskParked, .taskResumed,
            .workflowChanged, .taskChanged,
            .sessionBecameInactive, .screenSlept, .sessionBecameActive, .screenWoke
        ]
        return priority.first(where: kinds.contains) ?? kinds.first ?? .taskChanged
    }

    private func eventSummary(_ bucket: TimelineEventBucket) -> String {
        TimelineMarkerKind.allCases.compactMap { kind in
            guard kind != .activeSpaceChanged, let count = bucket.countsByKind[kind] else { return nil }
            return count > 1 ? "\(markerText(kind)) × \(count)" : markerText(kind)
        }.joined(separator: "、")
    }

    private func markerSymbol(_ kind: TimelineMarkerKind) -> String {
        switch kind {
        case .activeSpaceChanged: return "rectangle.2.swap"
        case .screenSlept: return "moon.zzz.fill"
        case .screenWoke: return "sun.max.fill"
        case .sessionBecameInactive: return "lock.fill"
        case .sessionBecameActive: return "lock.open.fill"
        case .taskChanged: return "arrow.triangle.branch"
        case .workflowChanged: return "rectangle.2.swap"
        case .reminderSent: return "bell.fill"
        case .taskParked: return "pause.circle.fill"
        case .taskResumed: return "play.circle.fill"
        case .focusPaused: return "pause.circle.fill"
        case .focusResumed: return "play.circle.fill"
        case .spaceSwitchCheckpoint: return "checkmark.circle.fill"
        case .spaceSwitchWaiting: return "hourglass.circle.fill"
        case .spaceSwitchInterrupted: return "exclamationmark.bubble.fill"
        case .spaceSwitchUnstructured: return "questionmark.circle.fill"
        case .spaceSwitchCancelled: return "arrow.uturn.backward.circle.fill"
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }

    private func legendItem(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(text)
                .font(.caption2)
                .lineLimit(1)
        }
    }

    private static let timeStyle = Date.FormatStyle.dateTime.hour().minute()
}

private enum VerdantTimelinePalette {
    static func segmentSeparator(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(nsColor: .windowBackgroundColor)
            : Color(nsColor: .textBackgroundColor)
    }

    static func trackFill(_ scheme: ColorScheme) -> Color {
        Color(nsColor: .textBackgroundColor)
    }

    static func panelFill(_ scheme: ColorScheme) -> Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static func panelBorder(_ scheme: ColorScheme) -> Color {
        Color(nsColor: .separatorColor)
    }
}

private extension FocusTraceRGBColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }
}

struct SwitchingScalePopover: View {
    let averageSwitches: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("应用层切换强度")
                .font(.headline)
            Text("这不是 ADHD 或分心判断，也没有行业统一阈值。FocusTrace 当前使用一组可解释的试运行刻度：")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 7) {
                scaleRow(color: .green, text: "0–2 次 / 5 分钟：较少")
                scaleRow(color: .blue, text: "3–5 次 / 5 分钟：适中")
                scaleRow(color: .orange, text: "6–10 次 / 5 分钟：密集")
                scaleRow(color: .red, text: "11 次以上 / 5 分钟：非常密集")
            }

            Text("顶部标签取当天所有有活动的 5 分钟区间的平均值；当前为 \(averageSwitches, specifier: "%.1f") 次。它只描述 Bundle ID 之间的变化，不代表工作流切换，也看不到 Chrome 内部标签页。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 390)
    }

    private func scaleRow(color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.callout)
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            FocusTraceTheme.elevatedFill(colorScheme),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(FocusTraceTheme.cardBorder(colorScheme), lineWidth: 1)
        }
    }
}

struct ClassificationBadge: View {
    let classification: ActivityClassification

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var text: String {
        switch classification {
        case .allowed: return "允许"
        case .necessary: return "必要"
        case .suspectedDistraction: return "疑似"
        case .confirmedDistraction: return "确认分心"
        case .taskSwitch: return "工作流切换"
        case .systemInactive: return "非活动"
        case .trackerControl: return "控制"
        }
    }

    private var color: Color {
        switch classification {
        case .allowed: return .blue
        case .necessary: return .green
        case .suspectedDistraction: return .orange
        case .confirmedDistraction: return .red
        case .taskSwitch: return .purple
        case .systemInactive, .trackerControl: return .secondary
        }
    }
}
