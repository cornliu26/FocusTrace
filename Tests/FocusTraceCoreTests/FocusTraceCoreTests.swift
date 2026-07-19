import Foundation
import Testing
@testable import FocusTraceCore

@Test
func activationClosesPreviousAndIgnoresDuplicate() {
    let start = Date(timeIntervalSince1970: 1_000)
    let second = start.addingTimeInterval(12)
    let appA = AppIdentity(bundleID: "a", name: "A")
    let appB = AppIdentity(bundleID: "b", name: "B")
    var machine = ActivityCaptureStateMachine()

    let first = machine.activate(appA, at: start)
    #expect(first.closed == nil)
    #expect(first.opened?.app == appA)

    let duplicate = machine.activate(appA, at: start.addingTimeInterval(2))
    #expect(duplicate.ignoredDuplicate)
    #expect(machine.current?.startedAt == start)

    let transition = machine.activate(appB, at: second)
    #expect(transition.closed?.app == appA)
    #expect(transition.closedAt == second)
    #expect(transition.opened?.app == appB)
}

@Test
func sleepClosesAndWakeReopens() {
    let start = Date(timeIntervalSince1970: 1_000)
    let app = AppIdentity(bundleID: "a", name: "A")
    var machine = ActivityCaptureStateMachine()
    _ = machine.activate(app, at: start)

    let asleep = machine.becomeInactive(at: start.addingTimeInterval(20))
    #expect(asleep.closed?.app == app)
    #expect(machine.current == nil)
    #expect(!machine.isSystemActive)

    let ignored = machine.activate(app, at: start.addingTimeInterval(30))
    #expect(ignored.ignoredDuplicate)

    let awake = machine.becomeActive(app, at: start.addingTimeInterval(40))
    #expect(awake.opened?.startedAt == start.addingTimeInterval(40))
    #expect(machine.isSystemActive)
}

@Test
func distractionGateRequiresAllConditions() {
    #expect(!DistractionGate.shouldTrigger(
        duration: 19.9,
        thresholdSeconds: 20,
        isAllowed: false,
        isFocusActive: true,
        baselineComplete: true
    ))
    #expect(DistractionGate.shouldTrigger(
        duration: 20,
        thresholdSeconds: 20,
        isAllowed: false,
        isFocusActive: true,
        baselineComplete: true
    ))
    #expect(!DistractionGate.shouldTrigger(
        duration: 30,
        thresholdSeconds: 20,
        isAllowed: true,
        isFocusActive: true,
        baselineComplete: true
    ))
    #expect(!DistractionGate.shouldTrigger(
        duration: 30,
        thresholdSeconds: 20,
        isAllowed: false,
        isFocusActive: true,
        baselineComplete: false
    ))
}

@Test
func initialDurationUsesDefaultWhenSamplesAreInsufficient() {
    #expect(TrainingEngine.initialFocusMinutes(baselineStreaks: [600, 900]) == 15)
}

@Test
func initialDurationRoundsAndClamps() {
    #expect(TrainingEngine.initialFocusMinutes(baselineStreaks: Array(repeating: 13 * 60, count: 10)) == 15)
    #expect(TrainingEngine.initialFocusMinutes(baselineStreaks: Array(repeating: 2 * 60, count: 10)) == 10)
    #expect(TrainingEngine.initialFocusMinutes(baselineStreaks: Array(repeating: 60 * 60, count: 10)) == 25)
}

@Test
func fiveSessionProgression() {
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

    let fourSuccesses = (0..<5).map { session(success: $0 < 4, offset: $0) }
    #expect(TrainingEngine.progression(currentMinutes: 15, lastFive: fourSuccesses) == .increase(toMinutes: 20))

    let twoSuccesses = (0..<5).map { session(success: $0 < 2, offset: $0) }
    #expect(TrainingEngine.progression(currentMinutes: 15, lastFive: twoSuccesses) == .decrease(toMinutes: 10))

    let threeSuccesses = (0..<5).map { session(success: $0 < 3, offset: $0) }
    #expect(TrainingEngine.progression(currentMinutes: 15, lastFive: threeSuccesses) == .maintain(minutes: 15))
}

@Test
func baselineStreakBreaksOnDistractionAndTaskChange() {
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
    #expect(TrainingEngine.baselineStreaks(from: records) == [120, 30])
}

@Test
func dailySummaryKeepsSwitchAndDistractionCountsSeparate() {
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
    #expect(summary.appSwitchCount == 2)
    #expect(summary.taskSwitchCount == 0)
    #expect(summary.confirmedDistractionCount == 1)
    #expect(summary.averageReturnLatency == 10)
}

@Test
func analysisLocksUntilMinimumData() {
    let plan = TrainingPlanRecord(version: 1, focusMinutes: 15, reason: "default")
    let result = AdaptiveAnalyzer.analyze(activities: [], sessions: [], interruptions: [], currentPlan: plan)
    #expect(result.readiness == .locked(workdays: 0, sessions: 0))
    #expect(result.suggestion == nil)
}

@Test
func analysisSurfacesRepeatedRiskAppFirst() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let task = UUID()
    let start = Date(timeIntervalSince1970: 100_000)
    let app = AppIdentity(bundleID: "risk", name: "Risk")
    let activities = (0..<10).map { day in
        let date = calendar.date(byAdding: .day, value: day, to: start)!
        return ActivityRecord(app: app, startedAt: date, endedAt: date.addingTimeInterval(60), taskID: task, focusSessionID: nil, classification: .allowed)
    }
    let sessions = (0..<20).map { offset in
        let date = start.addingTimeInterval(Double(offset * 1_000))
        return FocusSessionRecord(taskID: task, startedAt: date, endedAt: date.addingTimeInterval(900), targetSeconds: 900, outcome: .completed, difficulty: 2, confirmedDistractionCount: 0)
    }
    let interruptions = (0..<3).map { offset in
        InterruptionRecord(
            activityID: UUID(),
            focusSessionID: sessions[offset].id,
            taskID: task,
            app: app,
            detectedAt: start.addingTimeInterval(Double(offset)),
            resolvedAt: start.addingTimeInterval(Double(offset + 1)),
            resolution: .returnedToTask
        )
    }
    let plan = TrainingPlanRecord(version: 1, focusMinutes: 15, reason: "default")
    let result = AdaptiveAnalyzer.analyze(
        activities: activities,
        sessions: sessions,
        interruptions: interruptions,
        currentPlan: plan,
        calendar: calendar
    )
    #expect(result.readiness == .ready)
    #expect(result.suggestion?.kind == .highRiskApp)
}

@Test
func csvQuotesSeparatorsWithoutAddingExtraFields() {
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
    #expect(csv.contains("\"App, \"\"Work\"\"\""))
    #expect(csv.contains("com.example.app"))
    #expect(!csv.contains("window_title"))
    #expect(!csv.contains("url"))
}

@Test
func jsonRoundTrip() throws {
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
    #expect(decoded.tasks.first?.title == "Task")
}
