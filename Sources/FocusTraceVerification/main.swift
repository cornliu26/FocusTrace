import Foundation
import FocusTraceCore

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

suite.run("专注护栏只统计稳定且未经挂起的任务切换") {
    let start = Date(timeIntervalSince1970: 80_000)
    let taskA = UUID()
    let taskB = UUID()
    let taskC = UUID()
    let taskD = UUID()
    let intervals = [
        TaskIntervalRecord(taskID: taskA, startedAt: start, endedAt: start.addingTimeInterval(40)),
        TaskIntervalRecord(taskID: taskB, startedAt: start.addingTimeInterval(40), endedAt: start.addingTimeInterval(80)),
        TaskIntervalRecord(taskID: taskC, startedAt: start.addingTimeInterval(80), endedAt: start.addingTimeInterval(120)),
        TaskIntervalRecord(taskID: taskD, startedAt: start.addingTimeInterval(120), endedAt: nil),
    ]
    let now = start.addingTimeInterval(160)
    try expect(AttentionCueEngine.stableTaskSwitchCount(
        intervals: intervals,
        parkings: [],
        at: now
    ) == 3, "三个稳定任务转换应被统计")

    let parking = TaskParkingRecord(
        taskID: taskA,
        parkedAt: start.addingTimeInterval(40),
        resumeCue: "等待 Agent 完成",
        switchedToTaskID: taskB
    )
    try expect(AttentionCueEngine.stableTaskSwitchCount(
        intervals: intervals,
        parkings: [parking],
        at: now
    ) == 2, "主动挂起后的转换不应触发护栏")
}

suite.run("专注护栏忽略不足三十秒的短暂任务") {
    let start = Date(timeIntervalSince1970: 81_000)
    let intervals = [
        TaskIntervalRecord(taskID: UUID(), startedAt: start, endedAt: start.addingTimeInterval(60)),
        TaskIntervalRecord(taskID: UUID(), startedAt: start.addingTimeInterval(60), endedAt: nil),
    ]
    try expect(AttentionCueEngine.stableTaskSwitchCount(
        intervals: intervals,
        parkings: [],
        at: start.addingTimeInterval(89)
    ) == 0, "不足三十秒的目标任务不应被计为稳定切换")
}

suite.run("专注护栏在三次和五次切换时分级提示") {
    let start = Date(timeIntervalSince1970: 82_000)
    let tasks = (0..<6).map { _ in UUID() }
    let intervals = tasks.enumerated().map { index, taskID in
        TaskIntervalRecord(
            taskID: taskID,
            startedAt: start.addingTimeInterval(Double(index * 30)),
            endedAt: index == tasks.count - 1
                ? nil
                : start.addingTimeInterval(Double((index + 1) * 30))
        )
    }
    let gentle = AttentionCueEngine.switchDecision(
        intervals: Array(intervals.prefix(4)),
        parkings: [],
        at: start.addingTimeInterval(120)
    )
    try expect(gentle.level == .gentle && gentle.switchCount == 3, "三次切换应温和提示")

    let strong = AttentionCueEngine.switchDecision(
        intervals: intervals,
        parkings: [],
        at: start.addingTimeInterval(180)
    )
    try expect(strong.level == .strong && strong.switchCount == 5, "五次切换应加强提示")
}

suite.run("专注护栏按五分钟里程碑给予奖励") {
    try expect(AttentionCueEngine.continuityMilestoneMinutes(elapsedSeconds: 299) == 0, "不足五分钟不奖励")
    try expect(AttentionCueEngine.continuityMilestoneMinutes(elapsedSeconds: 300) == 5, "五分钟应立即奖励")
    try expect(AttentionCueEngine.continuityMilestoneMinutes(elapsedSeconds: 601) == 10, "十分钟应进入下一里程碑")
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
    try expect(markdown.contains("挂起工作流 / 已返回：2 / 1 次"), "日报应包含挂起聚合指标")
    try expect(!markdown.contains("PRIVATE_RESUME_CUE"), "日报不应暴露恢复线索")
    try expect(!markdown.contains("com.openai.codex"), "日报不应泄露 Bundle ID")
    try expect(!markdown.contains(fixture.snapshot.activities[0].id.uuidString), "日报不应泄露原始事件 ID")
    let json = try AutomationReportEngine.jsonData(for: report)
    let jsonText = String(decoding: json, as: UTF8.self)
    try expect(jsonText.contains("\"schemaVersion\" : 2"), "结构化日报应包含协议版本")
    try expect(jsonText.contains("\"recommendation\""), "结构化日报应包含单项训练")
    try expect(!jsonText.contains("PRIVATE_RESUME_CUE"), "结构化日报不应暴露恢复线索")
    try expect(!jsonText.contains("com.openai.codex"), "结构化日报不应泄露 Bundle ID")
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
