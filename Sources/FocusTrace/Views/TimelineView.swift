import SwiftUI
import FocusTraceCore

struct TimelineView: View {
    @ObservedObject var state: ApplicationState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    DatePicker(
                        "日期",
                        selection: $state.selectedDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.field)
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
                .frame(height: 230)

                summaryGrid
                activityList
            }
            .padding(24)
        }
    }

    private var summaryGrid: some View {
        let summary = state.selectedSummary
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
            MetricCard(title: "应用切换", value: "\(summary.appSwitchCount)", detail: "前台应用变化")
            MetricCard(title: "任务切换", value: "\(summary.taskSwitchCount)", detail: "主动标记")
            MetricCard(title: "疑似 / 确认分心", value: "\(summary.suspectedDistractionCount) / \(summary.confirmedDistractionCount)", detail: "可在回顾中修正")
            MetricCard(
                title: "中位连续专注",
                value: summary.medianFocusStreak.map(durationText) ?? "—",
                detail: "同任务允许应用"
            )
        }
    }

    private var activityList: some View {
        GroupBox("应用片段") {
            if state.selectedActivities.isEmpty {
                ContentUnavailableView(
                    "当天没有记录",
                    systemImage: "timeline.selection",
                    description: Text("记录只在配置的工作时段内进行。")
                )
                .frame(height: 160)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("任务").frame(width: 50, alignment: .leading)
                track(height: 42) { width in
                    ForEach(taskIntervals) { interval in
                        let frame = frameFor(start: interval.startedAt, end: interval.endedAt ?? now, width: width)
                        if frame.width > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(taskColor(interval.taskID).opacity(0.75))
                                .frame(width: frame.width, height: 32)
                                .offset(x: frame.offset, y: 5)
                                .help("\(taskName(interval.taskID)) · \(duration(interval.startedAt, interval.endedAt ?? now))")
                                .overlay(alignment: .leading) {
                                    if frame.width > 80 {
                                        Text(taskName(interval.taskID))
                                            .font(.caption)
                                            .lineLimit(1)
                                            .padding(.leading, 6)
                                    }
                                }
                        }
                    }
                }
            }
            HStack {
                Text("应用").frame(width: 50, alignment: .leading)
                track(height: 62) { width in
                    ForEach(segments) { segment in
                        let frame = frameFor(start: segment.startedAt, end: segment.endedAt ?? now, width: width)
                        if frame.width > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(segmentColor(segment))
                                .frame(width: frame.width, height: 42)
                                .offset(x: frame.offset, y: 7)
                                .help("\(segment.appName) · \(duration(segment.startedAt, segment.endedAt ?? now)) · \(classificationText(segment.classification))")
                        }
                    }
                    ForEach(markers) { marker in
                        let x = frameFor(start: marker.date, end: marker.date.addingTimeInterval(1), width: width).offset
                        Rectangle()
                            .fill(markerColor(marker.kind))
                            .frame(width: 2, height: 54)
                            .offset(x: x, y: 4)
                            .help(markerText(marker.kind))
                    }
                }
            }
            HStack {
                Spacer().frame(width: 58)
                hourLabels
            }
            HStack(spacing: 12) {
                legend("允许", .blue)
                legend("必要", .green)
                legend("疑似", .orange)
                legend("确认分心", .red)
                legend("系统/本工具", .gray)
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
                        .fill(.separator.opacity(index == 0 || index == 8 ? 0 : 0.35))
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

    private func segmentColor(_ item: ActivitySegmentModel) -> Color {
        switch item.classification {
        case .necessary: return .green
        case .suspectedDistraction: return .orange
        case .confirmedDistraction: return .red
        case .systemInactive, .trackerControl: return .gray
        case .taskSwitch: return .purple
        case .allowed: return stableColor(item.bundleID)
        }
    }

    private func stableColor(_ value: String) -> Color {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.58, brightness: 0.82)
    }

    private func duration(_ start: Date, _ end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return seconds >= 60 ? "\(seconds / 60) 分 \(seconds % 60) 秒" : "\(seconds) 秒"
    }

    private func classificationText(_ value: ActivityClassification) -> String {
        switch value {
        case .allowed: return "允许"
        case .necessary: return "必要"
        case .suspectedDistraction: return "疑似分心"
        case .confirmedDistraction: return "确认分心"
        case .taskSwitch: return "任务切换"
        case .systemInactive: return "系统非活动"
        case .trackerControl: return "FocusTrace 操作"
        }
    }

    private func markerColor(_ kind: TimelineMarkerKind) -> Color {
        kind == .reminderSent ? .orange : .secondary
    }

    private func markerText(_ kind: TimelineMarkerKind) -> String {
        switch kind {
        case .activeSpaceChanged: return "切换 Space"
        case .screenSlept: return "屏幕休眠"
        case .screenWoke: return "屏幕唤醒"
        case .sessionBecameInactive: return "会话锁定"
        case .sessionBecameActive: return "会话恢复"
        case .taskChanged: return "任务切换"
        case .reminderSent: return "发送温和提醒"
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
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
