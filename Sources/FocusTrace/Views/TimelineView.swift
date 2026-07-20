import SwiftUI
import FocusTraceCore

struct TimelineView: View {
    @ObservedObject var state: ApplicationState
    @State private var showRawActivities = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if state.currentTaskID == nil {
                    taskContextBanner
                }
                HStack {
                    DatePicker(
                        "日期",
                        selection: $state.selectedDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.field)
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
                    segments: state.selectedActivities,
                    taskIntervals: state.selectedTaskIntervals,
                    markers: state.selectedMarkers,
                    tasks: state.tasks,
                    range: state.preferences.workRange(for: state.selectedDate),
                    now: state.now
                )
                .frame(height: 310)

                summaryGrid
                rawActivityList
            }
            .padding(24)
        }
    }

    private var taskContextBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "tag.slash")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.activeTasks.isEmpty ? "当前只能记录应用切换" : "当前没有主任务")
                    .font(.headline)
                Text(state.activeTasks.isEmpty
                     ? "创建至少一个任务，否则无法累积基线、识别分心或训练恢复能力。"
                     : "请选择你正在做的任务；未标注时的切换只能用于描述性统计。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button("使用方法") {
                    state.showQuickStart = true
                }
                .buttonStyle(.bordered)
                Button(state.activeTasks.isEmpty ? "创建第一个任务" : "选择当前任务") {
                    if state.activeTasks.isEmpty {
                        state.showTaskCreator = true
                    } else {
                        state.showTaskSwitcher = true
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var summaryGrid: some View {
        let summary = state.selectedSummary
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
            MetricCard(title: "应用切换", value: "\(summary.appSwitchCount)", detail: "前台应用变化")
            MetricCard(
                title: "工作流 / 手动切换",
                value: "\(summary.workflowSwitchCount) / \(summary.taskSwitchCount)",
                detail: "桌面识别 / 主动标记"
            )
            MetricCard(title: "疑似 / 确认分心", value: "\(summary.suspectedDistractionCount) / \(summary.confirmedDistractionCount)", detail: "可在回顾中修正")
            MetricCard(
                title: "中位连续专注",
                value: summary.medianFocusStreak.map(durationText) ?? "—",
                detail: "同任务允许应用"
            )
        }
    }

    private var rawActivityList: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $showRawActivities) {
                if state.selectedActivities.isEmpty {
                    ContentUnavailableView(
                        "当天没有记录",
                        systemImage: "timeline.selection",
                        description: Text("记录只在配置的工作时段内进行。")
                    )
                    .frame(height: 150)
                } else {
                    Table(state.selectedActivities) {
                        TableColumn("开始") { item in
                            Text(item.startedAt, style: .time).monospacedDigit()
                        }
                        .width(70)
                        TableColumn("时长") { item in
                            Text(durationText((item.endedAt ?? state.now).timeIntervalSince(item.startedAt)))
                                .monospacedDigit()
                        }
                        .width(70)
                        TableColumn("应用") { item in Text(item.appName) }
                        TableColumn("任务") { item in Text(state.taskName(for: item.taskID)) }
                        TableColumn("分类") { item in ClassificationBadge(classification: item.classification) }
                    }
                    .frame(minHeight: 250)
                }
            } label: {
                HStack {
                    Label("原始应用片段（\(state.selectedActivities.count)）", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                    Spacer()
                    Text(showRawActivities ? "收起明细" : "需要核对时再展开")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct TimelineChart: View {
    let segments: [ActivitySegmentModel]
    let taskIntervals: [TaskIntervalModel]
    let markers: [TimelineMarkerModel]
    let tasks: [FocusTaskModel]
    let range: DateInterval
    let now: Date
    private let bucketMinutes = 5
    @State private var showSwitchingScale = false

    private var buckets: [TimelineBucket] {
        TimelineAggregationEngine.buckets(
            activities: segments.map(\.record),
            markers: markers.map(\.record),
            range: range,
            bucketMinutes: bucketMinutes,
            now: now
        )
    }

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

    private var eventBuckets: [TimelineEventBucket] {
        TimelineEventAggregationEngine.buckets(
            markers: markers.map(\.record),
            range: range,
            bucketMinutes: 15
        )
    }

    private var spaceSwitchCount: Int {
        buckets.reduce(0) { $0 + $1.spaceSwitchCount }
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
                    Text("按 5 分钟聚合：颜色显示主应用，柱高显示切换密度")
                        .font(.callout.weight(.medium))
                    Text(occupiedBuckets.isEmpty
                         ? "工作时段开始后会在这里形成概览"
                         : "有记录的区间平均 \(averageSwitches, specifier: "%.1f") 次应用切换 · Space 切换 \(spaceSwitchCount) 次")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("描述行为，不自动等于分心")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Text("任务").frame(width: 50, alignment: .leading)
                track(height: 36) { width in
                    ForEach(taskIntervals) { interval in
                        let frame = frameFor(start: interval.startedAt, end: interval.endedAt ?? now, width: width)
                        if frame.width > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(taskColor(interval.taskID).opacity(0.75))
                                .frame(width: frame.width, height: 25)
                                .offset(x: frame.offset, y: 5)
                                .help("\(taskName(interval.taskID)) · \(duration(interval.startedAt, interval.endedAt ?? now))")
                        }
                    }
                }
            }
            HStack {
                Text("主应用").frame(width: 50, alignment: .leading)
                track(height: 36) { width in
                    ForEach(buckets) { bucket in
                        let frame = frameFor(start: bucket.start, end: bucket.end, width: width)
                        if let app = bucket.dominantApp, frame.width > 0 {
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(stableColor(app.bundleID).opacity(0.88))
                                .frame(width: max(1, frame.width - 1), height: 25)
                                .offset(x: frame.offset + 0.5, y: 5)
                                .help("\(timeRange(bucket.start, bucket.end)) · \(app.name) · 活跃 \(duration(bucket.activeSeconds)) · \(bucket.uniqueAppCount) 个应用")
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
                                .fill(fragmentationColor(bucket.fragmentationLevel).opacity(0.85))
                                .frame(width: max(1, frame.width - 1), height: barHeight)
                                .offset(x: frame.offset + 0.5, y: 39 - barHeight)
                                .help("\(timeRange(bucket.start, bucket.end)) · 应用切换 \(bucket.switchCount) 次 · Space \(bucket.spaceSwitchCount) 次")
                        }
                    }
                }
            }
            if !eventBuckets.isEmpty {
                HStack {
                    Text("关键事件").frame(width: 50, alignment: .leading)
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
            HStack(spacing: 12) {
                legend("较少 0–2", .green)
                legend("适中 3–5", .blue)
                legend("密集 6–10", .orange)
                legend("很密集 11+", .red)
                Text("关键事件按 15 分钟合并")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func track<Content: View>(height: CGFloat, @ViewBuilder content: @escaping (CGFloat) -> Content) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5).fill(.background)
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
        tasks.first(where: { $0.id == id })?.title ?? "已删除任务"
    }

    private func taskColor(_ id: UUID) -> Color { stableColor(id.uuidString) }

    private func stableColor(_ value: String) -> Color {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.48, brightness: 0.86)
    }

    private func duration(_ start: Date, _ end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return seconds >= 60 ? "\(seconds / 60) 分 \(seconds % 60) 秒" : "\(seconds) 秒"
    }

    private func duration(_ seconds: TimeInterval) -> String {
        duration(Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: max(0, seconds)))
    }

    private func timeRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
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
        case .quiet: return .green
        case .steady: return .blue
        case .fragmented: return .orange
        case .intense: return .red
        }
    }

    private func markerColor(_ kind: TimelineMarkerKind) -> Color {
        switch kind {
        case .reminderSent: return .orange
        case .taskParked: return .purple
        case .taskResumed: return .green
        case .focusPaused: return .orange
        case .focusResumed: return .green
        default: return .secondary
        }
    }

    private func markerText(_ kind: TimelineMarkerKind) -> String {
        switch kind {
        case .activeSpaceChanged: return "切换 Space"
        case .screenSlept: return "屏幕休眠"
        case .screenWoke: return "屏幕唤醒"
        case .sessionBecameInactive: return "会话锁定"
        case .sessionBecameActive: return "会话恢复"
        case .taskChanged: return "任务切换"
        case .workflowChanged: return "桌面工作流切换"
        case .reminderSent: return "发送温和提醒"
        case .taskParked: return "挂起任务"
        case .taskResumed: return "恢复任务"
        case .focusPaused: return "跨桌面暂停专注"
        case .focusResumed: return "返回后恢复专注"
        }
    }

    private func representativeKind(_ kinds: [TimelineMarkerKind]) -> TimelineMarkerKind {
        let priority: [TimelineMarkerKind] = [
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
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
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

            Text("顶部标签取当天所有有活动的 5 分钟区间的平均值；当前为 \(averageSwitches, specifier: "%.1f") 次。它只描述 Bundle ID 之间的变化，不代表任务切换，也看不到 Chrome 内部标签页。")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(detail).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
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
        case .taskSwitch: return "任务切换"
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
