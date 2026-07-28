import Foundation
import FocusTraceCore
import FocusTraceMacSupport

private struct VerificationFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private struct VerificationSuite {
    private(set) var passed = 0
    private(set) var failures: [String] = []

    mutating func run(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            passed += 1
            print("PASS  \(name)")
        } catch {
            failures.append("\(name)：\(error)")
            print("FAIL  \(name)：\(error)")
        }
    }
}

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else { throw VerificationFailure(message: message) }
}

private func repositoryFileContents(_ path: String) throws -> String {
    try String(
        contentsOf: URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent(path),
        encoding: .utf8
    )
}

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private func phaseTwoFixture() -> (
    snapshot: FocusTraceLocalSnapshot,
    calendar: Calendar,
    lastDay: Date
) {
    let calendar = utcCalendar()
    let start = calendar.date(from: DateComponents(
        timeZone: calendar.timeZone,
        year: 2026,
        month: 6,
        day: 1,
        hour: 9
    ))!
    let taskID = UUID()
    let codex = AppIdentity(bundleID: "com.openai.codex", name: "Codex")
    let wechat = AppIdentity(bundleID: "com.tencent.xinWeChat", name: "微信")
    let browser = AppIdentity(bundleID: "com.apple.Safari", name: "Safari")
    var activities: [ActivityRecord] = []
    var sessions: [FocusSessionRecord] = []
    var interruptions: [InterruptionRecord] = []

    for day in 0..<10 {
        let morning = calendar.date(byAdding: .day, value: day, to: start)!
        let afternoon = calendar.date(byAdding: .hour, value: 5, to: morning)!
        let morningSessionID = UUID()
        let afternoonSessionID = UUID()

        let codexActivity = ActivityRecord(
            app: codex,
            startedAt: morning,
            endedAt: morning.addingTimeInterval(5 * 60),
            taskID: taskID,
            focusSessionID: morningSessionID,
            classification: .allowed
        )
        let wechatActivity = ActivityRecord(
            app: wechat,
            startedAt: morning.addingTimeInterval(5 * 60),
            endedAt: morning.addingTimeInterval(6 * 60),
            taskID: taskID,
            focusSessionID: morningSessionID,
            classification: day < 3 ? .confirmedDistraction : .suspectedDistraction
        )
        activities.append(contentsOf: [codexActivity, wechatActivity])

        sessions.append(FocusSessionRecord(
            id: morningSessionID,
            taskID: taskID,
            startedAt: morning,
            endedAt: morning.addingTimeInterval(15 * 60),
            targetSeconds: 15 * 60,
            outcome: .completed,
            difficulty: day < 3 ? 4 : 2,
            confirmedDistractionCount: day < 3 ? 1 : 0
        ))
        sessions.append(FocusSessionRecord(
            id: afternoonSessionID,
            taskID: taskID,
            startedAt: afternoon,
            endedAt: afternoon.addingTimeInterval(15 * 60),
            targetSeconds: 15 * 60,
            outcome: .completed,
            difficulty: 2,
            confirmedDistractionCount: 0
        ))

        if day < 3 {
            interruptions.append(InterruptionRecord(
                activityID: wechatActivity.id,
                focusSessionID: morningSessionID,
                taskID: taskID,
                app: wechat,
                detectedAt: morning.addingTimeInterval(5 * 60),
                resolvedAt: morning.addingTimeInterval(5 * 60 + 30),
                resolution: .returnedToTask
            ))
        }
        if day < 4 {
            interruptions.append(InterruptionRecord(
                activityID: codexActivity.id,
                focusSessionID: afternoonSessionID,
                taskID: taskID,
                app: browser,
                detectedAt: afternoon.addingTimeInterval(2 * 60),
                resolvedAt: afternoon.addingTimeInterval(2 * 60 + 5),
                resolution: .markedNecessary
            ))
        }
    }

    let plan = TrainingPlanRecord(
        version: 1,
        effectiveAt: start,
        focusMinutes: 15,
        reason: "测试计划"
    )
    let lastDay = calendar.date(byAdding: .day, value: 9, to: start)!
    let taskParkings = [
        TaskParkingRecord(
            taskID: taskID,
            parkedAt: lastDay.addingTimeInterval(60),
            resumeCue: "PRIVATE_RESUME_CUE",
            remindAt: lastDay.addingTimeInterval(10 * 60),
            switchedToTaskID: UUID(),
            resumedAt: lastDay.addingTimeInterval(21 * 60)
        ),
        TaskParkingRecord(
            taskID: taskID,
            parkedAt: lastDay.addingTimeInterval(30 * 60),
            resumeCue: "ANOTHER_PRIVATE_CUE"
        )
    ]
    return (
        FocusTraceLocalSnapshot(
            activities: activities,
            focusSessions: sessions,
            interruptions: interruptions,
            trainingPlans: [plan],
            taskParkings: taskParkings
        ),
        calendar,
        lastDay
    )
}

private var suite = VerificationSuite()

suite.run("流程引导始终只给出当前下一步") {
    let create = FlowGuidanceEngine.guidance(
        hasOpenWorkflows: false,
        currentWorkflowTitle: nil,
        capturePaused: false,
        isWithinSchedule: true,
        focusRemainingSeconds: nil,
        planMinutes: 15
    )
    try expect(create.action == .createWorkflow, "无工作流时应先引导创建")

    let bind = FlowGuidanceEngine.guidance(
        hasOpenWorkflows: true,
        currentWorkflowTitle: nil,
        capturePaused: false,
        isWithinSchedule: true,
        focusRemainingSeconds: nil,
        planMinutes: 15
    )
    try expect(bind.action == .bindWorkflow, "有工作流但桌面未绑定时应先引导绑定")

    let start = FlowGuidanceEngine.guidance(
        hasOpenWorkflows: true,
        currentWorkflowTitle: "排查登录问题",
        capturePaused: false,
        isWithinSchedule: true,
        focusRemainingSeconds: nil,
        planMinutes: 20
    )
    try expect(start.action == .startFocus(minutes: 20), "记录就绪后应只显示开始专注")

    let active = FlowGuidanceEngine.guidance(
        hasOpenWorkflows: true,
        currentWorkflowTitle: "排查登录问题",
        capturePaused: false,
        isWithinSchedule: true,
        focusRemainingSeconds: 125,
        planMinutes: 20
    )
    try expect(active.action == .viewFocus, "专注中应只引导查看当前轮次")
    try expect(active.detail.contains("02:05"), "专注引导应显示剩余时间")

    let paused = FlowGuidanceEngine.guidance(
        hasOpenWorkflows: true,
        currentWorkflowTitle: "排查登录问题",
        capturePaused: true,
        isWithinSchedule: true,
        focusRemainingSeconds: nil,
        planMinutes: 20
    )
    try expect(paused.action == .resumeCapture, "记录暂停时应只引导恢复")

    let outsideSchedule = FlowGuidanceEngine.guidance(
        hasOpenWorkflows: true,
        currentWorkflowTitle: "排查登录问题",
        capturePaused: false,
        isWithinSchedule: false,
        focusRemainingSeconds: nil,
        planMinutes: 20
    )
    try expect(outsideSchedule.action == .openSchedule, "工作时段外应只引导调整记录时段")
}

suite.run("工作流确认位于中上方且不复用被动专注浮层") {
    let visibleFrame = CGRect(x: 0, y: 25, width: 1_440, height: 875)
    let decision = FocusTraceConfirmationLayout.frame(
        in: visibleFrame,
        size: CGSize(
            width: FocusTraceConfirmationLayout.panelWidth,
            height: FocusTraceConfirmationLayout.panelHeight
        )
    )
    try expect(
        decision.midX == visibleFrame.midX
            && decision.maxY
                == visibleFrame.maxY - FocusTraceConfirmationLayout.topInset
            && decision.midY > visibleFrame.midY,
        "需要明确决策的工作流确认必须水平居中位于屏幕中上方"
    )
}

suite.run("已优化的日常交互契约保持稳定") {
    try expect(
        FocusTraceUXContract.dateSelectionPresentation == .graphicalCalendarPopover,
        "日期选择必须保持图形化日历弹层，不能退化为日期列表"
    )
    try expect(
        FocusTraceUXContract.requirementDateSelectionPresentation
            == .graphicalCalendarPopover,
        "需求截止日期必须保持紧凑图形日历弹层，不能退化为内嵌日历或日期列表"
    )
    try expect(
        !FocusTraceUXContract.calendarPopoverAnimationsEnabled
            && FocusTraceUXContract.calendarRefreshGranularity == .day
            && FocusTraceUXContract.calendarPrewarmMonthOffsets == [-1, 0, 1],
        "日历必须关闭展开动画、按天隔离刷新并预热相邻月份"
    )
    try expect(
        FocusTraceUXContract.menuBarWidth == 304,
        "状态栏面板应保持紧凑宽度"
    )
    try expect(
        FocusTraceUXContract.onboardingRequiredInputs == ["workflowName"],
        "首次使用只能要求一个工作流名称"
    )
    try expect(
        FocusTraceUXContract.primaryDailyActionCount == 1,
        "每日主路径只能暴露一个主要下一步"
    )
    try expect(
        FocusTraceUXContract.sidebarIconCanvasSize == 18
            && FocusTraceUXContract.sidebarTimelineIcon == "clock.arrow.circlepath",
        "侧栏图标尺寸和时间轴图标必须保持统一"
    )
    try expect(
        FocusTraceUXContract.timelinePaletteName == "radix-cool-v4",
        "时间轴必须保持经过决策的语义色板"
    )
    try expect(
        !FocusTraceUXContract.timelineCurrentWorkflowOutlineEnabled,
        "当前工作流不能给每个碎片添加深色描边"
    )
}

suite.run("展开箭头扩大命中范围但不改变视觉布局") {
    try expect(
        FocusTraceDisclosureInteraction.hitTargetSize == 36,
        "展开箭头应使用 36pt 的不可见点击热区"
    )
    let opened = FocusTraceDisclosureInteraction.stateAfterHeaderPress(
        isExpanded: false
    )
    let closed = FocusTraceDisclosureInteraction.stateAfterHeaderPress(
        isExpanded: opened
    )
    try expect(opened && !closed, "展开标题一次点击只能切换一次状态")

    let root = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
    func contents(_ path: String) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }
    let theme = try contents(
        "Sources/FocusTrace/Views/FocusTraceTheme.swift"
    )
    try expect(
        theme.contains("content.overlay(alignment: .topLeading)")
            && !theme.contains("FocusTraceWideDisclosureGroupStyle"),
        "点击热区必须作为不可见 overlay 存在，不能替换系统 DisclosureGroup 布局"
    )

    let disclosureSources = try [
        "Sources/FocusTrace/Views/TimelineView.swift",
        "Sources/FocusTrace/Views/RequirementsView.swift",
        "Sources/FocusTrace/Views/FocusTrainingView.swift",
        "Sources/FocusTrace/Views/ReviewView.swift",
        "Sources/FocusTrace/Views/OnboardingView.swift",
        "Sources/FocusTrace/Views/TaskEditor.swift"
    ].map(contents).joined(separator: "\n")
    let disclosureCount = disclosureSources.components(
        separatedBy: "DisclosureGroup"
    ).count - 1
    let expandedHitTargetCount = disclosureSources.components(
        separatedBy: ".focusTraceDisclosureHitTarget("
    ).count - 1
    try expect(
        disclosureCount == expandedHitTargetCount,
        "每个展开控件都必须单独增加箭头热区，不能通过全局宽行样式实现"
    )
}

suite.run("需求日期弹层允许未来日期且尊重下界") {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let earliest = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 27)
    )!
    let previousDay = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 26)
    )!
    let futureDay = calendar.date(
        from: DateComponents(year: 2026, month: 8, day: 15)
    )!

    try expect(
        !FocusTraceCalendarBounds.isSelectable(
            previousDay,
            minimumDate: earliest,
            calendar: calendar
        ),
        "需求日历不能选择早于可用下界的日期"
    )
    try expect(
        FocusTraceCalendarBounds.isSelectable(
            earliest,
            minimumDate: earliest,
            calendar: calendar
        ) && FocusTraceCalendarBounds.isSelectable(
            futureDay,
            minimumDate: earliest,
            calendar: calendar
        ),
        "需求日历必须允许下界当天和未来日期"
    )

    let currentMonth = FocusTraceCalendarLayoutEngine.startOfMonth(
        containing: earliest,
        calendar: calendar
    )
    try expect(
        FocusTraceCalendarBounds.movedMonth(
            from: currentMonth,
            by: -1,
            minimumDate: earliest,
            calendar: calendar
        ) == currentMonth,
        "需求日历不能越过最早可选月份"
    )
    try expect(
        FocusTraceCalendarBounds.movedMonth(
            from: currentMonth,
            by: 1,
            minimumDate: earliest,
            calendar: calendar
        ) == FocusTraceCalendarLayoutEngine.startOfMonth(
            containing: futureDay,
            calendar: calendar
        ),
        "需求日历必须能进入未来月份"
    )
}

suite.run("当前工作流碎片不使用黑色描边") {
    try expect(
        !FocusTraceUXContract.timelineCurrentWorkflowOutlineEnabled,
        "当前工作流已在页面其他位置说明，时间轴只能使用统一分隔线"
    )
}

suite.run("时间轴用不同语义编码上下文、工具和高切换风险") {
    try expect(
        FocusTraceTimelinePalette.workflows.map(\.hexadecimalRGB)
            == [0x29A383, 0x00A2C7, 0x0090FF, 0x3E63DD, 0x5B5BD6],
        "工作流必须使用 Radix Jade/Cyan/Blue/Indigo/Iris 9 原值"
    )
    try expect(
        FocusTraceTimelinePalette.applications.map(\.hexadecimalRGB)
            == [0x56BA9F, 0x3DB9CF, 0x5EB1EF, 0x8DA4EF, 0x9B9EF0],
        "主应用必须使用对应的 Radix 8 阶原值"
    )
    try expect(
        FocusTraceTimelinePalette.densityScale.map(\.hexadecimalRGB)
            == [0x29A383, 0x00A2C7, 0xFFC53D, 0xE54D2E],
        "切换密度必须使用 Radix Jade/Cyan/Amber/Tomato 9 原值"
    )
    try expect(
        FocusTraceTimelinePalette.workflowOther.hexadecimalRGB == 0x8B8D98
            && FocusTraceTimelinePalette.applicationOther.hexadecimalRGB == 0xB9BBC6,
        "超过五类必须统一使用 Radix Slate"
    )
}

suite.run("时间轴分类色按当天排名且最多使用五种") {
    let ranked = [
        "workflow-a", "workflow-b", "workflow-c",
        "workflow-d", "workflow-e", "workflow-f"
    ]
    try expect(
        TimelineCategoryPaletteAssignment.maximumColoredCategories == 5
            && TimelineCategoryPaletteAssignment.index(
                for: "workflow-a",
                rankedIDs: ranked
            ) == 0
            && TimelineCategoryPaletteAssignment.index(
                for: "workflow-e",
                rankedIDs: ranked
            ) == 4
            && TimelineCategoryPaletteAssignment.index(
                for: "workflow-f",
                rankedIDs: ranked
            ) == nil,
        "只能按顺序给前五类着色，其余必须回退到中性 Slate"
    )
}

suite.run("主应用连续区间合并后不再形成五分钟彩色马赛克") {
    let start = Date(timeIntervalSince1970: 1_750_000_000)
    let codex = AppIdentity(bundleID: "com.openai.codex", name: "Codex")
    let lark = AppIdentity(bundleID: "com.larksuite.suite", name: "飞书")
    func bucket(
        _ offsetMinutes: Int,
        _ app: AppIdentity?,
        _ activeSeconds: TimeInterval
    ) -> TimelineBucket {
        let bucketStart = start.addingTimeInterval(
            TimeInterval(offsetMinutes * 60)
        )
        return TimelineBucket(
            start: bucketStart,
            end: bucketStart.addingTimeInterval(5 * 60),
            dominantApp: app,
            activeSeconds: activeSeconds,
            switchCount: 0,
            spaceSwitchCount: 0,
            uniqueAppCount: app == nil ? 0 : 1,
            fragmentationLevel: .quiet
        )
    }

    let runs = TimelineApplicationRunEngine.runs(from: [
        bucket(0, codex, 280),
        bucket(5, codex, 260),
        bucket(10, nil, 0),
        bucket(15, codex, 240),
        bucket(20, lark, 220)
    ])
    try expect(
        runs.count == 3
            && runs[0].app == codex
            && runs[0].bucketCount == 2
            && runs[0].activeSeconds == 540
            && runs[1].app == codex
            && runs[2].app == lark,
        "相邻同应用应合并，空档和应用变化必须断开"
    )
}

suite.run("所有入口只复用一个 FocusTrace 主窗口") {
    try expect(
        FocusTraceWindowContract.mainWindowID == "main"
            && !FocusTraceWindowContract.allowsMultipleMainWindows
            && !FocusTraceWindowContract.exposesDedicatedSettingsWindow,
        "主窗口必须是单实例且不能另开冗余设置窗口"
    )
}

suite.run("日历月份在点击前预生成且计算耗时稳定") {
    let calendar = utcCalendar()
    let selected = calendar.date(from: DateComponents(
        timeZone: calendar.timeZone,
        year: 2026,
        month: 7,
        day: 24,
        hour: 18
    ))!
    let locale = Locale(identifier: "zh_CN")
    let measuredAt = Date()
    let layouts = FocusTracePerformanceBudget.calendarMonthOffsets.compactMap {
        offset -> FocusTraceCalendarMonthLayout? in
        guard let month = calendar.date(
            byAdding: .month,
            value: offset,
            to: selected
        ) else {
            return nil
        }
        return FocusTraceCalendarLayoutEngine.layout(
            containing: month,
            calendar: calendar,
            locale: locale
        )
    }
    let elapsed = Date().timeIntervalSince(measuredAt)
    let selectedLayout = FocusTraceCalendarLayoutEngine.layout(
        containing: selected,
        calendar: calendar,
        locale: locale
    )
    try expect(
        layouts.count == FocusTracePerformanceBudget.calendarMonthOffsets.count,
        "月份布局批量生成不应遗漏"
    )
    try expect(
        elapsed < FocusTracePerformanceBudget.calendarLayoutMaximumSeconds,
        "月份布局不能超过性能预算"
    )
    try expect(selectedLayout.weekdaySymbols.count == 7, "星期栏必须保持七列")
    try expect(
        selectedLayout.cells.count.isMultiple(of: 7),
        "日期单元格必须按整周排布"
    )
    try expect(
        selectedLayout.cells.compactMap(\.date).count == 31,
        "2026 年 7 月必须包含 31 个有效日期"
    )
    let capped = FocusTraceCalendarLayoutEngine.movedMonth(
        from: selected,
        by: 1,
        latestDate: selected,
        calendar: calendar
    )
    try expect(
        capped == FocusTraceCalendarLayoutEngine.startOfMonth(
            containing: selected,
            calendar: calendar
        ),
        "日历月份不能进入未来"
    )
}

suite.run("日历锚点连续点击只执行一次开关") {
    let opened = FocusTraceCalendarPopoverState.next(
        isPresented: false,
        event: .anchorPressed
    )
    let closed = FocusTraceCalendarPopoverState.next(
        isPresented: opened,
        event: .anchorPressed
    )
    let remainsClosed = FocusTraceCalendarPopoverState.next(
        isPresented: closed,
        event: .dismissRequested
    )
    try expect(opened, "第一次点击必须打开日历")
    try expect(!closed, "第二次点击必须关闭日历，不能再次弹出")
    try expect(!remainsClosed, "关闭请求不能反向打开日历")
}

suite.run("需求先进入收件箱且安排时不自动开始") {
    guard let captured = RequirementEngine.captured(
        title: "  张三口头说：补上失败告警  ",
        source: "  周会  "
    ) else {
        throw VerificationFailure(message: "有效需求应能被收下")
    }
    try expect(captured.title == "张三口头说：补上失败告警", "需求文本应清理空白")
    try expect(captured.source == "周会", "来源应清理空白")
    try expect(captured.status == .inbox, "新需求必须先进入待整理")
    try expect(captured.priority == .unplanned, "新需求不能擅自决定优先级")
    try expect(captured.workflowID == nil, "新需求不能自动绑定工作流")

    let workflowID = UUID()
    let attached = RequirementEngine.attached(captured, to: workflowID)
    try expect(attached.workflowID == workflowID, "安排后应关联目标工作流")
    try expect(attached.status == .inbox, "只选择工作流不能代替截止日期和重要程度")
    try expect(attached.status != .active, "安排需求不能自动开始或切换上下文")
    try expect(RequirementEngine.needsPlanning(attached), "关联工作流后仍应完成独立整理")
    try expect(
        RequirementEngine.suggestedWorkflowTitle(
            from: "修复训练失败后的告警。补充对应文档",
            maximumLength: 20
        ) == "修复训练失败后的告警",
        "新工作流建议名称应提取第一句"
    )
}

suite.run("需求截止日期、重要程度和工作流彼此独立") {
    let calendar = utcCalendar()
    let now = calendar.date(from: DateComponents(
        timeZone: calendar.timeZone,
        year: 2026,
        month: 7,
        day: 25,
        hour: 10
    ))!
    let deadline = calendar.date(byAdding: .day, value: 2, to: now)!
    guard let captured = RequirementEngine.captured(
        title: "补上失败告警",
        at: now
    ) else {
        throw VerificationFailure(message: "有效需求应能被收下")
    }
    let workflowID = UUID()
    let planned = RequirementEngine.planned(
        captured,
        dueDate: deadline,
        importance: .high,
        workflowID: workflowID,
        calendar: calendar
    )

    try expect(
        planned.dueDate == calendar.startOfDay(for: deadline),
        "截止日期应按天保存"
    )
    try expect(planned.importance == .high, "重要程度不能被截止日期替代")
    try expect(planned.workflowID == workflowID, "工作流归属应独立保存")
    try expect(planned.status == .planned, "整理需求不能自动开始")
    try expect(!RequirementEngine.needsPlanning(planned), "完整整理后应离开待整理")
}

suite.run("需求无需先整理即可处理且在同一工作流内独立完成") {
    let workflowID = UUID()
    guard let first = RequirementEngine.captured(title: "补上失败告警"),
          let second = RequirementEngine.captured(title: "补充运行手册")
    else {
        throw VerificationFailure(message: "有效需求应能被收下")
    }
    let attachedFirst = RequirementEngine.attached(first, to: workflowID)
    let attachedSecond = RequirementEngine.attached(second, to: workflowID)
    let started = RequirementEngine.started(attachedFirst, in: workflowID)

    try expect(
        RequirementEngine.needsPlanning(started),
        "未安排日期的重要需求仍应保留待确认信息"
    )
    try expect(started.status == .active, "处理决定不能被安排详情阻塞")
    try expect(started.workflowID == workflowID, "处理后应归入目标工作流")

    let completed = RequirementEngine.completed(started, at: Date(timeIntervalSince1970: 100))
    try expect(completed.status == .completed, "完成应只更新当前需求")
    try expect(completed.workflowID == workflowID, "完成需求不应丢失工作流关系")
    try expect(attachedSecond.status == .inbox, "同一工作流中的其他需求不应被完成")
    try expect(attachedSecond.workflowID == workflowID, "工作流应能承接多条需求")
}

suite.run("工作流删除只解绑未完成需求") {
    let workflowID = UUID()
    let otherWorkflowID = UUID()
    guard let activeSource = RequirementEngine.captured(title: "正在做"),
          let completedSource = RequirementEngine.captured(title: "已经做完"),
          let unrelatedSource = RequirementEngine.captured(title: "其他工作流")
    else {
        throw VerificationFailure(message: "有效需求应能被收下")
    }
    let active = RequirementEngine.started(activeSource, in: workflowID)
    let completed = RequirementEngine.completed(
        RequirementEngine.attached(completedSource, to: workflowID)
    )
    let unrelated = RequirementEngine.attached(unrelatedSource, to: otherWorkflowID)
    let detached = RequirementEngine.detachedFromWorkflow(
        active,
        workflowID: workflowID
    )

    try expect(detached.workflowID == nil, "未完成需求应回到未指定工作流")
    try expect(detached.status == .inbox, "未整理的活动需求应回到收件状态")
    try expect(
        RequirementEngine.detachedFromWorkflow(completed, workflowID: workflowID) == completed,
        "已完成需求的历史关系应保留"
    )
    try expect(
        RequirementEngine.detachedFromWorkflow(unrelated, workflowID: workflowID) == unrelated,
        "删除一个工作流不能影响其他工作流的需求"
    )
}

suite.run("工作流名称规范化后保持唯一") {
    try expect(
        WorkflowNamePolicy.normalizedTitle("  发布   FocusTrace  ") == "发布 FocusTrace",
        "工作流名称应折叠多余空白"
    )
    try expect(
        !WorkflowNamePolicy.isAvailable(
            "发布  focustrace",
            among: ["发布 FocusTrace"]
        ),
        "大小写和空白变体不能重复注册"
    )
    try expect(
        !WorkflowNamePolicy.isAvailable(
            "Ｆｏｃｕｓ Ｔｒａｃｅ",
            among: ["focus trace"]
        ),
        "字符宽度变体不能重复注册"
    )
}

suite.run("需求队列按紧迫性再按重要程度排序") {
    let calendar = utcCalendar()
    let now = calendar.date(from: DateComponents(
        timeZone: calendar.timeZone,
        year: 2026,
        month: 7,
        day: 25,
        hour: 10
    ))!
    let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
    let overdue = RequirementRecord(
        title: "逾期",
        capturedAt: now,
        dueDate: yesterday,
        importance: .low,
        status: .planned
    )
    let todayLow = RequirementRecord(
        title: "今天低",
        capturedAt: now,
        dueDate: now,
        importance: .low,
        status: .planned
    )
    let todayHigh = RequirementRecord(
        title: "今天高",
        capturedAt: now.addingTimeInterval(1),
        dueDate: now,
        importance: .high,
        status: .planned
    )
    let future = RequirementRecord(
        title: "未来",
        capturedAt: now,
        dueDate: tomorrow,
        importance: .high,
        status: .planned
    )
    let legacy = RequirementRecord(
        title: "旧版今天",
        capturedAt: now,
        priority: .today,
        status: .planned
    )
    let legacyAttached = RequirementRecord(
        title: "旧版已绑定",
        capturedAt: now,
        planningVersion: 0,
        status: .planned,
        workflowID: UUID()
    )
    let ordered = RequirementEngine.ordered(
        [legacy, future, todayLow, overdue, todayHigh],
        at: now,
        calendar: calendar
    )

    try expect(
        ordered.map(\.id) == [
            overdue.id,
            todayHigh.id,
            todayLow.id,
            future.id,
            legacy.id
        ],
        "队列必须先按逾期、今天、未来排序，同一天再按重要程度"
    )
    try expect(
        RequirementEngine.queueSection(
            for: legacy,
            at: now,
            calendar: calendar
        ) == .needsPlanning,
        "旧版模糊安排必须要求确认，不能猜测截止日期"
    )
    try expect(
        RequirementEngine.needsPlanning(legacyAttached),
        "旧版只绑定工作流的需求也必须重新确认三项安排"
    )
}

suite.run("需求到期只提醒一次且千项排序不超预算") {
    let calendar = utcCalendar()
    let now = calendar.date(from: DateComponents(
        timeZone: calendar.timeZone,
        year: 2026,
        month: 7,
        day: 25,
        hour: 10
    ))!
    let due = RequirementRecord(
        title: "今天",
        dueDate: now,
        status: .planned
    )
    let alreadySent = RequirementRecord(
        title: "已提醒",
        dueDate: now,
        reminderSentAt: now.addingTimeInterval(-60),
        status: .planned
    )
    let active = RequirementRecord(
        title: "正在处理",
        dueDate: now,
        status: .active
    )
    try expect(
        RequirementEngine.dueForReminder(
            [alreadySent, active, due],
            at: now,
            calendar: calendar
        ).map(\.id) == [due.id],
        "已提醒或正在处理的需求不能重复通知"
    )
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
    let rescheduled = RequirementEngine.planned(
        alreadySent,
        dueDate: tomorrow,
        importance: alreadySent.importance,
        workflowID: alreadySent.workflowID,
        calendar: calendar
    )
    try expect(
        rescheduled.reminderSentAt == nil,
        "用户更改截止日期后应允许新承诺再次提醒"
    )

    let requirements = (0..<FocusTracePerformanceBudget.requirementQueueCount).map {
        index in
        RequirementRecord(
            title: "需求 \(index)",
            capturedAt: now.addingTimeInterval(Double(index)),
            dueDate: now.addingTimeInterval(Double((index % 30) * 86_400)),
            importance: RequirementImportance.allCases[index % 3],
            status: .planned
        )
    }
    let measuredAt = Date()
    let ordered = RequirementEngine.ordered(
        requirements,
        at: now,
        calendar: calendar
    )
    let elapsed = Date().timeIntervalSince(measuredAt)
    try expect(
        ordered.count == FocusTracePerformanceBudget.requirementQueueCount,
        "千项需求排序不能丢失记录"
    )
    try expect(
        elapsed < FocusTracePerformanceBudget.requirementQueueMaximumSeconds,
        "千项需求排序不能超过性能预算"
    )
}

suite.run("日期导航按整日移动且不会越过今天") {
    let calendar = utcCalendar()
    let latest = calendar.date(from: DateComponents(
        timeZone: calendar.timeZone,
        year: 2026,
        month: 7,
        day: 24,
        hour: 18,
        minute: 30
    ))!
    let yesterday = calendar.date(byAdding: .day, value: -1, to: latest)!
    try expect(
        FocusTraceDateNavigation.canMoveForward(
            selection: yesterday,
            latestDate: latest,
            calendar: calendar
        ),
        "昨天应允许前进到今天"
    )

    let today = FocusTraceDateNavigation.movedSelection(
        yesterday,
        byDays: 1,
        latestDate: latest,
        calendar: calendar
    )
    try expect(
        today == calendar.startOfDay(for: latest),
        "日期导航应归一化到当天零点"
    )
    try expect(
        !FocusTraceDateNavigation.canMoveForward(
            selection: today,
            latestDate: latest,
            calendar: calendar
        ),
        "今天不应允许继续向未来移动"
    )

    let capped = FocusTraceDateNavigation.movedSelection(
        latest,
        byDays: 10,
        latestDate: latest,
        calendar: calendar
    )
    try expect(
        capped == calendar.startOfDay(for: latest),
        "任何向未来的偏移都必须封顶在今天"
    )
}

suite.run("大数据时间轴单次聚合且按分钟刷新") {
    let calendar = utcCalendar()
    let start = calendar.date(from: DateComponents(
        timeZone: calendar.timeZone,
        year: 2026,
        month: 7,
        day: 24,
        hour: 9
    ))!
    let apps = (0..<8).map {
        AppIdentity(bundleID: "app.\($0)", name: "App \($0)")
    }
    let activities = (0..<FocusTracePerformanceBudget.timelineActivityCount).map { index in
        let began = start.addingTimeInterval(Double(index * 15))
        return ActivityRecord(
            app: apps[index % apps.count],
            startedAt: began,
            endedAt: began.addingTimeInterval(15),
            taskID: nil,
            focusSessionID: nil,
            classification: .allowed
        )
    }
    let markers = (0..<FocusTracePerformanceBudget.timelineMarkerCount).map { index in
        TimelineMarkerRecord(
            date: start.addingTimeInterval(Double(index * 60)),
            kind: index.isMultiple(of: 3) ? .activeSpaceChanged : .taskChanged
        )
    }
    let range = DateInterval(start: start, duration: 12 * 60 * 60)
    let measuredAt = Date()
    let snapshot = TimelinePresentationEngine.snapshot(
        activities: activities,
        taskIntervals: [],
        interruptions: [],
        markers: markers,
        taskParkings: [],
        range: range,
        now: range.end
    )
    let elapsed = Date().timeIntervalSince(measuredAt)
    try expect(snapshot.buckets.count == 144, "十二小时应生成 144 个五分钟桶")
    try expect(!snapshot.eventBuckets.isEmpty, "关键事件应完成聚合")
    try expect(
        snapshot.summary.appSwitchCount
            == FocusTracePerformanceBudget.timelineActivityCount - 1,
        "大量应用切换统计不应丢失"
    )
    try expect(
        elapsed < FocusTracePerformanceBudget.timelinePresentationMaximumSeconds,
        "大数据时间轴呈现不能超过性能预算"
    )

    let firstTick = start.addingTimeInterval(12.1)
    let secondTick = start.addingTimeInterval(58.9)
    try expect(
        TimelinePresentationEngine.renderMinute(for: firstTick, calendar: calendar)
            == TimelinePresentationEngine.renderMinute(for: secondTick, calendar: calendar),
        "同一分钟的秒级计时不应触发时间轴重算"
    )
}

suite.run("时间轴缓存只在分钟或数据变化时失效") {
    let calendar = utcCalendar()
    let day = calendar.date(from: DateComponents(
        timeZone: calendar.timeZone,
        year: 2026,
        month: 7,
        day: 24,
        hour: 9
    ))!
    let range = DateInterval(start: day, duration: 12 * 60 * 60)
    let first = TimelinePresentationCacheKey(
        selectedDay: day,
        range: range,
        now: day.addingTimeInterval(1),
        dataRevision: 7,
        calendar: calendar
    )
    let sameMinute = TimelinePresentationCacheKey(
        selectedDay: day.addingTimeInterval(15),
        range: range,
        now: day.addingTimeInterval(58),
        dataRevision: 7,
        calendar: calendar
    )
    let nextMinute = TimelinePresentationCacheKey(
        selectedDay: day,
        range: range,
        now: day.addingTimeInterval(61),
        dataRevision: 7,
        calendar: calendar
    )
    let changedData = TimelinePresentationCacheKey(
        selectedDay: day,
        range: range,
        now: day.addingTimeInterval(1),
        dataRevision: 8,
        calendar: calendar
    )
    try expect(first == sameMinute, "同一分钟且数据未变时应复用时间轴呈现")
    try expect(first != nextMinute, "跨分钟后应刷新开放片段时长")
    try expect(first != changedData, "数据变化后必须立即刷新时间轴")
}

suite.run("首次专注工具建议只使用当前工作流的真实应用") {
    let taskID = UUID()
    let otherTaskID = UUID()
    let start = Date(timeIntervalSince1970: 1_000)
    let terminal = AppIdentity(bundleID: "com.apple.Terminal", name: "Terminal")
    let codex = AppIdentity(bundleID: "com.openai.codex", name: "Codex")
    let helper = AppIdentity(bundleID: "com.example.Helper", name: "Helper")
    let activities = [
        ActivityRecord(app: terminal, startedAt: start, endedAt: start.addingTimeInterval(600), taskID: taskID, focusSessionID: nil, classification: .allowed),
        ActivityRecord(app: codex, startedAt: start, endedAt: start.addingTimeInterval(300), taskID: taskID, focusSessionID: nil, classification: .allowed),
        ActivityRecord(app: helper, startedAt: start, endedAt: start.addingTimeInterval(900), taskID: taskID, focusSessionID: nil, classification: .allowed),
        ActivityRecord(app: codex, startedAt: start, endedAt: start.addingTimeInterval(1_200), taskID: otherTaskID, focusSessionID: nil, classification: .allowed)
    ]
    let suggestions = ToolSuggestionEngine.suggestions(from: activities, taskID: taskID)
    try expect(suggestions == [terminal, codex], "建议应按当前工作流使用时长排序并排除 Helper")
}

suite.run("应用切换状态机按事件闭合片段") {
    let start = Date(timeIntervalSince1970: 1_000)
    let appA = AppIdentity(bundleID: "a", name: "A")
    let appB = AppIdentity(bundleID: "b", name: "B")
    var machine = ActivityCaptureStateMachine()
    _ = machine.activate(appA, at: start)
    let duplicate = machine.activate(appA, at: start.addingTimeInterval(2))
    let transition = machine.activate(appB, at: start.addingTimeInterval(12))
    try expect(duplicate.ignoredDuplicate, "同一 Bundle ID 应忽略")
    try expect(transition.closed?.app == appA, "应闭合前一个应用")
    try expect(transition.closedAt == start.addingTimeInterval(12), "闭合时间不正确")
    try expect(transition.opened?.app == appB, "应打开新应用片段")
}

suite.run("睡眠关闭片段且唤醒后重开") {
    let start = Date(timeIntervalSince1970: 1_000)
    let app = AppIdentity(bundleID: "a", name: "A")
    var machine = ActivityCaptureStateMachine()
    _ = machine.activate(app, at: start)
    let asleep = machine.becomeInactive(at: start.addingTimeInterval(20))
    let ignored = machine.activate(app, at: start.addingTimeInterval(30))
    let awake = machine.becomeActive(app, at: start.addingTimeInterval(40))
    try expect(asleep.closed?.app == app, "睡眠时应闭合当前应用")
    try expect(ignored.ignoredDuplicate, "系统非活跃期间不应采集")
    try expect(awake.opened?.startedAt == start.addingTimeInterval(40), "唤醒应从新时间开始")
}

suite.run("锁屏 loginwindow 被视为系统非活动") {
    let loginWindow = AppIdentity(bundleID: "com.apple.loginwindow", name: "loginwindow")
    let normalApp = AppIdentity(bundleID: "com.apple.Terminal", name: "Terminal")
    try expect(SystemActivityGate.isSystemInactiveApp(loginWindow), "loginwindow 应结束活动计时")
    try expect(!SystemActivityGate.isSystemInactiveApp(normalApp), "普通应用不应被当作锁屏")

    let start = Date(timeIntervalSince1970: 1_000)
    var machine = ActivityCaptureStateMachine()
    _ = machine.activate(normalApp, at: start)
    let locked = machine.becomeInactive(at: start.addingTimeInterval(10))
    let unlocked = machine.becomeActive(normalApp, at: start.addingTimeInterval(40))
    try expect(locked.closedAt == start.addingTimeInterval(10), "锁屏时应立即闭合前台片段")
    try expect(unlocked.opened?.startedAt == start.addingTimeInterval(40), "解锁后应从实际返回时间重开")
}

suite.run("跨天自动跟随今天但保留历史查看") {
    let calendar = utcCalendar()
    let yesterday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 19, hour: 23, minute: 59))!
    let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 0, minute: 1))!
    let selectedYesterday = calendar.startOfDay(for: yesterday)
    let rolled = TimelineDateEngine.selectedDateAfterTick(
        selectedDate: selectedYesterday,
        previousNow: yesterday,
        currentNow: today,
        calendar: calendar
    )
    try expect(calendar.isDate(rolled, inSameDayAs: today), "跟随今天时应自动跨天")

    let historical = calendar.date(byAdding: .day, value: -2, to: selectedYesterday)!
    let preserved = TimelineDateEngine.selectedDateAfterTick(
        selectedDate: historical,
        previousNow: yesterday,
        currentNow: today,
        calendar: calendar
    )
    try expect(preserved == historical, "用户主动查看的历史日期不应被改写")
}

suite.run("分心提醒严格遵守 20 秒和基线门槛") {
    try expect(!DistractionGate.shouldTrigger(
        duration: 19.9,
        thresholdSeconds: 20,
        isAllowed: false,
        isFocusActive: true,
        baselineComplete: true
    ), "不足 20 秒不应提醒")
    try expect(DistractionGate.shouldTrigger(
        duration: 20,
        thresholdSeconds: 20,
        isAllowed: false,
        isFocusActive: true,
        baselineComplete: true
    ), "达到 20 秒应提醒")
    try expect(!DistractionGate.shouldTrigger(
        duration: 30,
        thresholdSeconds: 20,
        isAllowed: true,
        isFocusActive: true,
        baselineComplete: true
    ), "允许应用不应提醒")
    try expect(!DistractionGate.shouldTrigger(
        duration: 30,
        thresholdSeconds: 20,
        isAllowed: false,
        isFocusActive: true,
        baselineComplete: false
    ), "基线期不应提醒")
}

suite.run("基线训练时长默认、取整和边界") {
    try expect(TrainingEngine.initialFocusMinutes(baselineStreaks: [600, 900]) == 15, "样本不足应为 15 分钟")
    try expect(TrainingEngine.initialFocusMinutes(baselineStreaks: Array(repeating: 13 * 60, count: 10)) == 15, "应取最近 5 分钟档")
    try expect(TrainingEngine.initialFocusMinutes(baselineStreaks: Array(repeating: 2 * 60, count: 10)) == 10, "首轮下限应为 10 分钟")
    try expect(TrainingEngine.initialFocusMinutes(baselineStreaks: Array(repeating: 60 * 60, count: 10)) == 25, "首轮上限应为 25 分钟")
}

suite.run("五次训练升降级规则") {
    let start = Date(timeIntervalSince1970: 2_000)
    func session(success: Bool, offset: Int) -> FocusSessionRecord {
        let began = start.addingTimeInterval(Double(offset * 1_000))
        return FocusSessionRecord(
            taskID: UUID(),
            startedAt: began,
            endedAt: began.addingTimeInterval(success ? 900 : 600),
            targetSeconds: 900,
            outcome: success ? .completed : .partial,
            difficulty: 3,
            confirmedDistractionCount: 0
        )
    }
    let four = (0..<5).map { session(success: $0 < 4, offset: $0) }
    let two = (0..<5).map { session(success: $0 < 2, offset: $0) }
    let three = (0..<5).map { session(success: $0 < 3, offset: $0) }
    try expect(TrainingEngine.progression(currentMinutes: 15, lastFive: four) == .increase(toMinutes: 20), "4/5 成功应增加 5 分钟")
    try expect(TrainingEngine.progression(currentMinutes: 15, lastFive: two) == .decrease(toMinutes: 10), "2/5 成功应减少 5 分钟")
    try expect(TrainingEngine.progression(currentMinutes: 15, lastFive: three) == .maintain(minutes: 15), "3/5 成功应保持")
}

suite.run("切换干预只在十分钟内第三次最终工作流切换时出现") {
    let start = Date(timeIntervalSince1970: 80_000)
    let taskA = UUID()
    let taskB = UUID()
    let endpointA = WorkflowTransitionEndpoint(
        kind: .workflow,
        workflowID: taskA
    )
    let endpointB = WorkflowTransitionEndpoint(
        kind: .workflow,
        workflowID: taskB
    )
    func transition(
        at date: Date,
        origin: WorkflowTransitionEndpoint,
        destination: WorkflowTransitionEndpoint,
        trigger: WorkflowInterventionTrigger? = nil
    ) -> WorkflowTransitionRecord {
        WorkflowTransitionRecord(
            navigationStartedAt: date.addingTimeInterval(-2),
            settledAt: date.addingTimeInterval(-0.5),
            resolvedAt: date,
            origin: origin,
            destination: destination,
            outcome: trigger == nil ? .automatic : .confirmed,
            reason: trigger == nil ? nil : .reachedCheckpoint,
            interventionTrigger: trigger,
            navigationEventCount: 1
        )
    }
    let first = transition(
        at: start,
        origin: endpointA,
        destination: endpointB
    )
    let second = transition(
        at: start.addingTimeInterval(120),
        origin: endpointB,
        destination: endpointA
    )
    try expect(
        !WorkflowSwitchInterventionEngine.decision(
            history: [first],
            origin: endpointB,
            destination: endpointA,
            at: start.addingTimeInterval(120),
            isEnabled: true
        ).shouldPrompt,
        "前两次正常工作流切换必须静默"
    )
    let third = WorkflowSwitchInterventionEngine.decision(
        history: [first, second],
        origin: endpointA,
        destination: endpointB,
        at: start.addingTimeInterval(240),
        isEnabled: true
    )
    try expect(
        third.shouldPrompt
            && third.trigger == .frequentSwitchBurst,
        "十分钟内第三次最终工作流切换才应请求确认"
    )
    let prompted = transition(
        at: start.addingTimeInterval(240),
        origin: endpointA,
        destination: endpointB,
        trigger: .frequentSwitchBurst
    )
    try expect(
        !WorkflowSwitchInterventionEngine.decision(
            history: [first, second, prompted],
            origin: endpointB,
            destination: endpointA,
            at: start.addingTimeInterval(300),
            isEnabled: true
        ).shouldPrompt,
        "确认后的十分钟冷却期不得再次打扰"
    )

    let audit = WorkflowSwitchInterventionEngine.audit(
        transitions: [first, second, prompted],
        range: start..<start.addingTimeInterval(3_600),
        now: start.addingTimeInterval(900)
    )
    try expect(
        audit.frequentSwitchEpisodes == 1
            && audit.promptsShown == 1
            && audit.quietAfterPromptRate == 1,
        "回顾必须能验证高频段、实际确认和确认后稳定性"
    )
}

suite.run("每日观察配置只重分配分析精力") {
    func analysis(
        recordedMinutes: Double,
        reliable: Bool
    ) -> DailyCoachingAnalysis {
        DailyCoachingAnalysis(
            metrics: DailyNormalizedMetrics(
                recordedMinutes: recordedMinutes,
                attributedMinutes: reliable ? recordedMinutes : 0,
                attributedRatio: reliable ? 1 : 0,
                appSwitchesPerHour: 2,
                workflowSwitchesPerHour: 1,
                medianFocusMinutes: 15,
                trainingCount: 1,
                successfulTrainingCount: 1,
                feedbackCompletionRatio: 1,
                parkingCount: 0
            ),
            quality: DailyDataQuality(
                isReliableForBehavior: reliable,
                warnings: reliable ? [] : ["工作流归因不足"]
            ),
            trend: DailyTrendComparison(
                baselineDays: 3,
                appSwitchRateDeltaPercent: nil,
                workflowSwitchRateDeltaPercent: nil,
                attributedRatioDeltaPoints: nil,
                medianFocusDeltaMinutes: nil
            ),
            recommendation: DailyCoachRecommendation(
                kind: .maintainRound,
                title: "保持",
                rationale: "验证",
                evidence: [],
                confidence: .medium,
                action: .none,
                method: DailyTrainingMethod(
                    title: "验证",
                    steps: [],
                    successMeasure: "验证"
                )
            ),
            previousRecommendationEvaluation: nil
        )
    }
    let summary = DailySummary(
        appSwitchCount: 0,
        taskSwitchCount: 0,
        workflowSwitchCount: 0,
        suspectedDistractionCount: 0,
        confirmedDistractionCount: 0,
        averageReturnLatency: nil,
        medianFocusStreak: nil,
        taskParkingCount: 0,
        resumedTaskCount: 0,
        averageTaskResumeLatency: nil,
        appDurations: [:],
        taskDurations: [:]
    )
    let quietAudit = WorkflowInterventionAudit(
        frequentSwitchEpisodes: 0,
        promptsShown: 0,
        confirmedPrompts: 0,
        timedOutPrompts: 0,
        assessedPrompts: 0,
        quietAfterPromptCount: 0
    )
    let initial = ObservationPlanEngine.makePlan(
        coaching: analysis(recordedMinutes: 0, reliable: false),
        summary: summary,
        interventionAudit: quietAudit
    )
    try expect(
        initial.source == .initialDefault
            && initial.allocations.map(\.percent) == [25, 25, 25, 25]
            && initial.rawCollectionMode == .minimalEventDrivenFixed,
        "无数据时必须使用均衡初始配置且不改变原始采集"
    )

    let unreliable = ObservationPlanEngine.makePlan(
        coaching: analysis(recordedMinutes: 60, reliable: false),
        summary: summary,
        interventionAudit: quietAudit
    )
    try expect(
        unreliable.primaryAllocation?.lens == .dataQuality
            && unreliable.primaryAllocation?.percent == 70
            && unreliable.allocations.reduce(0) { $0 + $1.percent } == 100,
        "不可靠数据必须把分析重点转向质量修复"
    )

    let semanticAudit = WorkflowInterventionAudit(
        frequentSwitchEpisodes: 1,
        promptsShown: 0,
        confirmedPrompts: 0,
        timedOutPrompts: 0,
        assessedPrompts: 0,
        quietAfterPromptCount: 0
    )
    let semantic = ObservationPlanEngine.makePlan(
        coaching: analysis(recordedMinutes: 60, reliable: true),
        summary: summary,
        interventionAudit: semanticAudit
    )
    try expect(
        semantic.primaryAllocation?.lens == .workflowSemantics,
        "高频工作流切换段应加重语义与后果联合分析"
    )
}

suite.run("Space 切换门覆盖工作流边界且始终可退出") {
    let workflowA = UUID()
    let workflowB = UUID()
    let workflowC = UUID()
    let start = Date(timeIntervalSince1970: 90_000)
    let pending = SpaceSwitchGateEngine.begin(
        origin: .bound(workflowID: workflowA),
        destination: .bound(workflowID: workflowB),
        at: start,
        isEnabled: true
    )
    try expect(pending != nil, "离开已绑定工作流应进入切换门")
    try expect(
        SpaceSwitchGateEngine.begin(
            origin: .bound(workflowID: workflowA),
            destination: .bound(workflowID: workflowA),
            at: start,
            isEnabled: true
        ) == nil,
        "同一工作流的多个桌面之间不应阻挡"
    )
    try expect(
        SpaceSwitchGateEngine.begin(
            origin: .unbound,
            destination: .bound(workflowID: workflowB),
            at: start,
            isEnabled: true
        ) != nil,
        "从未绑定桌面进入工作流也应形成切换边界"
    )
    try expect(
        SpaceSwitchGateEngine.begin(
            origin: .unbound,
            destination: .unbound,
            at: start,
            isEnabled: true
        ) == nil,
        "两个都未绑定的桌面之间不应制造无意义的切换门"
    )
    guard let pending else {
        throw VerificationFailure(message: "切换门未创建")
    }
    try expect(
        SpaceSwitchGateEngine.observe(
            .bound(workflowID: workflowA),
            while: pending
        ) == .returnedToOrigin,
        "滑回原桌面必须取消切换"
    )
    guard case let .destinationChanged(updated) = SpaceSwitchGateEngine.observe(
        .bound(workflowID: workflowC),
        while: pending
    ) else {
        throw VerificationFailure(message: "切到第三个桌面应更新目标")
    }
    try expect(
        updated.origin == pending.origin
            && updated.expiresAt == pending.expiresAt,
        "更新目标不能丢失原上下文或延长阻挡时间"
    )
    try expect(
        !SpaceSwitchGateEngine.hasExpired(
            pending,
            at: start.addingTimeInterval(9.9)
        )
            && SpaceSwitchGateEngine.hasExpired(
                pending,
                at: start.addingTimeInterval(10)
            ),
        "切换门必须在 10 秒时安全放行"
    )
}

suite.run("连续 Space 导航保留起点且只确认最终工作流") {
    let workflowA = UUID()
    let workflowB = UUID()
    let workflowC = UUID()
    let start = Date(timeIntervalSince1970: 90_500)
    let first = SpaceSwitchJourneyEngine.beginOrExtend(
        nil,
        origin: .bound(workflowID: workflowA),
        at: start
    )
    guard let first,
          let throughB = SpaceSwitchJourneyEngine.beginOrExtend(
              first,
              origin: .unknown,
              candidateDestination: .bound(workflowID: workflowB),
              at: start.addingTimeInterval(0.4)
          ),
          let finalC = SpaceSwitchJourneyEngine.beginOrExtend(
              throughB,
              origin: .unknown,
              candidateDestination: .bound(workflowID: workflowC),
              at: start.addingTimeInterval(0.8)
          ) else {
        throw VerificationFailure(message: "连续 Space 导航上下文创建失败")
    }
    try expect(
        finalC.origin == .bound(workflowID: workflowA)
            && finalC.candidateDestination == .bound(workflowID: workflowC)
            && finalC.eventCount == 3,
        "连续 Space 事件不能丢失最初工作流或停在中间工作流"
    )
    try expect(
        SpaceSwitchJourneyEngine.finish(
            finalC,
            finalDestination: .bound(workflowID: workflowC),
            at: start.addingTimeInterval(1.9),
            isGateEnabled: true
        ) == .notSettled,
        "最后一次变化不足 1.2 秒时不能提前弹窗"
    )
    guard case let .presentGate(pending) = SpaceSwitchJourneyEngine.finish(
        finalC,
        finalDestination: .bound(workflowID: workflowC),
        at: start.addingTimeInterval(2.0),
        isGateEnabled: true
    ) else {
        throw VerificationFailure(message: "稳定后没有为最终工作流创建切换门")
    }
    try expect(
        pending.origin == .bound(workflowID: workflowA)
            && pending.destination == .bound(workflowID: workflowC),
        "切换门必须只显示整段导航的起点和最终工作流"
    )
    try expect(
        SpaceSwitchJourneyEngine.finish(
            finalC,
            finalDestination: .bound(workflowID: workflowA),
            at: start.addingTimeInterval(2.0),
            isGateEnabled: true
        ) == .unchanged(.bound(workflowID: workflowA)),
        "最终回到原工作流时不应显示切换门"
    )
}

suite.run("确认层在继续导航后保留完整可操作时间") {
    let workflowA = UUID()
    let workflowB = UUID()
    let workflowC = UUID()
    let start = Date(timeIntervalSince1970: 90_800)
    guard let pending = SpaceSwitchGateEngine.begin(
        origin: .bound(workflowID: workflowA),
        destination: .bound(workflowID: workflowB),
        at: start,
        isEnabled: true
    ), let refreshed = SpaceSwitchGateEngine.refreshed(
        pending,
        destination: .bound(workflowID: workflowC),
        at: start.addingTimeInterval(4)
    ) else {
        throw VerificationFailure(message: "最终桌面稳定后应恢复确认层")
    }
    try expect(
        refreshed.origin == pending.origin
            && refreshed.destination == .bound(workflowID: workflowC),
        "继续导航不能丢失最初工作流，且必须更新最终落点"
    )
    try expect(
        refreshed.expiresAt.timeIntervalSince(refreshed.startedAt)
            == SpaceSwitchGateEngine.decisionWindowSeconds,
        "最终桌面稳定后必须重新提供完整 10 秒操作时间"
    )
}

suite.run("连续专注在分心和任务变化处断开") {
    let taskA = UUID()
    let taskB = UUID()
    let start = Date(timeIntervalSince1970: 1_000)
    let app = AppIdentity(bundleID: "app", name: "App")
    let records = [
        ActivityRecord(app: app, startedAt: start, endedAt: start.addingTimeInterval(60), taskID: taskA, focusSessionID: nil, classification: .allowed),
        ActivityRecord(app: app, startedAt: start.addingTimeInterval(60), endedAt: start.addingTimeInterval(120), taskID: taskA, focusSessionID: nil, classification: .necessary),
        ActivityRecord(app: app, startedAt: start.addingTimeInterval(120), endedAt: start.addingTimeInterval(150), taskID: taskA, focusSessionID: nil, classification: .suspectedDistraction),
        ActivityRecord(app: app, startedAt: start.addingTimeInterval(150), endedAt: start.addingTimeInterval(180), taskID: taskB, focusSessionID: nil, classification: .allowed)
    ]
    try expect(TrainingEngine.baselineStreaks(from: records) == [120, 30], "连续专注区间计算错误")
}

suite.run("每日指标分开统计应用、桌面工作流、手动切换和确认分心") {
    let task = UUID()
    let focus = UUID()
    let start = Date(timeIntervalSince1970: 10_000)
    let a = AppIdentity(bundleID: "a", name: "A")
    let b = AppIdentity(bundleID: "b", name: "B")
    let activities = [
        ActivityRecord(app: a, startedAt: start, endedAt: start.addingTimeInterval(60), taskID: task, focusSessionID: focus, classification: .allowed),
        ActivityRecord(app: b, startedAt: start.addingTimeInterval(60), endedAt: start.addingTimeInterval(90), taskID: task, focusSessionID: focus, classification: .confirmedDistraction),
        ActivityRecord(app: a, startedAt: start.addingTimeInterval(90), endedAt: start.addingTimeInterval(150), taskID: task, focusSessionID: focus, classification: .allowed)
    ]
    let interruption = InterruptionRecord(
        activityID: activities[1].id,
        focusSessionID: focus,
        taskID: task,
        app: b,
        detectedAt: start.addingTimeInterval(80),
        resolvedAt: start.addingTimeInterval(90),
        resolution: .returnedToTask
    )
    let summary = MetricsEngine.dailySummary(
        activities: activities,
        taskIntervals: [
            TaskIntervalRecord(taskID: task, startedAt: start, endedAt: start.addingTimeInterval(50)),
            TaskIntervalRecord(
                taskID: task,
                startedAt: start.addingTimeInterval(50),
                endedAt: start.addingTimeInterval(100),
                workflowSource: .space
            ),
            TaskIntervalRecord(
                taskID: task,
                startedAt: start.addingTimeInterval(100),
                endedAt: start.addingTimeInterval(150),
                workflowSource: .manual
            )
        ],
        interruptions: [interruption],
        now: start.addingTimeInterval(150)
    )
    try expect(summary.appSwitchCount == 2, "应用切换次数错误")
    try expect(summary.workflowSwitchCount == 1, "桌面工作流切换次数错误")
    try expect(summary.taskSwitchCount == 1, "手动任务切换次数错误")
    try expect(summary.confirmedDistractionCount == 1, "确认分心次数错误")
    try expect(summary.averageReturnLatency == 10, "返回耗时错误")
}

suite.run("五分钟时间轴聚合主应用和切换密度") {
    let start = Date(timeIntervalSince1970: 40_000)
    let range = DateInterval(start: start, duration: 10 * 60)
    let appA = AppIdentity(bundleID: "a", name: "A")
    let appB = AppIdentity(bundleID: "b", name: "B")
    let system = AppIdentity(bundleID: "system", name: "System")
    let activities = [
        ActivityRecord(app: appA, startedAt: start, endedAt: start.addingTimeInterval(180), taskID: nil, focusSessionID: nil, classification: .allowed),
        ActivityRecord(app: appB, startedAt: start.addingTimeInterval(180), endedAt: start.addingTimeInterval(240), taskID: nil, focusSessionID: nil, classification: .allowed),
        ActivityRecord(app: appA, startedAt: start.addingTimeInterval(240), endedAt: start.addingTimeInterval(420), taskID: nil, focusSessionID: nil, classification: .necessary),
        ActivityRecord(app: system, startedAt: start.addingTimeInterval(420), endedAt: start.addingTimeInterval(450), taskID: nil, focusSessionID: nil, classification: .systemInactive),
        ActivityRecord(app: appB, startedAt: start.addingTimeInterval(450), endedAt: start.addingTimeInterval(600), taskID: nil, focusSessionID: nil, classification: .allowed)
    ]
    let markers = [
        TimelineMarkerRecord(date: start.addingTimeInterval(100), kind: .activeSpaceChanged),
        TimelineMarkerRecord(date: start.addingTimeInterval(320), kind: .activeSpaceChanged)
    ]
    let buckets = TimelineAggregationEngine.buckets(
        activities: activities,
        markers: markers,
        range: range,
        now: range.end
    )
    try expect(buckets.count == 2, "10 分钟应聚合成两个桶")
    try expect(buckets[0].dominantApp == appA, "第一桶主应用应按停留时长计算")
    try expect(buckets[0].switchCount == 2, "第一桶切换数错误")
    try expect(buckets[0].spaceSwitchCount == 1, "第一桶 Space 计数错误")
    try expect(buckets[1].dominantApp == appB, "系统非活动不应成为主应用")
    try expect(buckets[1].switchCount == 1, "第二桶切换数错误")
    try expect(buckets[1].uniqueAppCount == 2, "系统非活动不应计入应用数")
}

suite.run("碎片化等级边界稳定") {
    try expect(FragmentationLevel.classify(switchCount: 2) == .quiet, "2 次应为稳定")
    try expect(FragmentationLevel.classify(switchCount: 3) == .steady, "3 次应为中等")
    try expect(FragmentationLevel.classify(switchCount: 6) == .fragmented, "6 次应为碎片化")
    try expect(FragmentationLevel.classify(switchCount: 11) == .intense, "11 次应为高碎片化")
}

suite.run("相邻系统事件按十五分钟合并且忽略 Space") {
    let start = Date(timeIntervalSince1970: 50_000)
    let range = DateInterval(start: start, duration: 60 * 60)
    let buckets = TimelineEventAggregationEngine.buckets(
        markers: [
            TimelineMarkerRecord(date: start.addingTimeInterval(60), kind: .screenSlept),
            TimelineMarkerRecord(date: start.addingTimeInterval(5 * 60), kind: .screenWoke),
            TimelineMarkerRecord(date: start.addingTimeInterval(8 * 60), kind: .activeSpaceChanged),
            TimelineMarkerRecord(date: start.addingTimeInterval(20 * 60), kind: .taskChanged)
        ],
        range: range
    )
    try expect(buckets.count == 2, "三个可见事件应形成两个事件簇")
    try expect(buckets[0].eventCount == 2, "相邻睡眠和唤醒应合并")
    try expect(buckets[0].countsByKind[.screenSlept] == 1, "事件类型计数错误")
    try expect(buckets[1].kinds == [.taskChanged], "任务事件应落入下一事件簇")
}

suite.run("工作流完成释放桌面且保留可撤销状态") {
    let workflowID = UUID()
    let completedAt = Date(timeIntervalSince1970: 60_000)
    var state = WorkflowLifecycleState(
        workflowID: workflowID,
        bindingCount: 2,
        hasCheckpoint: true
    )
    let completed = try WorkflowLifecycleEngine.transition(state, event: .complete, at: completedAt)
    try expect(completed.state.lifecycle == .completed, "完成后生命周期错误")
    try expect(completed.state.bindingCount == 0, "完成后应释放所有桌面绑定")
    try expect(completed.state.completedAt == completedAt, "完成时间错误")
    try expect(completed.effects.contains(.releaseAllBindings(workflowID: workflowID)), "缺少释放绑定副作用")
    try expect(completed.effects.contains(.checkpointResolved(workflowID: workflowID)), "完成时应解决检查点")

    state = completed.state
    let undone = try WorkflowLifecycleEngine.transition(state, event: .undoCompletion, at: completedAt.addingTimeInterval(10))
    try expect(undone.state.lifecycle == .open, "撤销后应重新打开")
    try expect(undone.state.bindingCount == 0, "撤销不能猜测恢复旧桌面")
    try expect(undone.effects == [.requiresRebind(workflowID: workflowID)], "撤销后应要求重新绑定")
}

suite.run("桌面解析对未知和冲突绝不猜测") {
    let workflowA = UUID()
    let workflowB = UUID()
    try expect(
        WorkflowSpaceResolutionEngine.resolve(activeAnchorWorkflowIDs: [workflowA], registryReady: false) == .unknown,
        "锚点未就绪时必须未知"
    )
    try expect(
        WorkflowSpaceResolutionEngine.resolve(activeAnchorWorkflowIDs: [], registryReady: true) == .unbound,
        "无锚点命中应为未绑定"
    )
    try expect(
        WorkflowSpaceResolutionEngine.resolve(activeAnchorWorkflowIDs: [workflowA, workflowA], registryReady: true) == .bound(workflowID: workflowA),
        "同一工作流多个锚点不应冲突"
    )
    if case let .conflict(ids) = WorkflowSpaceResolutionEngine.resolve(
        activeAnchorWorkflowIDs: [workflowA, workflowB],
        registryReady: true
    ) {
        try expect(Set(ids) == Set([workflowA, workflowB]), "冲突应保留工作流集合")
    } else {
        throw VerificationFailure(message: "多个工作流锚点必须进入冲突")
    }
}

suite.run("稳定 Space 身份不随新增、重排或删除其他桌面移位") {
    let workflowID = UUID()
    let original = WorkflowSpaceIdentity(
        displayIdentifier: "display-a",
        managedSpaceID: 304,
        spaceUUID: "space-original"
    )
    let inserted = WorkflowSpaceIdentity(
        displayIdentifier: "display-a",
        managedSpaceID: 495,
        spaceUUID: "space-inserted"
    )
    let binding = WorkflowSpaceBindingRecord(
        workflowID: workflowID,
        anchorRestorationID: "legacy-only",
        displayHint: "display-a",
        spaceIdentity: original
    )
    try expect(
        WorkflowSpaceResolutionEngine.resolve(
            currentSpaceIdentity: original,
            bindings: [binding],
            registryReady: true
        ) == .bound(workflowID: workflowID),
        "原 Space 应继续命中原工作流"
    )
    try expect(
        WorkflowSpaceResolutionEngine.resolve(
            currentSpaceIdentity: inserted,
            bindings: [binding],
            registryReady: true
        ) == .unbound,
        "新增 Space 不得继承已有绑定"
    )
    let sameIDOnAnotherDisplay = WorkflowSpaceIdentity(
        displayIdentifier: "display-b",
        managedSpaceID: 304,
        spaceUUID: "space-original"
    )
    try expect(
        !original.identifiesSameSpace(as: sameIDOnAnotherDisplay),
        "Space 身份必须按显示器隔离"
    )
    try expect(
        WorkflowSpaceResolutionEngine.resolve(
            currentSpaceIdentity: original,
            bindings: [binding],
            registryReady: true
        ) == .bound(workflowID: workflowID),
        "删除其他 Space 后原 Space 应继续命中原工作流"
    )
}

suite.run("全局 active Space ID 可以唯一反查稳定身份") {
    let pointerDisplaySpace = WorkflowSpaceIdentity(
        displayIdentifier: "display-under-pointer",
        managedSpaceID: 304,
        spaceUUID: "pointer-space"
    )
    let actuallyActivatedSpace = WorkflowSpaceIdentity(
        displayIdentifier: "display-that-changed",
        managedSpaceID: 495,
        spaceUUID: "active-space"
    )
    try expect(
        WorkflowSpaceIdentitySelector.activeIdentity(
            managedSpaceID: 495,
            allSpaces: [pointerDisplaySpace, actuallyActivatedSpace]
        ) == actuallyActivatedSpace,
        "必须选择窗口服务器报告的 active Space"
    )
    let duplicate = WorkflowSpaceIdentity(
        displayIdentifier: "ambiguous-display",
        managedSpaceID: 495,
        spaceUUID: "ambiguous-space"
    )
    try expect(
        WorkflowSpaceIdentitySelector.activeIdentity(
            managedSpaceID: 495,
            allSpaces: [actuallyActivatedSpace, duplicate]
        ) == nil,
        "active Space ID 不唯一时必须进入未知"
    )
}

suite.run("多显示器切换使用 Current Space 差量而不是陈旧全局 active") {
    let displayAOld = WorkflowSpaceIdentity(
        displayIdentifier: "display-a",
        managedSpaceID: 1,
        spaceUUID: "desktop-a-old"
    )
    let displayANew = WorkflowSpaceIdentity(
        displayIdentifier: "display-a",
        managedSpaceID: 621,
        spaceUUID: "desktop-a-new"
    )
    let staleGlobalActive = WorkflowSpaceIdentity(
        displayIdentifier: "display-b",
        managedSpaceID: 346,
        spaceUUID: "desktop-b"
    )
    let displayC = WorkflowSpaceIdentity(
        displayIdentifier: "display-c",
        managedSpaceID: 521,
        spaceUUID: "desktop-c"
    )
    try expect(
        WorkflowSpaceTransitionSelector.changedIdentity(
            previousCurrentSpaces: [displayAOld, staleGlobalActive, displayC],
            currentSpaces: [displayANew, staleGlobalActive, displayC],
            activeIdentity: staleGlobalActive
        ) == displayANew,
        "单个显示器发生 Space 变化时不得被其他显示器的全局 active 覆盖"
    )
    try expect(
        WorkflowSpaceTransitionSelector.changedIdentity(
            previousCurrentSpaces: [displayAOld, staleGlobalActive],
            currentSpaces: [displayANew, displayC],
            activeIdentity: displayC
        ) == displayC,
        "多个显示器同时变化时才允许用 active Space 消歧"
    )
    try expect(
        WorkflowSpaceTransitionSelector.changedIdentity(
            previousCurrentSpaces: [displayANew, staleGlobalActive, displayC],
            currentSpaces: [displayANew, staleGlobalActive, displayC],
            activeIdentity: staleGlobalActive
        ) == nil,
        "没有显示器变化时不得回退到其他显示器的全局 active Space"
    )
}

suite.run("旧单显示器与全局 active 绑定升级后必须一次性重绑") {
    let identity = WorkflowSpaceIdentity(
        displayIdentifier: "display-a",
        managedSpaceID: 304,
        spaceUUID: "space-a"
    )
    try expect(
        !WorkflowSpaceBindingCompatibility.canRestore(
            identity: identity,
            identityVersion: nil
        ),
        "旧绑定没有版本时不得继续恢复"
    )
    try expect(
        !WorkflowSpaceBindingCompatibility.canRestore(
            identity: identity,
            identityVersion: 1
        ),
        "鼠标显示器算法生成的绑定不得继续恢复"
    )
    try expect(
        !WorkflowSpaceBindingCompatibility.canRestore(
            identity: identity,
            identityVersion: 2
        ),
        "多显示器下全局 active 算法生成的绑定不得继续恢复"
    )
    try expect(
        WorkflowSpaceBindingCompatibility.canRestore(
            identity: identity,
            identityVersion: WorkflowSpaceBindingCompatibility.currentIdentityVersion
        ),
        "按显示器差量算法生成的绑定应可恢复"
    )
}

suite.run("旧桌面绑定兼容解码但要求一次性重绑") {
    let workflowID = UUID()
    let bindingID = UUID()
    let json = """
    {
      "id": "\(bindingID.uuidString)",
      "workflowID": "\(workflowID.uuidString)",
      "anchorRestorationID": "old-window-anchor",
      "state": "verified",
      "boundAt": 1000
    }
    """
    let binding = try JSONDecoder().decode(
        WorkflowSpaceBindingRecord.self,
        from: Data(json.utf8)
    )
    try expect(binding.id == bindingID, "旧绑定 ID 未保留")
    try expect(binding.spaceIdentity == nil, "旧窗口锚点不得伪造稳定 Space 身份")
}

suite.run("工作流上下文切换闭合旧区间并打开未知区间") {
    let workflowID = UUID()
    let start = Date(timeIntervalSince1970: 70_000)
    let entered = WorkflowContextEngine.transition(
        WorkflowContextState(),
        to: .bound(workflowID: workflowID),
        at: start
    )
    try expect(entered.state.context.workflowID == workflowID, "应进入绑定工作流")
    try expect(entered.effects.contains(.workflowBecameForeground(workflowID: workflowID)), "缺少前台副作用")

    let unknownAt = start.addingTimeInterval(30)
    let unknown = WorkflowContextEngine.transition(entered.state, to: .unknown, at: unknownAt)
    try expect(unknown.state.context.kind == .unknown, "识别失败应进入 unknown")
    try expect(unknown.state.context.workflowID == nil, "unknown 不应沿用旧工作流")
    try expect(unknown.effects.contains(.workflowBecameBackground(workflowID: workflowID)), "旧工作流应转后台")
    try expect(unknown.effects.contains(.closeInterval(
        context: entered.state.context,
        startedAt: start,
        endedAt: unknownAt
    )), "旧区间未正确闭合")
}

suite.run("跨桌面专注宽限、暂停、恢复和有效时长") {
    let focusWorkflow = UUID()
    let otherWorkflow = UUID()
    let start = Date(timeIntervalSince1970: 80_000)
    let initial = FocusWorkflowDepartureState(focusWorkflowID: focusWorkflow)

    let briefDeparture = FocusWorkflowDepartureEngine.contextChanged(
        initial,
        to: otherWorkflow,
        at: start
    )
    try expect(briefDeparture.state.pendingDepartureAt == start, "离开后应进入宽限")
    try expect(
        briefDeparture.effects == [.scheduleGrace(deadline: start.addingTimeInterval(10))],
        "宽限截止时间错误"
    )
    let briefReturn = FocusWorkflowDepartureEngine.contextChanged(
        briefDeparture.state,
        to: focusWorkflow,
        at: start.addingTimeInterval(8)
    )
    try expect(briefReturn.effects == [.cancelGrace], "10 秒内返回只应取消宽限")
    try expect(briefReturn.state.pausedAt == nil, "短暂误触不应暂停")

    let departedAgain = FocusWorkflowDepartureEngine.contextChanged(
        briefReturn.state,
        to: otherWorkflow,
        at: start.addingTimeInterval(20)
    )
    let paused = FocusWorkflowDepartureEngine.graceElapsed(departedAgain.state)
    try expect(paused.state.pausedAt == start.addingTimeInterval(20), "暂停应从离开时刻开始")
    let resumed = FocusWorkflowDepartureEngine.contextChanged(
        paused.state,
        to: focusWorkflow,
        at: start.addingTimeInterval(45)
    )
    try expect(resumed.state.accumulatedPausedSeconds == 25, "暂停累计时长错误")
    try expect(resumed.effects == [.resumed(pausedSeconds: 25)], "恢复副作用错误")
    try expect(
        FocusWorkflowDepartureEngine.activeElapsedSeconds(
            startedAt: start,
            endedAt: start.addingTimeInterval(100),
            state: resumed.state
        ) == 75,
        "有效专注时长应扣除跨桌面暂停"
    )

    let session = FocusSessionRecord(
        taskID: focusWorkflow,
        startedAt: start,
        endedAt: start.addingTimeInterval(100),
        targetSeconds: 80,
        outcome: .completed,
        difficulty: 2,
        confirmedDistractionCount: 0,
        pausedSeconds: 25
    )
    try expect(!session.reachedTarget, "训练成功判定必须扣除暂停时间")
}

suite.run("旧任务生命周期兼容迁移") {
    try expect(
        WorkflowLifecycleMigration.lifecycle(rawValue: nil, isArchived: false, completedAt: nil) == .open,
        "普通旧任务应迁移为 open"
    )
    try expect(
        WorkflowLifecycleMigration.lifecycle(rawValue: nil, isArchived: true, completedAt: nil) == .archived,
        "已归档旧任务应保留归档状态"
    )
    try expect(
        WorkflowLifecycleMigration.lifecycle(rawValue: nil, isArchived: false, completedAt: Date()) == .completed,
        "已有完成时间应迁移为 completed"
    )
}

suite.run("任务停车只提醒到期且未解决的线索") {
    let now = Date(timeIntervalSince1970: 20_000)
    let task = UUID()
    let due = TaskParkingRecord(
        taskID: task,
        parkedAt: now.addingTimeInterval(-600),
        resumeCue: "run tests",
        remindAt: now.addingTimeInterval(-1)
    )
    let future = TaskParkingRecord(
        taskID: task,
        parkedAt: now,
        resumeCue: "review output",
        remindAt: now.addingTimeInterval(300)
    )
    let sent = TaskParkingRecord(
        taskID: task,
        parkedAt: now.addingTimeInterval(-600),
        resumeCue: "sent",
        remindAt: now.addingTimeInterval(-1),
        reminderSentAt: now.addingTimeInterval(-30)
    )
    let resumed = TaskParkingRecord(
        taskID: task,
        parkedAt: now.addingTimeInterval(-600),
        resumeCue: "done",
        remindAt: now.addingTimeInterval(-1),
        resumedAt: now
    )
    let result = TaskParkingEngine.dueForReminder([due, future, sent, resumed], at: now)
    try expect(result.map(\.id) == [due.id], "到期提醒筛选错误")
}

suite.run("任务停车指标统计恢复率和耗时") {
    let start = Date(timeIntervalSince1970: 30_000)
    let task = UUID()
    let parkings = [
        TaskParkingRecord(
            taskID: task,
            parkedAt: start,
            resumeCue: "first",
            resumedAt: start.addingTimeInterval(600)
        ),
        TaskParkingRecord(
            taskID: task,
            parkedAt: start,
            resumeCue: "second",
            resumedAt: start.addingTimeInterval(1_200)
        ),
        TaskParkingRecord(taskID: task, parkedAt: start, resumeCue: "active")
    ]
    let summary = MetricsEngine.dailySummary(
        activities: [],
        taskIntervals: [],
        interruptions: [],
        taskParkings: parkings,
        now: start
    )
    try expect(summary.taskParkingCount == 3, "挂起次数错误")
    try expect(summary.resumedTaskCount == 2, "恢复次数错误")
    try expect(summary.averageTaskResumeLatency == 900, "平均恢复耗时错误")
}

suite.run("阶段 2 在门槛前保持锁定") {
    let plan = TrainingPlanRecord(version: 1, focusMinutes: 15, reason: "default")
    let result = AdaptiveAnalyzer.analyze(activities: [], sessions: [], interruptions: [], currentPlan: plan)
    try expect(result.readiness == .locked(workdays: 0, sessions: 0), "空数据应锁定")
    try expect(result.suggestion == nil, "锁定时不应给建议")
}

suite.run("阶段 2 完整 10 日 / 20 次样本识别模式") {
    let fixture = phaseTwoFixture()
    let result = AdaptiveAnalyzer.analyze(
        activities: fixture.snapshot.activities,
        sessions: fixture.snapshot.focusSessions,
        interruptions: fixture.snapshot.interruptions,
        currentPlan: fixture.snapshot.currentPlan,
        calendar: fixture.calendar
    )
    try expect(result.readiness == .ready, "满足门槛后应解锁")
    try expect(result.suggestion?.kind == .highRiskApp, "应优先给出高风险转换建议")
    try expect(result.insights.first(where: { $0.id == "transition" })?.value == "Codex → 微信", "未识别高风险转换")
    try expect(result.insights.first(where: { $0.id == "distraction-minute" })?.value == "第 5 分钟", "偏离时点中位数错误")
    try expect(result.insights.first(where: { $0.id == "return-latency" })?.value == "30 秒", "返回耗时错误")
    try expect(result.insights.first(where: { $0.id == "best-duration" })?.value == "15 分钟", "最佳训练长度错误")
    try expect(result.insights.first(where: { $0.id == "necessary-app" })?.value == "Safari", "必要应用统计错误")
}

suite.run("每日教练先校验数据质量再给行为建议") {
    let calendar = utcCalendar()
    let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 9))!
    let task = UUID()
    let app = AppIdentity(bundleID: "app", name: "App")
    let snapshot = FocusTraceLocalSnapshot(
        activities: [
            ActivityRecord(app: app, startedAt: day, endedAt: day.addingTimeInterval(30 * 60), taskID: task, focusSessionID: nil, classification: .allowed),
            ActivityRecord(app: app, startedAt: day.addingTimeInterval(30 * 60), endedAt: day.addingTimeInterval(60 * 60), taskID: nil, focusSessionID: nil, classification: .allowed)
        ],
        trainingPlans: [TrainingPlanRecord(version: 1, focusMinutes: 15, reason: "default")]
    )
    let result = DailyCoachEngine.analyze(
        snapshot: snapshot,
        reportDate: day,
        generatedAt: day.addingTimeInterval(60 * 60),
        calendar: calendar
    )
    try expect(result.metrics.attributedRatio == 0.5, "归因率应为 50%")
    try expect(!result.quality.isReliableForBehavior, "低归因率不得生成可靠行为结论")
    try expect(result.recommendation.kind == .repairAttribution, "应先建议修复桌面绑定")
}

suite.run("每日教练把极密 Space 信号视为采集风险") {
    let calendar = utcCalendar()
    let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 9))!
    let task = UUID()
    let app = AppIdentity(bundleID: "app", name: "App")
    let intervals = (0..<31).map { index in
        TaskIntervalRecord(
            taskID: task,
            startedAt: day.addingTimeInterval(Double(index * 120)),
            endedAt: day.addingTimeInterval(Double((index + 1) * 120)),
            workflowSource: .space
        )
    }
    let snapshot = FocusTraceLocalSnapshot(
        taskIntervals: intervals,
        activities: [ActivityRecord(app: app, startedAt: day, endedAt: day.addingTimeInterval(60 * 60), taskID: task, focusSessionID: nil, classification: .allowed)],
        trainingPlans: [TrainingPlanRecord(version: 1, focusMinutes: 15, reason: "default")]
    )
    let result = DailyCoachEngine.analyze(
        snapshot: snapshot,
        reportDate: day,
        generatedAt: day.addingTimeInterval(60 * 60),
        calendar: calendar
    )
    try expect(!result.quality.isReliableForBehavior, "极密 Space 信号不得用于行为判断")
    try expect(result.quality.warnings.contains { $0.contains("Space 识别噪声") }, "应给出 Space 数据质量警告")
    try expect(result.recommendation.kind == .verifySpaceTracking, "应先建议校准 Space 记录")
}

suite.run("每日教练执行训练并在下一工作日验证结果") {
    let calendar = utcCalendar()
    let firstDay = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 9))!
    let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!
    let task = UUID()
    let app = AppIdentity(bundleID: "app", name: "App")
    let session = FocusSessionRecord(
        taskID: task,
        startedAt: secondDay.addingTimeInterval(10 * 60),
        endedAt: secondDay.addingTimeInterval(25 * 60),
        targetSeconds: 15 * 60,
        outcome: .completed,
        difficulty: 2,
        confirmedDistractionCount: 0
    )
    let snapshot = FocusTraceLocalSnapshot(
        activities: [
            ActivityRecord(app: app, startedAt: firstDay, endedAt: firstDay.addingTimeInterval(60 * 60), taskID: task, focusSessionID: nil, classification: .allowed),
            ActivityRecord(app: app, startedAt: secondDay, endedAt: secondDay.addingTimeInterval(60 * 60), taskID: task, focusSessionID: session.id, classification: .allowed)
        ],
        focusSessions: [session],
        trainingPlans: [TrainingPlanRecord(version: 1, focusMinutes: 15, reason: "default")]
    )
    let result = DailyCoachEngine.analyze(
        snapshot: snapshot,
        reportDate: secondDay,
        generatedAt: secondDay.addingTimeInterval(60 * 60),
        calendar: calendar
    )
    try expect(result.previousRecommendationEvaluation?.status == .improved, "成功训练应闭环为已改善")
    try expect(result.previousRecommendationEvaluation?.evidence.contains("1/1") == true, "验证证据应包含训练结果")
}

suite.run("每日教练验证实际发出的建议而不是事后重算") {
    let calendar = utcCalendar()
    let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 9))!
    let task = UUID()
    let app = AppIdentity(bundleID: "app", name: "App")
    let issued = DailyCoachRecommendation(
        kind: .repairAttribution,
        title: "fix attribution",
        rationale: "test",
        evidence: [],
        confidence: .high,
        action: .bindWorkflow,
        method: DailyTrainingMethod(title: "bind", steps: ["bind"], successMeasure: "70%")
    )
    let previousMetrics = DailyNormalizedMetrics(
        recordedMinutes: 60,
        attributedMinutes: 30,
        attributedRatio: 0.5,
        appSwitchesPerHour: 10,
        workflowSwitchesPerHour: 2,
        medianFocusMinutes: nil,
        trainingCount: 0,
        successfulTrainingCount: 0,
        feedbackCompletionRatio: nil,
        parkingCount: 0
    )
    let snapshot = FocusTraceLocalSnapshot(
        activities: [ActivityRecord(app: app, startedAt: day, endedAt: day.addingTimeInterval(60 * 60), taskID: task, focusSessionID: nil, classification: .allowed)],
        trainingPlans: [TrainingPlanRecord(version: 1, focusMinutes: 15, reason: "default")]
    )
    let result = DailyCoachEngine.analyze(
        snapshot: snapshot,
        reportDate: day,
        generatedAt: day.addingTimeInterval(60 * 60),
        calendar: calendar,
        previousIssuedRecommendation: issued,
        previousIssuedMetrics: previousMetrics
    )
    try expect(result.previousRecommendationEvaluation?.status == .improved, "工作流归因恢复应验证为已改善")
    try expect(result.previousRecommendationEvaluation?.title.contains("归因") == true, "应评价实际发出的归因建议")
}

suite.run("每日教练不把切换次数本身判为恢复失败") {
    let calendar = utcCalendar()
    let day = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 28, hour: 9)
    )!
    let task = UUID()
    let session = FocusSessionRecord(
        taskID: task,
        startedAt: day,
        endedAt: day.addingTimeInterval(15 * 60),
        targetSeconds: 15 * 60,
        outcome: .completed,
        difficulty: 2,
        confirmedDistractionCount: 0
    )
    var intervals: [TaskIntervalRecord] = []
    for index in 0..<8 {
        intervals.append(
            TaskIntervalRecord(
                taskID: task,
                startedAt: day.addingTimeInterval(Double(index) * 7 * 60),
                endedAt: day.addingTimeInterval(Double(index + 1) * 7 * 60),
                workflowSource: .space
            )
        )
    }
    let result = DailyCoachEngine.analyze(
        snapshot: FocusTraceLocalSnapshot(
            taskIntervals: intervals,
            activities: [
                ActivityRecord(
                    app: AppIdentity(bundleID: "app", name: "App"),
                    startedAt: day,
                    endedAt: day.addingTimeInterval(60 * 60),
                    taskID: task,
                    focusSessionID: session.id,
                    classification: .allowed
                )
            ],
            focusSessions: [session],
            trainingPlans: [
                TrainingPlanRecord(
                    version: 1,
                    focusMinutes: 15,
                    reason: "default"
                )
            ]
        ),
        reportDate: day,
        generatedAt: day.addingTimeInterval(60 * 60),
        calendar: calendar
    )
    try expect(result.quality.isReliableForBehavior, "普通切换密度不应触发数据质量阻塞")
    try expect(result.metrics.workflowSwitchesPerHour >= 6, "反例必须包含较多工作流切换")
    try expect(
        result.recommendation.kind != .agentParkingDrill,
        "没有显式交接原因时不得仅凭切换次数建议返回点训练"
    )
}

suite.run("返回点建议要求重复的显式等待或中断") {
    let calendar = utcCalendar()
    let day = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 28, hour: 9)
    )!
    let workflowA = UUID()
    let workflowB = UUID()
    let endpointA = WorkflowTransitionEndpoint(
        kind: .workflow,
        workflowID: workflowA
    )
    let endpointB = WorkflowTransitionEndpoint(
        kind: .workflow,
        workflowID: workflowB
    )
    let transition: (Date, WorkflowTransitionEndpoint, WorkflowTransitionEndpoint, SpaceSwitchReason) -> WorkflowTransitionRecord = {
        date, origin, destination, reason in
        WorkflowTransitionRecord(
            navigationStartedAt: date.addingTimeInterval(-2),
            settledAt: date.addingTimeInterval(-0.5),
            resolvedAt: date,
            origin: origin,
            destination: destination,
            outcome: .confirmed,
            reason: reason,
            navigationEventCount: 1
        )
    }
    let session = FocusSessionRecord(
        taskID: workflowA,
        startedAt: day,
        endedAt: day.addingTimeInterval(15 * 60),
        targetSeconds: 15 * 60,
        outcome: .completed,
        difficulty: 2,
        confirmedDistractionCount: 0
    )
    let result = DailyCoachEngine.analyze(
        snapshot: FocusTraceLocalSnapshot(
            activities: [
                ActivityRecord(
                    app: AppIdentity(bundleID: "app", name: "App"),
                    startedAt: day,
                    endedAt: day.addingTimeInterval(60 * 60),
                    taskID: workflowA,
                    focusSessionID: session.id,
                    classification: .allowed
                )
            ],
            focusSessions: [session],
            trainingPlans: [
                TrainingPlanRecord(
                    version: 1,
                    focusMinutes: 15,
                    reason: "default"
                )
            ],
            workflowTransitions: [
                transition(
                    day.addingTimeInterval(20 * 60),
                    endpointA,
                    endpointB,
                    .waitingForResult
                ),
                transition(
                    day.addingTimeInterval(40 * 60),
                    endpointB,
                    endpointA,
                    .forcedInterruption
                )
            ]
        ),
        reportDate: day,
        generatedAt: day.addingTimeInterval(60 * 60),
        calendar: calendar
    )
    try expect(
        result.recommendation.kind == .agentParkingDrill,
        "两次显式交接且没有返回点时才应建议返回点训练"
    )
    try expect(
        result.recommendation.evidence.contains(
            "等待结果 1 次，被迫中断 1 次"
        ),
        "建议必须引用显式原因而不是切换率"
    )
}

suite.run("工作流跳转审计只分析最终路线并保留原因与标题上下文") {
    let calendar = utcCalendar()
    let day = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 27)
    )!
    let workflowA = UUID()
    let workflowB = UUID()
    let at: (Int, Int) -> Date = { hour, minute in
        day.addingTimeInterval(Double(hour * 3_600 + minute * 60))
    }
    let result = WorkflowTransitionAuditEngine.makeAudit(
        tasks: [
            TaskRecord(id: workflowA, title: "主召回\n性能优化"),
            TaskRecord(id: workflowB, title: "Codex 对话")
        ],
        requirements: [
            RequirementRecord(
                title: "修复\n召回耗时",
                source: "PRIVATE_REQUIREMENT_SOURCE",
                capturedAt: at(7, 0),
                status: .planned,
                workflowID: workflowA
            )
        ],
        taskIntervals: [
            TaskIntervalRecord(taskID: workflowA, startedAt: at(9, 0), endedAt: at(9, 10), workflowSource: .manual),
            TaskIntervalRecord(taskID: workflowB, startedAt: at(9, 10), endedAt: at(9, 14), workflowSource: .space),
            TaskIntervalRecord(taskID: workflowA, startedAt: at(9, 14), endedAt: at(9, 30), workflowSource: .space),
            TaskIntervalRecord(taskID: workflowB, startedAt: at(10, 0), endedAt: at(10, 20), workflowSource: .space)
        ],
        activities: [
            ActivityRecord(app: AppIdentity(bundleID: "a", name: "A"), startedAt: at(9, 0), endedAt: at(9, 10), taskID: workflowA, focusSessionID: nil, classification: .allowed),
            ActivityRecord(app: AppIdentity(bundleID: "b", name: "B"), startedAt: at(9, 10), endedAt: at(9, 14), taskID: workflowB, focusSessionID: nil, classification: .allowed),
            ActivityRecord(app: AppIdentity(bundleID: "a", name: "A"), startedAt: at(9, 14), endedAt: at(9, 30), taskID: workflowA, focusSessionID: nil, classification: .allowed),
            ActivityRecord(app: AppIdentity(bundleID: "b", name: "B"), startedAt: at(10, 0), endedAt: at(10, 20), taskID: workflowB, focusSessionID: nil, classification: .allowed)
        ],
        markers: [
            TimelineMarkerRecord(date: at(9, 10), kind: .spaceSwitchUnstructured, taskID: workflowA),
            TimelineMarkerRecord(date: at(9, 14), kind: .spaceSwitchCheckpoint, taskID: workflowB),
            TimelineMarkerRecord(date: at(10, 0), kind: .spaceSwitchInterrupted, taskID: workflowA)
        ],
        range: day..<day.addingTimeInterval(24 * 3_600),
        now: at(18, 0),
        calendar: calendar
    )
    guard let route = result.audit.routes.first(where: {
        $0.fromWorkflow == "主召回 性能优化" && $0.toWorkflow == "Codex 对话"
    }) else {
        throw VerificationFailure(message: "缺少主召回到 Codex 的最终路线")
    }
    try expect(route.count == 2, "相同最终路线应聚合为两次")
    try expect(route.reasonCounts["unstructured"] == 1, "应保留无计划原因")
    try expect(route.reasonCounts["forcedInterruption"] == 1, "应保留被迫打断原因")
    try expect(route.medianDestinationMinutes == 12, "应计算目的工作流停留中位数")
    try expect(route.returnedWithin30Minutes == 1, "应统计三十分钟内返回结果")
    try expect(
        result.contexts.first(where: {
            $0.workflowTitle == "主召回 性能优化"
        })?.openRequirementTitles == ["修复 召回耗时"],
        "提示词只应获得清洗后的有限需求标题"
    )
    try expect(
        result.contexts.first(where: {
            $0.workflowTitle == "主召回 性能优化"
        })?.activeMinutes == 26,
        "工作流时长必须来自互斥的前台活动，不能累加重叠区间"
    )
}

suite.run("工作流跳转协议优先使用原生语义并去重旧标记") {
    let calendar = utcCalendar()
    let day = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 28)
    )!
    let workflowA = UUID()
    let workflowB = UUID()
    let switchedAt = day.addingTimeInterval(9 * 3_600)
    let cancelledAt = day.addingTimeInterval(10 * 3_600)
    let transition = WorkflowTransitionRecord(
        navigationStartedAt: switchedAt.addingTimeInterval(-2),
        settledAt: switchedAt.addingTimeInterval(-0.5),
        resolvedAt: switchedAt,
        origin: WorkflowTransitionEndpoint(
            resolution: .bound(workflowID: workflowA)
        ),
        destination: WorkflowTransitionEndpoint(
            resolution: .bound(workflowID: workflowB)
        ),
        outcome: .confirmed,
        reason: .waitingForResult,
        navigationEventCount: 3
    )
    let cancelled = WorkflowTransitionRecord(
        navigationStartedAt: cancelledAt.addingTimeInterval(-2),
        settledAt: cancelledAt,
        resolvedAt: cancelledAt,
        origin: WorkflowTransitionEndpoint(
            resolution: .bound(workflowID: workflowA)
        ),
        destination: WorkflowTransitionEndpoint(
            resolution: .bound(workflowID: workflowA)
        ),
        outcome: .cancelled,
        reason: nil,
        navigationEventCount: 2
    )
    let result = WorkflowTransitionAuditEngine.makeAudit(
        tasks: [
            TaskRecord(id: workflowA, title: "等待 Agent"),
            TaskRecord(id: workflowB, title: "处理需求")
        ],
        requirements: [],
        taskIntervals: [
            TaskIntervalRecord(
                taskID: workflowB,
                startedAt: switchedAt,
                endedAt: switchedAt.addingTimeInterval(12 * 60),
                workflowSource: .space
            )
        ],
        markers: [
            // Compatibility marker for the same native event must not double
            // count the route.
            TimelineMarkerRecord(
                date: switchedAt,
                kind: .spaceSwitchWaiting,
                taskID: workflowA
            )
        ],
        workflowTransitions: [transition, cancelled],
        range: day..<day.addingTimeInterval(24 * 3_600),
        now: day.addingTimeInterval(18 * 3_600),
        calendar: calendar
    )

    try expect(result.audit.protocolVersion == 2, "跳转聚合必须声明干预审计协议版本")
    try expect(result.audit.dataSource == "semanticEvents", "原生记录存在时必须声明语义数据来源")
    try expect(result.audit.finalSwitches == 1, "同一语义记录和兼容标记不得重复计数")
    try expect(result.audit.explicitReasonSwitches == 1, "主动原因必须单独统计")
    try expect(result.audit.cancelledNavigations == 1, "回到起点只应记为取消导航")
    try expect(result.audit.routes.first?.count == 1, "最终路线必须保持单一分析单位")
    try expect(result.audit.routes.first?.outcomeCounts?["confirmed"] == 1, "路线应暴露可验证结果")
}

suite.run("工作流跳转超时不臆测用户意图") {
    let calendar = utcCalendar()
    let day = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 28)
    )!
    let workflowA = UUID()
    let workflowB = UUID()
    let switchedAt = day.addingTimeInterval(9 * 3_600)
    let report = AutomationReportEngine.makeReport(
        snapshot: FocusTraceLocalSnapshot(
            tasks: [
                TaskRecord(id: workflowA, title: "工作流 A"),
                TaskRecord(id: workflowB, title: "工作流 B")
            ],
            taskIntervals: [
                TaskIntervalRecord(
                    taskID: workflowB,
                    startedAt: switchedAt,
                    endedAt: switchedAt.addingTimeInterval(10 * 60),
                    workflowSource: .space
                )
            ],
            activities: [
                ActivityRecord(
                    app: AppIdentity(bundleID: "app", name: "App"),
                    startedAt: switchedAt,
                    endedAt: switchedAt.addingTimeInterval(10 * 60),
                    taskID: workflowB,
                    focusSessionID: nil,
                    classification: .allowed
                )
            ],
            workflowTransitions: [
                WorkflowTransitionRecord(
                    navigationStartedAt: switchedAt.addingTimeInterval(-2),
                    settledAt: switchedAt.addingTimeInterval(-0.5),
                    resolvedAt: switchedAt,
                    origin: WorkflowTransitionEndpoint(
                        kind: .workflow,
                        workflowID: workflowA
                    ),
                    destination: WorkflowTransitionEndpoint(
                        kind: .workflow,
                        workflowID: workflowB
                    ),
                    outcome: .timedOut,
                    reason: .unstructured,
                    interventionTrigger: .frequentSwitchBurst,
                    navigationEventCount: 1
                )
            ]
        ),
        reportDate: day,
        generatedAt: day.addingTimeInterval(18 * 3_600),
        calendar: calendar
    )
    let markdown = AutomationReportEngine.markdown(
        for: report,
        timeZone: calendar.timeZone
    )
    try expect(
        markdown.contains("主动说明 / 超时 / 自动：0 / 1 / 0 次"),
        "超时必须和主动说明分开"
    )
    try expect(
        markdown.contains("原因 未说明 1")
            && !markdown.contains("无明确计划")
            && !markdown.contains("已说明原因的最终跳转"),
        "超时只能表达未说明，不能臆测用户没有计划"
    )
}

suite.run("工作流跳转审计在固定大样本下不超过性能预算") {
    let calendar = utcCalendar()
    let day = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 27)
    )!
    let workflowA = UUID()
    let workflowB = UUID()
    let tasks = [
        TaskRecord(id: workflowA, title: "工作流 A"),
        TaskRecord(id: workflowB, title: "工作流 B")
    ]
    let intervals = (0..<2_000).map { index in
        let start = day.addingTimeInterval(Double(index * 10 + 1))
        return TaskIntervalRecord(
            taskID: index.isMultiple(of: 2) ? workflowA : workflowB,
            startedAt: start,
            endedAt: start.addingTimeInterval(8),
            workflowSource: .space
        )
    }
    let markers = intervals.enumerated().map { index, interval in
        TimelineMarkerRecord(
            date: interval.startedAt,
            kind: index.isMultiple(of: 3)
                ? .spaceSwitchUnstructured
                : .spaceSwitchWaiting,
            taskID: index.isMultiple(of: 2) ? workflowB : workflowA
        )
    }
    let requirements = (0..<1_000).map {
        RequirementRecord(
            title: "需求 \($0)",
            capturedAt: day.addingTimeInterval(Double($0)),
            status: .planned,
            workflowID: $0.isMultiple(of: 2) ? workflowA : workflowB
        )
    }
    let startedAt = Date()
    let result = WorkflowTransitionAuditEngine.makeAudit(
        tasks: tasks,
        requirements: requirements,
        taskIntervals: intervals,
        markers: markers,
        range: day..<day.addingTimeInterval(24 * 3_600),
        now: day.addingTimeInterval(24 * 3_600),
        calendar: calendar
    )
    let elapsed = Date().timeIntervalSince(startedAt)

    try expect(result.audit.reasonedSwitches == 2_000, "大样本不得漏掉理由事件")
    try expect(result.audit.unreasonedSwitches == 0, "匹配的最终区间不应变成未说明跳转")
    try expect(elapsed < 1, "两千区间、两千标记与一千需求应在一秒内完成，实测 \(elapsed) 秒")
}

suite.run("Codex 日报只暴露聚合结果") {
    let fixture = phaseTwoFixture()
    let report = AutomationReportEngine.makeReport(
        snapshot: fixture.snapshot,
        reportDate: fixture.lastDay,
        generatedAt: fixture.lastDay.addingTimeInterval(9 * 60 * 60),
        calendar: fixture.calendar
    )
    let markdown = AutomationReportEngine.markdown(for: report, timeZone: fixture.calendar.timeZone)
    try expect(markdown.contains("状态：已解锁"), "日报应显示阶段 2 状态")
    try expect(markdown.contains("Codex → 微信"), "日报应包含聚合模式")
    try expect(markdown.contains("本周单项建议"), "日报应限制为单项建议")
    try expect(markdown.contains("保存返回点 / 已返回：2 / 1 次"), "日报应包含返回点聚合指标")
    try expect(!markdown.contains("PRIVATE_RESUME_CUE"), "日报不应暴露恢复线索")
    try expect(!markdown.contains("com.openai.codex"), "日报不应泄露 Bundle ID")
    try expect(!markdown.contains(fixture.snapshot.activities[0].id.uuidString), "日报不应泄露原始事件 ID")
    let json = try AutomationReportEngine.jsonData(for: report)
    let jsonText = String(decoding: json, as: UTF8.self)
    try expect(jsonText.contains("\"schemaVersion\" : 5"), "结构化日报应包含协议版本")
    try expect(
        jsonText.contains("\"reportCivilDate\" : \"2026-06-10\""),
        "结构化日报必须显式保留用户所选民用日期"
    )
    try expect(jsonText.contains("\"recommendation\""), "结构化日报应包含单项训练")
    try expect(
        jsonText.contains("\"observationPlan\"")
            && jsonText.contains("\"minimalEventDrivenFixed\""),
        "结构化日报应声明动态分析配置与固定采集边界"
    )
    try expect(!jsonText.contains("PRIVATE_RESUME_CUE"), "结构化日报不应暴露恢复线索")
    try expect(!jsonText.contains("com.openai.codex"), "结构化日报不应泄露 Bundle ID")
}

suite.run("Codex 写回是问题到行动的短决策") {
    let review = CodexReviewArtifact(
        sourceReportID: "focustrace-report",
        reportDate: Date(timeIntervalSince1970: 100),
        generatedAt: Date(timeIntervalSince1970: 200),
        status: .behaviorFinding,
        problem: "今天没有形成带结果反馈的训练样本。",
        recommendation: "开始工作前写下唯一产出，完成一轮 15 分钟训练并记录难度。",
        evidence: ["今日训练 0 次"],
        nextCheck: "今天结束前检查训练完成数是否达到 1。"
    )
    try expect(review.hasValidShape, "一条强证据的短决策应通过")
    try expect(
        review.isConsistentWithBehaviorReliability(true),
        "可靠数据应只接受行为问题"
    )
    try expect(
        !review.isConsistentWithBehaviorReliability(false),
        "不可靠数据不能接受行为问题"
    )

    let repeated = CodexReviewArtifact(
        sourceReportID: review.sourceReportID,
        reportDate: review.reportDate,
        generatedAt: review.generatedAt,
        status: .behaviorFinding,
        problem: review.displayedProblem,
        recommendation: review.recommendation,
        evidence: ["今日训练 0 次", "今日训练0次"],
        nextCheck: review.nextCheck
    )
    try expect(!repeated.hasValidShape, "重复证据不应通过写回形状校验")
}

suite.run("Codex 旧写回只保留可行动部分") {
    let json = """
    {
      "schemaVersion": 1,
      "sourceReportID": "legacy-report",
      "reportDate": "1970-01-01T00:01:40Z",
      "generatedAt": "1970-01-01T00:03:20Z",
      "headline": "工作流归因不足，当前不能据此判断注意力。",
      "interpretation": "旧协议生成的解释段落不再进入主要展示。",
      "recommendation": "先校准当前桌面的工作流绑定。",
      "evidence": ["工作流归因率 68%", "可靠门槛 70%"],
      "nextCheck": "下一工作日检查归因率是否达到 70%。"
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let review = try decoder.decode(CodexReviewArtifact.self, from: Data(json.utf8))
    try expect(review.hasValidShape, "已有 v1 写回必须继续可读")
    try expect(
        review.displayedProblem == "工作流归因不足，当前不能据此判断注意力。",
        "旧协议的冗长解释不应进入问题展示"
    )
    try expect(review.displayedStatus == .dataQualityBlocked, "旧版数据阻塞应保留语义")
}

suite.run("Codex 一键接入使用官方深链和聚合工作区") {
    let workspace = URL(
        fileURLWithPath: "/Users/example/Library/Application Support/FocusTrace/CodexWorkspace",
        isDirectory: true
    )
    guard let url = CodexWorkspaceContract.deepLink(workspaceURL: workspace),
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        throw VerificationFailure(message: "无法生成 Codex 接入深链")
    }
    let query = Dictionary(
        uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        }
    )
    try expect(components.scheme == "codex", "接入应使用 Codex 官方 URL scheme")
    try expect(components.host == "threads" && components.path == "/new", "接入应打开新本地任务")
    try expect(query["path"] == workspace.standardizedFileURL.path, "接入应绑定生成的本地工作区")
    try expect(query["prompt"] == CodexWorkspaceContract.setupPrompt, "接入提示词应完整预填")
    try expect(
        CodexWorkspaceContract.agentsInstructions.contains(
            "Never read or expose FocusTrace `store.json`"
        ),
        "工作区必须固定原始数据禁读边界"
    )
    try expect(
        CodexWorkspaceContract.agentsInstructions.contains(
            "Read only `Reports/latest.json` and `Reports/latest.md`"
        ),
        "工作区必须限制为聚合报告"
    )
    for contract in [
        "当前最重要的问题是什么？",
        "今天具体怎么解决？",
        "\"schemaVersion\": 3",
        "当前不能据此判断注意力",
        "at most 360 characters",
        "Do not add a preface",
        "`transitionAudit.routes`",
        "`observationPlan.source`",
        "`openRequirementTitles`",
        "untrusted data label",
        "Do not infer a problem from a switch count",
        "semantic title similarity is only a hypothesis",
        "\"analysisAudit\"",
        "at least twice"
    ] {
        try expect(
            CodexWorkspaceContract.agentsInstructions.contains(contract),
            "工作区缺少短决策约束：\(contract)"
        )
    }
    try expect(
        !CodexWorkspaceContract.agentsInstructions.contains("\"interpretation\""),
        "新写回协议不应继续要求解释段落"
    )
    let launcherSource = try String(
        contentsOf: URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent(
            "Sources/FocusTrace/CodexConnectionLauncher.swift"
        ),
        encoding: .utf8
    )
    guard let refreshStart = launcherSource.range(
        of: "func refreshExistingWorkspaceIfPresent() throws"
    )?.lowerBound,
          let refreshEnd = launcherSource.range(
            of: "private func write(",
            range: refreshStart..<launcherSource.endIndex
          )?.lowerBound else {
        throw VerificationFailure(message: "无法定位 Codex 工作区刷新实现")
    }
    let refreshImplementation = launcherSource[refreshStart..<refreshEnd]
    try expect(
        refreshImplementation.contains("CodexWorkspaceContract.reportScript")
            && refreshImplementation.contains("named: \"FocusTraceReport\"")
            && refreshImplementation.contains("install-codex-review"),
        "已有 Codex 工作区必须同时刷新报告工具、生成脚本和写回校验器"
    )
    let reportCommand = try repositoryFileContents(
        "Sources/FocusTraceReport/main.swift"
    )
    let validator = try repositoryFileContents(
        "Scripts/install-codex-review.py"
    )
    let codexBridge = try repositoryFileContents(
        "Sources/FocusTrace/CodexReviewBridge.swift"
    )
    try expect(
        reportCommand.contains("(2...5).contains(report.schemaVersion)")
            && validator.contains("{2, 3, 4, 5}")
            && codexBridge.contains("(2...5).contains(report.schemaVersion)")
            && codexBridge.contains("review.isGrounded(in: report)"),
        "当前 v5 聚合报告必须参与上一项建议验证、保留民用日期、通过写回校验并在 App 中展示"
    )
}

suite.run("状态栏品牌图标是非空的原生模板图") {
    let idle = FocusTraceMenuBarIcon.image(isFocusing: false)
    let focusing = FocusTraceMenuBarIcon.image(isFocusing: true)
    try expect(idle.isTemplate && focusing.isTemplate, "状态栏图标必须交给 macOS 模板着色")
    try expect(
        idle.size.width == 18 && idle.size.height == 16,
        "状态栏图标尺寸应保持紧凑"
    )
    guard let idleData = idle.tiffRepresentation,
          let focusingData = focusing.tiffRepresentation else {
        throw VerificationFailure(message: "状态栏模板图为空")
    }
    try expect(idleData.count > 100 && focusingData.count > 100, "状态栏模板图必须包含实际像素")
    try expect(idleData != focusingData, "专注状态应有可区分的图标")
}

suite.run("本地 store.json 兼容解码") {
    let taskID = UUID()
    let activityID = UUID()
    let planID = UUID()
    let json = """
    {
      "activities": [{
        "id": "\(activityID.uuidString)",
        "appName": "Terminal",
        "bundleID": "com.apple.Terminal",
        "startedAt": "2026-06-01T09:00:00Z",
        "endedAt": "2026-06-01T09:01:00Z",
        "taskID": "\(taskID.uuidString)",
        "focusSessionID": null,
        "classificationRaw": "allowed",
        "sourceRaw": "appActivation",
        "isAllowedApp": true,
        "crossedReminderThreshold": false
      }],
      "taskIntervals": [],
      "focusSessions": [],
      "interruptions": [],
      "trainingPlans": [{
        "id": "\(planID.uuidString)",
        "version": 1,
        "effectiveAt": "2026-06-01T09:00:00Z",
        "focusMinutes": 15,
        "sessionsPerDay": 2,
        "breakMinutes": 5,
        "reminderThresholdSeconds": 20,
        "reason": "default",
        "previousPlanID": null
      }],
      "tasks": [],
      "markers": []
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(FocusTraceLocalSnapshot.self, from: Data(json.utf8))
    try expect(snapshot.activities.count == 1, "活动片段未解码")
    try expect(snapshot.activities[0].app.name == "Terminal", "应用名未解码")
    try expect(snapshot.currentPlan.focusMinutes == 15, "训练计划未解码")
    try expect(snapshot.taskParkings.isEmpty, "旧 store.json 缺少新字段时应默认为空")
}

suite.run("CSV 转义且不添加敏感字段") {
    let start = Date(timeIntervalSince1970: 100)
    let record = ActivityRecord(
        app: AppIdentity(bundleID: "com.example.app", name: "App, \"Work\""),
        startedAt: start,
        endedAt: start.addingTimeInterval(5),
        taskID: UUID(),
        focusSessionID: nil,
        classification: .allowed
    )
    let csv = ExportEngine.activitiesCSV([record])
    try expect(csv.contains("\"App, \"\"Work\"\"\""), "CSV 引号转义错误")
    try expect(!csv.contains("window_title"), "CSV 不应含窗口标题")
    try expect(!csv.contains("url"), "CSV 不应含 URL")
}

suite.run("JSON 导出可往返") {
    let bundle = ExportBundle(
        tasks: [TaskRecord(title: "Task")],
        taskIntervals: [],
        activities: [],
        focusSessions: [],
        interruptions: [],
        trainingPlans: [],
        markers: []
    )
    let data = try ExportEngine.jsonData(bundle)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(ExportBundle.self, from: data)
    try expect(decoded.tasks.first?.title == "Task", "JSON 往返失败")
    try expect(decoded.taskParkings.isEmpty, "空停车数组往返失败")
}

suite.run("需求保持两态且工作流列表没有重复动作") {
    let root = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
    func contents(_ path: String) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }
    let requirementsView = try contents(
        "Sources/FocusTrace/Views/RequirementsView.swift"
    )
    try expect(
        requirementsView.contains("Button(\"处理\")")
            && requirementsView.contains("Button(\"不处理\""),
        "未完成需求必须把处理和不处理作为两个显式日常决策"
    )
    try expect(
        requirementsView.contains("Button(\"完成需求\")"),
        "正在处理的需求必须能独立完成"
    )
    try expect(
        !requirementsView.contains("Button(\"开始处理\")")
            && !requirementsView.contains("Button(\"在当前工作流处理\")"),
        "需求卡片不能重新暴露内部规划状态分支"
    )
    try expect(
        requirementsView.contains("调整时间、重要程度与工作流…"),
        "时间、重要程度和归属必须保留在次级详情路径"
    )
    try expect(
        requirementsView.contains("FocusTraceCompactDatePicker(")
            && !requirementsView.contains(".datePickerStyle(.graphical)"),
        "需求截止日期必须使用紧凑 FocusTrace 日历弹层，不能恢复系统内嵌大日历"
    )

    let focusView = try contents(
        "Sources/FocusTrace/Views/FocusTrainingView.swift"
    )
    try expect(
        !focusView.contains("绑定此桌面")
            && !focusView.contains("workflowToDelete"),
        "工作流整行已经负责绑定，列表不能再展示重复绑定或删除动作"
    )
    try expect(
        focusView.contains("Button(\"编辑\")")
            && focusView.contains("Label(\"完成\", systemImage: \"checkmark.circle\")"),
        "进行中工作流列表右侧只保留编辑和完成"
    )

    let taskEditor = try contents(
        "Sources/FocusTrace/Views/TaskEditor.swift"
    )
    try expect(
        taskEditor.contains("Button(\"删除工作流…\", role: .destructive)")
            && taskEditor.contains("历史时间轴和训练记录会保留"),
        "删除必须收进编辑页并保留影响说明与二次确认"
    )

    let state = try contents("Sources/FocusTrace/ApplicationState.swift")
    try expect(
        state.contains("func workflowNameValidationMessage(")
            && state.contains("func deleteWorkflow("),
        "所有创建路径必须共用名称校验，工作流删除必须由状态层负责"
    )
}

suite.run("README 首页保持面向用户且技术细节折叠") {
    let readmeURL = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    ).appendingPathComponent("README.md")
    let readme = try String(contentsOf: readmeURL, encoding: .utf8)
    for heading in ["## 安装", "## 30 秒上手", "## 重要特性", "## 高级特性"] {
        try expect(readme.contains(heading), "README 缺少用户入口：\(heading)")
    }
    try expect(
        readme.components(separatedBy: "<details>").count >= 4,
        "技术与进阶说明应折叠，避免压过用户主路径"
    )
    try expect(
        !readme.contains("## 发布与自动更新"),
        "README 用户首页不应展开发布和更新实现"
    )
    try expect(
        readme.range(of: "## 安装")!.lowerBound
            < readme.range(of: "## 高级特性")!.lowerBound,
        "README 必须先讲安装与上手，再讲高级能力"
    )
    for productPillar in ["**看清**", "**不丢**", "**改善**"] {
        try expect(
            readme.contains(productPillar),
            "README 必须明确呈现三个核心注意力问题：\(productPillar)"
        )
    }
    for currentCapability in [
        "### 需求箱",
        "准备做时点击“处理”",
        "### Codex 每日行动复盘",
        "**当前问题**",
        "**今天怎么做**",
        "**如何验收**",
        "选择过去的日期，也可以重新查看已经写回的历史复盘"
    ] {
        try expect(
            readme.contains(currentCapability),
            "README 没有准确描述当前能力：\(currentCapability)"
        )
    }

    let reportScript = try String(
        contentsOf: URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent("Scripts/generate-daily-report.sh"),
        encoding: .utf8
    )
    try expect(
        reportScript.components(separatedBy: "\"$@\"").count == 3,
        "历史日报生成必须把日期参数同时传给预构建与 SwiftPM 两条路径"
    )
}

suite.run("产品纲领和质量门禁是仓库硬约束") {
    let root = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
    func contents(_ path: String) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    let doctrine = try contents("Docs/PRODUCT_DOCTRINE.md")
    for heading in [
        "## 三个核心问题",
        "### 问题门：是否解决真实问题",
        "### 边界门：是否知道自己不解决什么",
        "### 闭环门：流程是否能够自己完成",
        "## 需求与工作流的关系"
    ] {
        try expect(doctrine.contains(heading), "产品纲领缺少：\(heading)")
    }

    let quality = try contents("Docs/QUALITY_GATES.md")
    for contractID in [
        "CAP-01", "UX-03", "UX-04", "UX-05", "UX-06", "ATT-02", "REQ-01", "REQ-04", "FLOW-02",
        "SPACE-02", "DATA-02", "PRIV-01", "PERF-01", "PERF-04"
    ] {
        try expect(quality.contains(contractID), "质量基线缺少：\(contractID)")
    }

    let unitTests = try contents("Tests/FocusTraceCoreTests/FocusTraceCoreTests.swift")
    for evidence in [
        "activationClosesPreviousAndIgnoresDuplicate",
        "workflowConfirmationUsesUpperCenterWithoutPassiveOverlay",
        "observationPlanStartsBalancedAndReallocatesOnlyAnalysisAttention",
        "workflowInterventionPromptsOnlyOnThirdSwitchAndThenCoolsDown",
        "workflowInterventionIgnoresUnboundOrDisabledTransitions",
        "workflowInterventionAuditMeasuresPromptAndFollowingQuietWindow",
        "calendarPopoverAnchorPressesAlternateExactlyOnce",
        "disclosureButtonsExpandHitAreaWithoutChangingLayout",
        "requirementCalendarBoundsAllowFutureAndRespectEarliestDate",
        "requirementCaptureStaysInInboxUntilExplicitlyPlanned",
        "requirementPlanningSeparatesDeadlineImportanceAndWorkflow",
        "requirementCanStartWithoutPlanningAndCompletesIndependentlyInsideWorkflow",
        "deletingWorkflowDetachesOnlyItsUnfinishedRequirements",
        "workflowNamesAreUniqueAfterWhitespaceCaseAndWidthNormalization",
        "requirementQueueUsesUrgencyThenImportanceAndPreservesLegacyAmbiguity",
        "requirementDueReminderIsOneShotAndOnlyForPlannedOpenWork",
        "requirementQueueHandlesOneThousandItemsWithinBudget",
        "timelineSemanticPaletteSeparatesContextToolsAndRisk",
        "timelineCurrentWorkflowDoesNotUseDarkSegmentOutlines",
        "timelineCategoryColorsFollowRankAndCapAtFive",
        "timelineApplicationRunsMergeAdjacentDominantBuckets",
        "mainWindowContractRemainsSingleInstance",
        "spaceSwitchGateRequiresMeaningfulVerifiedDeparture",
        "spaceSwitchGateReturnsToOriginAndUpdatesDestinationSafely",
        "spaceSwitchGateRefreshesAFullDecisionWindowAfterNavigationSettles",
        "spaceSwitchGateExpiresWithoutLockingTheUser",
        "workflowTransitionKeepsCompleteNativeSemantics",
        "workflowTransitionAuditPrefersNativeSemanticsWithoutDoubleCountingMarkers",
        "timelinePresentationCacheInvalidatesOnlyForMeaningfulChanges",
        "dailyCoachRefusesBehaviorAdviceWhenWorkflowAttributionIsLow",
        "dailyCoachDoesNotTreatSwitchCountAloneAsRecoveryFailure",
        "dailyCoachRequiresRepeatedExplicitHandoffsBeforeParkingAdvice",
        "automationJSONIsStructuredAndAggregateOnly",
        "codexReviewDecisionBriefRemainsShortAndCompatible",
        "codexReviewV3RejectsUngroundedWorkflowSemantics",
        "codexReviewKeepsLegacyReadCompatibility",
        "codexWorkspaceDemandsProblemActionAndNoFiller",
        "dailyReportScriptPreservesDateArgumentsForHistoricalRegeneration"
    ] {
        try expect(
            unitTests.contains("func \(evidence)"),
            "质量基线引用的单元或回归证据不存在：\(evidence)"
        )
    }

    let pullRequestTemplate = try contents(".github/pull_request_template.md")
    for gate in ["用户问题", "边界与闭环", "质量证据", "契约变化"] {
        try expect(
            pullRequestTemplate.contains(gate),
            "Pull Request 模板缺少门禁：\(gate)"
        )
    }

    let ci = try contents(".github/workflows/ci.yml")
    try expect(ci.contains("pull_request:"), "持续集成必须覆盖 Pull Request")
    try expect(ci.contains("./Scripts/test.sh"), "持续集成必须运行完整质量门禁")

    let notificationRouter = try contents(
        "Sources/FocusTrace/NotificationRouter.swift"
    )
    try expect(
        notificationRouter.contains("打开 FocusTrace 查看最紧迫的一项。")
            && !notificationRouter.contains("firstTitle"),
        "需求到期通知不能在锁屏暴露需求标题"
    )

    let appScene = try contents("Sources/FocusTrace/FocusTraceApp.swift")
    try expect(
        appScene.contains("Window(\"FocusTrace\", id: FocusTraceWindowContract.mainWindowID)")
            && !appScene.contains("WindowGroup(")
            && !appScene.contains("Settings {")
            && appScene.contains("CommandGroup(replacing: .newItem)"),
        "FocusTrace 必须使用单实例主窗口并移除系统新建窗口入口"
    )

    let timelineView = try contents(
        "Sources/FocusTrace/Views/TimelineView.swift"
    )
    try expect(
        timelineView.contains("先看工作流，再看主应用，最后找高切换区间")
            && timelineView.contains("workflowLegendIDs")
            && timelineView.contains("applicationLegend")
            && timelineView.contains("TimelineApplicationRunEngine.runs")
            && timelineView.contains("segmentSeparator")
            && !timelineView.contains("StablePaletteAssignment.index")
            && !timelineView.contains("currentWorkflowStroke"),
        "时间轴必须合并主应用、使用统一浅色分隔并按排名使用参考色板"
    )

    let spaceSwitchGate = try contents(
        "Sources/FocusTraceMacSupport/SpaceSwitchGateController.swift"
    )
    let confirmationLayout = try contents(
        "Sources/FocusTraceMacSupport/FocusTraceConfirmationLayout.swift"
    )
    try expect(
        spaceSwitchGate.contains("误触或还没收尾？直接滑回原桌面。")
            && spaceSwitchGate.contains("确认工作流切换")
            && spaceSwitchGate.contains("阶段已到")
            && spaceSwitchGate.contains("等待结果")
            && spaceSwitchGate.contains("被迫中断")
            && spaceSwitchGate.contains("space-gate-reached-checkpoint")
            && spaceSwitchGate.contains("space-gate-waiting-for-result")
            && spaceSwitchGate.contains("space-gate-forced-interruption")
            && spaceSwitchGate.contains("panel.hasShadow = false")
            && spaceSwitchGate.contains("panel.ignoresMouseEvents = false")
            && spaceSwitchGate.contains("panel.level = .statusBar")
            && spaceSwitchGate.contains(
                "FocusTraceConfirmationLayout.frame"
            )
            && spaceSwitchGate.contains(".background(.ultraThinMaterial)")
            && spaceSwitchGate.contains("beginResolvingDestination")
            && spaceSwitchGate.contains("strokeBorder")
            && spaceSwitchGate.contains("separatorColor")
            && spaceSwitchGate.contains("hostingView.layer?.cornerCurve = .continuous")
            && spaceSwitchGate.contains("hostingView.layer?.masksToBounds = true")
            && !spaceSwitchGate.contains("accent.opacity(0.72)")
            && !spaceSwitchGate.contains("CGEventTap"),
        "切换门必须保持置顶、有边界、可操作、四角一致、无阴影、零手势监听并提供三种短理由"
    )
    try expect(
        confirmationLayout.contains(
            "visibleFrame.midX - size.width / 2"
        )
            && confirmationLayout.contains(
                "visibleFrame.maxY - size.height - topInset"
            )
            && !FileManager.default.fileExists(
                atPath: "Sources/FocusTrace/AttentionCueOverlayController.swift"
            ),
        "切换确认必须水平居中位于中上方，连续专注不得保留被动浮层"
    )
    let applicationState = try contents(
        "Sources/FocusTrace/ApplicationState.swift"
    )
    try expect(
        applicationState.contains("pendingSpaceSwitchJourney?.origin")
            && applicationState.contains("SpaceSwitchJourneyEngine.beginOrExtend")
            && applicationState.contains("SpaceSwitchJourneyEngine.settleDelaySeconds")
            && applicationState.contains("beginResolvingDestination")
            && applicationState.contains("PendingWorkflowTransition")
            && applicationState.contains("WorkflowTransitionModel")
            && applicationState.contains(
                "WorkflowSwitchInterventionEngine.decision"
            )
            && applicationState.contains("baselineComplete")
            && applicationState.contains("never open their own task interval.")
            && applicationState.contains("pendingSpaceSwitchJourney == nil"),
        "应用层必须把连续 Space 事件合并成一段导航并保留最初工作流"
    )
    let reviewView = try contents(
        "Sources/FocusTrace/Views/ReviewView.swift"
    )
    try expect(
        reviewView.contains("切换干预是否值得")
            && reviewView.contains("高频切换段")
            && reviewView.contains("确认后稳定")
            && reviewView.contains("今天重点观察")
            && reviewView.contains("不会抽样或丢弃原始时间轴"),
        "回顾必须解释确认为何出现、确认后的稳定性与动态分析来源"
    )
    try expect(
        !notificationRouter.contains("本轮专注目标已完成")
            && !applicationState.contains("sendTargetReached"),
        "连续专注和训练目标达成不得主动弹出奖励通知"
    )
    let spaceAcceptance = try contents(
        "Sources/FocusTraceSpaceAcceptance/main.swift"
    )
    let gateAcceptance = try contents(
        "Sources/FocusTraceGateAcceptance/main.swift"
    )
    try expect(
        spaceAcceptance.contains("SpaceSwitchGateController()")
            && spaceAcceptance.contains("showGateForAcceptance")
            && spaceAcceptance.contains("simulateReturnToOrigin")
            && spaceAcceptance.contains("runRealSpaceGateAcceptance")
            && spaceAcceptance.contains("NSWorkspace.activeSpaceDidChangeNotification")
            && spaceAcceptance.contains("SpaceSwitchJourneyEngine.beginOrExtend")
            && spaceAcceptance.contains("SpaceSwitchJourneyEngine.settleDelaySeconds")
            && spaceAcceptance.contains("10 秒超时已安全放行")
            && !spaceAcceptance.contains("SpaceSwitchGateOverlayView"),
        "隔离本机验收必须复用生产切换门，覆盖真实 Space 事件、按钮、超时和滑回取消"
    )
    try expect(
        gateAcceptance.contains("SpaceSwitchGateController()")
            && gateAcceptance.contains("gate-acceptance-result.json")
            && gateAcceptance.contains("SpaceSwitchReason.unstructured.rawValue")
            && !gateAcceptance.contains("SpaceSwitchGateOverlayView"),
        "无主窗口验收程序必须复用生产切换门，并持久化按钮或超时结果"
    )
    try expect(
        timelineView.contains("桌面变化")
            && timelineView.contains("（不等于分心）")
            && timelineView.contains("工作节点")
            && timelineView.contains("切换理由、保存/恢复、专注状态和屏幕状态"),
        "时间轴必须用用户语言解释桌面变化和工作节点"
    )
}

suite.run("更新清单按语义版本和构建号判断") {
    let assetURL = URL(
        string: "https://github.com/cornliu26/FocusTrace/releases/download/v0.2.0/FocusTrace-macOS-arm64.zip"
    )!
    let manifest = FocusTraceReleaseManifest(
        version: "0.2.0",
        build: "3",
        minimumSystemVersion: "14.0",
        bundleIdentifier: "com.local.FocusTrace",
        assetURL: assetURL,
        sha256: String(repeating: "a", count: 64),
        size: 42
    )
    try expect(manifest.isNewer(thanVersion: "0.1.9", build: "99"), "语义版本比较错误")
    try expect(!manifest.isNewer(thanVersion: "0.2.0", build: "3"), "相同版本不应更新")
    try expect(manifest.hasValidChecksum, "合法 SHA-256 未通过校验")

    let newerBuild = FocusTraceReleaseManifest(
        version: "0.2.0",
        build: "4",
        minimumSystemVersion: "14.0",
        bundleIdentifier: manifest.bundleIdentifier,
        assetURL: manifest.assetURL,
        sha256: manifest.sha256,
        size: manifest.size
    )
    try expect(newerBuild.isNewer(thanVersion: "0.2.0", build: "3"), "构建号比较错误")
    try expect(
        FocusTraceSemanticVersion("1.10.0")! > FocusTraceSemanticVersion("1.9.9")!,
        "语义版本不应按字符串排序"
    )
}

print("")
if suite.failures.isEmpty {
    print("FocusTrace verification: \(suite.passed) checks passed")
} else {
    print("FocusTrace verification: \(suite.passed) passed, \(suite.failures.count) failed")
    for failure in suite.failures { print("- \(failure)") }
    exit(EXIT_FAILURE)
}
