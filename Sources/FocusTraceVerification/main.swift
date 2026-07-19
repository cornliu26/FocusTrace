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
    return (
        FocusTraceLocalSnapshot(
            activities: activities,
            focusSessions: sessions,
            interruptions: interruptions,
            trainingPlans: [plan]
        ),
        calendar,
        calendar.date(byAdding: .day, value: 9, to: start)!
    )
}

private var suite = VerificationSuite()

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

suite.run("每日指标分开统计切换和确认分心") {
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
        taskIntervals: [TaskIntervalRecord(taskID: task, startedAt: start, endedAt: start.addingTimeInterval(150))],
        interruptions: [interruption],
        now: start.addingTimeInterval(150)
    )
    try expect(summary.appSwitchCount == 2, "应用切换次数错误")
    try expect(summary.taskSwitchCount == 0, "任务切换次数错误")
    try expect(summary.confirmedDistractionCount == 1, "确认分心次数错误")
    try expect(summary.averageReturnLatency == 10, "返回耗时错误")
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
    try expect(!markdown.contains("com.openai.codex"), "日报不应泄露 Bundle ID")
    try expect(!markdown.contains(fixture.snapshot.activities[0].id.uuidString), "日报不应泄露原始事件 ID")
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
}

print("")
if suite.failures.isEmpty {
    print("FocusTrace verification: \(suite.passed) checks passed")
} else {
    print("FocusTrace verification: \(suite.passed) passed, \(suite.failures.count) failed")
    for failure in suite.failures { print("- \(failure)") }
    exit(EXIT_FAILURE)
}
