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
func loginWindowIsTreatedAsSystemInactive() {
    let loginWindow = AppIdentity(bundleID: "com.apple.loginwindow", name: "loginwindow")
    let normalApp = AppIdentity(bundleID: "com.apple.Terminal", name: "Terminal")
    #expect(SystemActivityGate.isSystemInactiveApp(loginWindow))
    #expect(!SystemActivityGate.isSystemInactiveApp(normalApp))
}

@Test
func selectedDateFollowsMidnightOnlyWhenViewingToday() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let yesterday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 19, hour: 23, minute: 59))!
    let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 0, minute: 1))!
    let selectedYesterday = calendar.startOfDay(for: yesterday)

    let rolled = TimelineDateEngine.selectedDateAfterTick(
        selectedDate: selectedYesterday,
        previousNow: yesterday,
        currentNow: today,
        calendar: calendar
    )
    #expect(calendar.isDate(rolled, inSameDayAs: today))

    let historical = calendar.date(byAdding: .day, value: -2, to: selectedYesterday)!
    let preserved = TimelineDateEngine.selectedDateAfterTick(
        selectedDate: historical,
        previousNow: yesterday,
        currentNow: today,
        calendar: calendar
    )
    #expect(preserved == historical)
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
    #expect(summary.appSwitchCount == 2)
    #expect(summary.workflowSwitchCount == 1)
    #expect(summary.taskSwitchCount == 1)
    #expect(summary.confirmedDistractionCount == 1)
    #expect(summary.averageReturnLatency == 10)
}

@Test
func timelineAggregationUsesDominantAppAndHidesSystemActivity() {
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
    #expect(buckets.count == 2)
    #expect(buckets[0].dominantApp == appA)
    #expect(buckets[0].switchCount == 2)
    #expect(buckets[0].spaceSwitchCount == 1)
    #expect(buckets[1].dominantApp == appB)
    #expect(buckets[1].switchCount == 1)
    #expect(buckets[1].uniqueAppCount == 2)
}

@Test
func fragmentationLevelHasStableFiveMinuteBoundaries() {
    #expect(FragmentationLevel.classify(switchCount: 2) == .quiet)
    #expect(FragmentationLevel.classify(switchCount: 3) == .steady)
    #expect(FragmentationLevel.classify(switchCount: 6) == .fragmented)
    #expect(FragmentationLevel.classify(switchCount: 11) == .intense)
}

@Test
func nearbyEventsAreClusteredWithoutSpaceMarkers() {
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
    #expect(buckets.count == 2)
    #expect(buckets[0].eventCount == 2)
    #expect(buckets[0].countsByKind[.screenWoke] == 1)
    #expect(buckets[1].kinds == [.taskChanged])
}

@Test
func workflowCompletionReleasesBindingsAndUndoRequiresRebind() throws {
    let workflowID = UUID()
    let completedAt = Date(timeIntervalSince1970: 60_000)
    let initial = WorkflowLifecycleState(
        workflowID: workflowID,
        bindingCount: 2,
        hasCheckpoint: true
    )
    let completed = try WorkflowLifecycleEngine.transition(initial, event: .complete, at: completedAt)
    #expect(completed.state.lifecycle == .completed)
    #expect(completed.state.bindingCount == 0)
    #expect(completed.state.completedAt == completedAt)
    #expect(completed.effects.contains(.releaseAllBindings(workflowID: workflowID)))
    #expect(completed.effects.contains(.checkpointResolved(workflowID: workflowID)))

    let undone = try WorkflowLifecycleEngine.transition(completed.state, event: .undoCompletion)
    #expect(undone.state.lifecycle == .open)
    #expect(undone.state.bindingCount == 0)
    #expect(undone.effects == [.requiresRebind(workflowID: workflowID)])
}

@Test
func spaceResolutionNeverGuessesWhenUnknownOrConflicted() {
    let workflowA = UUID()
    let workflowB = UUID()
    #expect(WorkflowSpaceResolutionEngine.resolve(
        activeAnchorWorkflowIDs: [workflowA],
        registryReady: false
    ) == .unknown)
    #expect(WorkflowSpaceResolutionEngine.resolve(
        activeAnchorWorkflowIDs: [],
        registryReady: true
    ) == .unbound)
    #expect(WorkflowSpaceResolutionEngine.resolve(
        activeAnchorWorkflowIDs: [workflowA, workflowA],
        registryReady: true
    ) == .bound(workflowID: workflowA))
    let conflict = WorkflowSpaceResolutionEngine.resolve(
        activeAnchorWorkflowIDs: [workflowA, workflowB],
        registryReady: true
    )
    if case let .conflict(ids) = conflict {
        #expect(Set(ids) == Set([workflowA, workflowB]))
    } else {
        Issue.record("multiple workflow anchors should conflict")
    }
}

@Test
func unknownSpaceClosesWorkflowWithoutCarryingAttribution() {
    let workflowID = UUID()
    let start = Date(timeIntervalSince1970: 70_000)
    let entered = WorkflowContextEngine.transition(
        WorkflowContextState(),
        to: .bound(workflowID: workflowID),
        at: start
    )
    #expect(entered.state.context.workflowID == workflowID)

    let unknownAt = start.addingTimeInterval(30)
    let unknown = WorkflowContextEngine.transition(entered.state, to: .unknown, at: unknownAt)
    #expect(unknown.state.context.kind == .unknown)
    #expect(unknown.state.context.workflowID == nil)
    #expect(unknown.effects.contains(.workflowBecameBackground(workflowID: workflowID)))
    #expect(unknown.effects.contains(.closeInterval(
        context: entered.state.context,
        startedAt: start,
        endedAt: unknownAt
    )))
}

@Test
func focusWorkflowDepartureHasGraceAndSubtractsPausedTime() {
    let focusWorkflow = UUID()
    let otherWorkflow = UUID()
    let start = Date(timeIntervalSince1970: 80_000)
    let initial = FocusWorkflowDepartureState(focusWorkflowID: focusWorkflow)
    let departed = FocusWorkflowDepartureEngine.contextChanged(
        initial,
        to: otherWorkflow,
        at: start
    )
    #expect(departed.effects == [.scheduleGrace(deadline: start.addingTimeInterval(10))])

    let briefReturn = FocusWorkflowDepartureEngine.contextChanged(
        departed.state,
        to: focusWorkflow,
        at: start.addingTimeInterval(8)
    )
    #expect(briefReturn.effects == [.cancelGrace])
    #expect(briefReturn.state.pausedAt == nil)

    let departedAgain = FocusWorkflowDepartureEngine.contextChanged(
        briefReturn.state,
        to: otherWorkflow,
        at: start.addingTimeInterval(20)
    )
    let paused = FocusWorkflowDepartureEngine.graceElapsed(departedAgain.state)
    let resumed = FocusWorkflowDepartureEngine.contextChanged(
        paused.state,
        to: focusWorkflow,
        at: start.addingTimeInterval(45)
    )
    #expect(resumed.state.accumulatedPausedSeconds == 25)
    #expect(FocusWorkflowDepartureEngine.activeElapsedSeconds(
        startedAt: start,
        endedAt: start.addingTimeInterval(100),
        state: resumed.state
    ) == 75)
}

@Test
func legacyTaskLifecycleMigrationIsLossless() {
    #expect(WorkflowLifecycleMigration.lifecycle(
        rawValue: nil,
        isArchived: false,
        completedAt: nil
    ) == .open)
    #expect(WorkflowLifecycleMigration.lifecycle(
        rawValue: nil,
        isArchived: true,
        completedAt: nil
    ) == .archived)
    #expect(WorkflowLifecycleMigration.lifecycle(
        rawValue: nil,
        isArchived: false,
        completedAt: Date()
    ) == .completed)
}

@Test
func parkingReminderRequiresActiveDueAndUnsentRecord() {
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
        reminderSentAt: now
    )
    let resumed = TaskParkingRecord(
        taskID: task,
        parkedAt: now.addingTimeInterval(-600),
        resumeCue: "done",
        remindAt: now.addingTimeInterval(-1),
        resumedAt: now
    )
    #expect(TaskParkingEngine.dueForReminder([due, future, sent, resumed], at: now).map(\.id) == [due.id])
}

@Test
func parkingMetricsTrackResumptionWithoutReadingCue() {
    let start = Date(timeIntervalSince1970: 30_000)
    let task = UUID()
    let parkings = [
        TaskParkingRecord(taskID: task, parkedAt: start, resumeCue: "one", resumedAt: start.addingTimeInterval(600)),
        TaskParkingRecord(taskID: task, parkedAt: start, resumeCue: "two", resumedAt: start.addingTimeInterval(1_200)),
        TaskParkingRecord(taskID: task, parkedAt: start, resumeCue: "active")
    ]
    let summary = MetricsEngine.dailySummary(
        activities: [],
        taskIntervals: [],
        interruptions: [],
        taskParkings: parkings,
        now: start
    )
    #expect(summary.taskParkingCount == 3)
    #expect(summary.resumedTaskCount == 2)
    #expect(summary.averageTaskResumeLatency == 900)
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
    #expect(decoded.taskParkings.isEmpty)
}
