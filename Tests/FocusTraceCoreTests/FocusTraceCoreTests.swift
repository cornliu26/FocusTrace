import Foundation
import Testing
import FocusTraceMacSupport
@testable import FocusTraceCore

@Test
func flowGuidanceAlwaysExposesOnlyTheNextRequiredAction() {
    let create = FlowGuidanceEngine.guidance(
        hasOpenWorkflows: false,
        currentWorkflowTitle: nil,
        capturePaused: false,
        isWithinSchedule: true,
        focusRemainingSeconds: nil,
        planMinutes: 15
    )
    #expect(create.action == .createWorkflow)

    let bind = FlowGuidanceEngine.guidance(
        hasOpenWorkflows: true,
        currentWorkflowTitle: nil,
        capturePaused: false,
        isWithinSchedule: true,
        focusRemainingSeconds: nil,
        planMinutes: 15
    )
    #expect(bind.action == .bindWorkflow)

    let start = FlowGuidanceEngine.guidance(
        hasOpenWorkflows: true,
        currentWorkflowTitle: "排查登录问题",
        capturePaused: false,
        isWithinSchedule: true,
        focusRemainingSeconds: nil,
        planMinutes: 17
    )
    #expect(start.action == .startFocus(minutes: 17))

    let active = FlowGuidanceEngine.guidance(
        hasOpenWorkflows: true,
        currentWorkflowTitle: "排查登录问题",
        capturePaused: false,
        isWithinSchedule: true,
        focusRemainingSeconds: 125,
        planMinutes: 15
    )
    #expect(active.action == .viewFocus)
    #expect(active.detail.contains("02:05"))

    let paused = FlowGuidanceEngine.guidance(
        hasOpenWorkflows: true,
        currentWorkflowTitle: "排查登录问题",
        capturePaused: true,
        isWithinSchedule: true,
        focusRemainingSeconds: nil,
        planMinutes: 15
    )
    #expect(paused.action == .resumeCapture)

    let outsideSchedule = FlowGuidanceEngine.guidance(
        hasOpenWorkflows: true,
        currentWorkflowTitle: "排查登录问题",
        capturePaused: false,
        isWithinSchedule: false,
        focusRemainingSeconds: nil,
        planMinutes: 15
    )
    #expect(outsideSchedule.action == .openSchedule)
}

@Test
func toolSuggestionsPreferTheWorkflowMostUsedRealApps() {
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
    #expect(suggestions == [terminal, codex])
}

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
func optimizedDailyUXContractRemainsStable() {
    #expect(
        FocusTraceUXContract.dateSelectionPresentation
            == .graphicalCalendarPopover
    )
    #expect(FocusTraceUXContract.menuBarWidth == 304)
    #expect(FocusTraceUXContract.onboardingRequiredInputs == ["workflowName"])
    #expect(FocusTraceUXContract.primaryDailyActionCount == 1)
}

@Test
func dateNavigationNormalizesDaysAndNeverMovesIntoTheFuture() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let latest = calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 24,
        hour: 18,
        minute: 30
    ))!
    let yesterday = calendar.date(byAdding: .day, value: -1, to: latest)!

    #expect(FocusTraceDateNavigation.canMoveForward(
        selection: yesterday,
        latestDate: latest,
        calendar: calendar
    ))

    let movedToToday = FocusTraceDateNavigation.movedSelection(
        yesterday,
        byDays: 1,
        latestDate: latest,
        calendar: calendar
    )
    #expect(movedToToday == calendar.startOfDay(for: latest))
    #expect(!FocusTraceDateNavigation.canMoveForward(
        selection: movedToToday,
        latestDate: latest,
        calendar: calendar
    ))

    let capped = FocusTraceDateNavigation.movedSelection(
        latest,
        byDays: 10,
        latestDate: latest,
        calendar: calendar
    )
    #expect(capped == calendar.startOfDay(for: latest))
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
func attentionCueCountsOnlyStableUnplannedTaskSwitches() {
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

    #expect(AttentionCueEngine.stableTaskSwitchCount(
        intervals: intervals,
        parkings: [],
        at: now
    ) == 3)

    let parking = TaskParkingRecord(
        taskID: taskA,
        parkedAt: start.addingTimeInterval(40),
        resumeCue: "等待 Agent 完成",
        switchedToTaskID: taskB
    )
    #expect(AttentionCueEngine.stableTaskSwitchCount(
        intervals: intervals,
        parkings: [parking],
        at: now
    ) == 2)
}

@Test
func attentionCueIgnoresTaskThatDidNotStayThirtySeconds() {
    let start = Date(timeIntervalSince1970: 81_000)
    let taskA = UUID()
    let taskB = UUID()
    let intervals = [
        TaskIntervalRecord(taskID: taskA, startedAt: start, endedAt: start.addingTimeInterval(60)),
        TaskIntervalRecord(taskID: taskB, startedAt: start.addingTimeInterval(60), endedAt: nil),
    ]
    #expect(AttentionCueEngine.stableTaskSwitchCount(
        intervals: intervals,
        parkings: [],
        at: start.addingTimeInterval(89)
    ) == 0)
}

@Test
func attentionCueUsesGentleAndStrongThresholds() {
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
    #expect(gentle.level == .gentle)
    #expect(gentle.switchCount == 3)

    let strong = AttentionCueEngine.switchDecision(
        intervals: intervals,
        parkings: [],
        at: start.addingTimeInterval(180)
    )
    #expect(strong.level == .strong)
    #expect(strong.switchCount == 5)
}

@Test
func attentionCueContinuitySurvivesShortSameTaskRefreshGap() {
    let start = Date(timeIntervalSince1970: 83_000)
    let task = UUID()
    let now = start.addingTimeInterval(601)
    let intervals = [
        TaskIntervalRecord(taskID: task, startedAt: start, endedAt: start.addingTimeInterval(300)),
        TaskIntervalRecord(taskID: task, startedAt: start.addingTimeInterval(301), endedAt: nil),
    ]
    let elapsed = AttentionCueEngine.continuousTaskSeconds(
        intervals: intervals,
        taskID: task,
        at: now
    )
    #expect(elapsed == 601)
    #expect(AttentionCueEngine.continuityMilestoneMinutes(elapsedSeconds: elapsed) == 10)
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
func stableSpaceIdentityDoesNotMoveWhenAnotherDesktopIsInsertedReorderedOrDeleted() {
    let workflowID = UUID()
    let original = WorkflowSpaceIdentity(
        displayIdentifier: "display-a",
        managedSpaceID: 41,
        spaceUUID: "space-original"
    )
    let inserted = WorkflowSpaceIdentity(
        displayIdentifier: "display-a",
        managedSpaceID: 99,
        spaceUUID: "space-new"
    )
    let binding = WorkflowSpaceBindingRecord(
        workflowID: workflowID,
        anchorRestorationID: "legacy-anchor",
        displayHint: "display-a",
        spaceIdentity: original
    )

    #expect(WorkflowSpaceResolutionEngine.resolve(
        currentSpaceIdentity: original,
        bindings: [binding],
        registryReady: true
    ) == .bound(workflowID: workflowID))
    #expect(WorkflowSpaceResolutionEngine.resolve(
        currentSpaceIdentity: inserted,
        bindings: [binding],
        registryReady: true
    ) == .unbound)

    // Reordering affects only presentation order, which is deliberately not
    // part of either the binding or the resolver input.
    let reorderedCurrent = WorkflowSpaceIdentity(
        displayIdentifier: "display-a",
        managedSpaceID: 41,
        spaceUUID: "space-original"
    )
    #expect(WorkflowSpaceResolutionEngine.resolve(
        currentSpaceIdentity: reorderedCurrent,
        bindings: [binding],
        registryReady: true
    ) == .bound(workflowID: workflowID))

    // Deleting the other desktop removes it from the window-server inventory;
    // it cannot change the original binding because presentation indexes are
    // never persisted.
    #expect(WorkflowSpaceResolutionEngine.resolve(
        currentSpaceIdentity: original,
        bindings: [binding],
        registryReady: true
    ) == .bound(workflowID: workflowID))
}

@Test
func globallyActiveSpaceWinsOverPointerDisplayCurrentSpace() {
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
    #expect(WorkflowSpaceIdentitySelector.activeIdentity(
        managedSpaceID: 495,
        allSpaces: [pointerDisplaySpace, actuallyActivatedSpace]
    ) == actuallyActivatedSpace)

    let duplicatedID = WorkflowSpaceIdentity(
        displayIdentifier: "another-display",
        managedSpaceID: 495,
        spaceUUID: "ambiguous-space"
    )
    #expect(WorkflowSpaceIdentitySelector.activeIdentity(
        managedSpaceID: 495,
        allSpaces: [actuallyActivatedSpace, duplicatedID]
    ) == nil)
}

@Test
func oneDisplayDeltaWinsOverStaleGlobalActiveSpace() {
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

    #expect(WorkflowSpaceTransitionSelector.changedIdentity(
        previousCurrentSpaces: [displayAOld, staleGlobalActive, displayC],
        currentSpaces: [displayANew, staleGlobalActive, displayC],
        activeIdentity: staleGlobalActive
    ) == displayANew)

    #expect(WorkflowSpaceTransitionSelector.changedIdentity(
        previousCurrentSpaces: [displayAOld, staleGlobalActive],
        currentSpaces: [displayANew, displayC],
        activeIdentity: displayC
    ) == displayC)

    #expect(WorkflowSpaceTransitionSelector.changedIdentity(
        previousCurrentSpaces: [displayANew, staleGlobalActive, displayC],
        currentSpaces: [displayANew, staleGlobalActive, displayC],
        activeIdentity: staleGlobalActive
    ) == nil)
}

@Test
func preDisplayDeltaBindingsRequireOneTimeRebindAfterIsolationFix() {
    let identity = WorkflowSpaceIdentity(
        displayIdentifier: "display-a",
        managedSpaceID: 304,
        spaceUUID: "space-a"
    )
    #expect(!WorkflowSpaceBindingCompatibility.canRestore(
        identity: identity,
        identityVersion: nil
    ))
    #expect(!WorkflowSpaceBindingCompatibility.canRestore(
        identity: identity,
        identityVersion: 1
    ))
    #expect(!WorkflowSpaceBindingCompatibility.canRestore(
        identity: identity,
        identityVersion: 2
    ))
    #expect(WorkflowSpaceBindingCompatibility.canRestore(
        identity: identity,
        identityVersion: WorkflowSpaceBindingCompatibility.currentIdentityVersion
    ))
}

@Test
func spaceIdentityIsScopedToItsDisplayAndPrefersUUID() {
    let first = WorkflowSpaceIdentity(
        displayIdentifier: "display-a",
        managedSpaceID: 7,
        spaceUUID: "uuid-a"
    )
    let otherDisplay = WorkflowSpaceIdentity(
        displayIdentifier: "display-b",
        managedSpaceID: 7,
        spaceUUID: "uuid-a"
    )
    let reusedNumericID = WorkflowSpaceIdentity(
        displayIdentifier: "display-a",
        managedSpaceID: 7,
        spaceUUID: "uuid-b"
    )
    #expect(!first.identifiesSameSpace(as: otherDisplay))
    #expect(!first.identifiesSameSpace(as: reusedNumericID))
}

@Test
func legacySpaceBindingDecodesWithoutStableIdentity() throws {
    let workflowID = UUID()
    let bindingID = UUID()
    let legacyJSON = """
    {
      "id": "\(bindingID.uuidString)",
      "workflowID": "\(workflowID.uuidString)",
      "anchorRestorationID": "old-window-anchor",
      "state": "verified",
      "boundAt": 1000
    }
    """
    let decoded = try JSONDecoder().decode(
        WorkflowSpaceBindingRecord.self,
        from: Data(legacyJSON.utf8)
    )
    #expect(decoded.id == bindingID)
    #expect(decoded.workflowID == workflowID)
    #expect(decoded.spaceIdentity == nil)
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
func dailyCoachRefusesBehaviorAdviceWhenWorkflowAttributionIsLow() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
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
    #expect(result.metrics.attributedRatio == 0.5)
    #expect(!result.quality.isReliableForBehavior)
    #expect(result.recommendation.kind == .repairAttribution)
    #expect(result.recommendation.action == .bindWorkflow)
}

@Test
func dailyCoachTreatsExtremelyDenseSpaceSignalsAsInstrumentationRisk() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
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
    #expect(!result.quality.isReliableForBehavior)
    #expect(result.quality.warnings.contains { $0.contains("Space 识别噪声") })
    #expect(result.recommendation.kind == .verifySpaceTracking)
}

@Test
func dailyCoachNormalizesRatesAndStartsWithOneMeasurableTrainingRound() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 9))!
    let task = UUID()
    let appA = AppIdentity(bundleID: "a", name: "A")
    let appB = AppIdentity(bundleID: "b", name: "B")
    var activities: [ActivityRecord] = []
    for dayOffset in 0..<3 {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: start)!
        activities.append(ActivityRecord(app: appA, startedAt: day, endedAt: day.addingTimeInterval(30 * 60), taskID: task, focusSessionID: nil, classification: .allowed))
        activities.append(ActivityRecord(app: appB, startedAt: day.addingTimeInterval(30 * 60), endedAt: day.addingTimeInterval(60 * 60), taskID: task, focusSessionID: nil, classification: .allowed))
    }
    let snapshot = FocusTraceLocalSnapshot(
        activities: activities,
        trainingPlans: [TrainingPlanRecord(version: 1, focusMinutes: 15, reason: "default")]
    )
    let reportDate = calendar.date(byAdding: .day, value: 2, to: start)!
    let result = DailyCoachEngine.analyze(
        snapshot: snapshot,
        reportDate: reportDate,
        generatedAt: reportDate.addingTimeInterval(60 * 60),
        calendar: calendar
    )
    #expect(result.metrics.recordedMinutes == 60)
    #expect(result.metrics.appSwitchesPerHour == 1)
    #expect(result.trend.baselineDays == 2)
    #expect(result.recommendation.kind == .startFocusRound)
    #expect(result.recommendation.action == .startFocus(minutes: 15))
    #expect(result.recommendation.method.successMeasure.contains("目标时长"))
}

@Test
func dailyCoachEvaluatesThePreviousTrainingFromObservedOutcome() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
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
    #expect(result.previousRecommendationEvaluation?.status == .improved)
    #expect(result.previousRecommendationEvaluation?.evidence.contains("1/1") == true)
}

@Test
func dailyCoachEvaluatesTheExactPreviouslyIssuedRecommendation() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
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
    #expect(result.previousRecommendationEvaluation?.status == .improved)
    #expect(result.previousRecommendationEvaluation?.title.contains("归因") == true)
}

@Test
func automationJSONIsStructuredAndAggregateOnly() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 9))!
    let task = UUID()
    let app = AppIdentity(bundleID: "private.bundle", name: "Private App")
    let snapshot = FocusTraceLocalSnapshot(
        activities: [ActivityRecord(app: app, startedAt: day, endedAt: day.addingTimeInterval(60 * 60), taskID: task, focusSessionID: nil, classification: .allowed)],
        trainingPlans: [TrainingPlanRecord(version: 1, focusMinutes: 15, reason: "default")],
        taskParkings: [TaskParkingRecord(taskID: task, parkedAt: day, resumeCue: "SECRET_RESUME_CUE")]
    )
    let report = AutomationReportEngine.makeReport(
        snapshot: snapshot,
        reportDate: day,
        generatedAt: day.addingTimeInterval(60 * 60),
        calendar: calendar
    )
    let data = try AutomationReportEngine.jsonData(for: report)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\"schemaVersion\" : 2"))
    #expect(text.contains("\"recommendation\""))
    #expect(text.contains("\"appSwitchesPerHour\""))
    #expect(!text.contains("private.bundle"))
    #expect(!text.contains("Private App"))
    #expect(!text.contains("SECRET_RESUME_CUE"))
}

@Test
func codexReviewRequiresACompleteTwoEvidenceWriteback() {
    let review = CodexReviewArtifact(
        sourceReportID: "focustrace-report",
        reportDate: Date(timeIntervalSince1970: 100),
        generatedAt: Date(timeIntervalSince1970: 200),
        headline: "今天的记录质量足够，但训练样本仍不足。",
        interpretation: "切换率只描述工作方式，不能单独证明分心。",
        recommendation: "今天完成一次 15 分钟训练。",
        evidence: ["有效记录 120 分钟", "工作流归因 86%"],
        nextCheck: "明天比较训练是否完成及主观难度。"
    )
    #expect(review.hasValidShape)

    let incomplete = CodexReviewArtifact(
        sourceReportID: review.sourceReportID,
        reportDate: review.reportDate,
        generatedAt: review.generatedAt,
        headline: review.headline,
        interpretation: review.interpretation,
        recommendation: review.recommendation,
        evidence: ["只有一条证据"],
        nextCheck: review.nextCheck
    )
    #expect(!incomplete.hasValidShape)
}

@Test
func codexWorkspaceDeepLinkPrefillsTheSupportedLocalChatContract() throws {
    let workspace = URL(
        fileURLWithPath: "/Users/example/Library/Application Support/FocusTrace/CodexWorkspace",
        isDirectory: true
    )
    let url = try #require(
        CodexWorkspaceContract.deepLink(workspaceURL: workspace)
    )
    let components = try #require(
        URLComponents(url: url, resolvingAgainstBaseURL: false)
    )
    let query = Dictionary(
        uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        }
    )

    #expect(components.scheme == "codex")
    #expect(components.host == "threads")
    #expect(components.path == "/new")
    #expect(query["path"] == workspace.standardizedFileURL.path)
    #expect(query["prompt"] == CodexWorkspaceContract.setupPrompt)
    #expect(query["prompt"]?.contains("每天 18:35") == true)
}

@Test
func codexWorkspaceMakesTheAggregateOnlyBoundaryDurable() {
    let instructions = CodexWorkspaceContract.agentsInstructions
    let script = CodexWorkspaceContract.reportScript

    #expect(instructions.contains("Read only `Reports/latest.json` and `Reports/latest.md`"))
    #expect(instructions.contains("Never read or expose FocusTrace `store.json`"))
    #expect(instructions.contains("evidence"))
    #expect(instructions.contains("at most one training"))
    #expect(script.contains("FocusTraceReport"))
    #expect(script.contains("Application Support/FocusTrace/CodexBridge"))
    #expect(script.contains("$BRIDGE_DIR/bridge.json"))
    #expect(!CodexWorkspaceContract.setupPrompt.contains("API key"))
}

@Test
func codexWorkspaceReportScriptIsValidBash() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let scriptURL = directory.appendingPathComponent("generate-daily-report.sh")
    try CodexWorkspaceContract.reportScript.write(
        to: scriptURL,
        atomically: true,
        encoding: .utf8
    )
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-n", scriptURL.path]
    try process.run()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
}

@Test @MainActor
func menuBarBrandMarkIsANonEmptyNativeTemplateImage() throws {
    let idle = FocusTraceMenuBarIcon.image(isFocusing: false)
    let focusing = FocusTraceMenuBarIcon.image(isFocusing: true)
    let idleData = try #require(idle.tiffRepresentation)
    let focusingData = try #require(focusing.tiffRepresentation)

    #expect(idle.isTemplate)
    #expect(focusing.isTemplate)
    #expect(idle.size.width == 18 && idle.size.height == 16)
    #expect(idleData.count > 100)
    #expect(focusingData.count > 100)
    #expect(idleData != focusingData)
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

@Test
func releaseManifestUsesSemanticVersionAndBuildOrdering() throws {
    let manifest = FocusTraceReleaseManifest(
        version: "0.2.0",
        build: "3",
        minimumSystemVersion: "14.0",
        bundleIdentifier: "com.local.FocusTrace",
        assetURL: try #require(
            URL(string: "https://github.com/cornliu26/FocusTrace/releases/download/v0.2.0/FocusTrace-macOS-arm64.zip")
        ),
        sha256: String(repeating: "a", count: 64),
        size: 42
    )
    #expect(manifest.isNewer(thanVersion: "0.1.9", build: "99"))
    #expect(!manifest.isNewer(thanVersion: "0.2.0", build: "3"))
    #expect(manifest.hasValidChecksum)

    let newerBuild = FocusTraceReleaseManifest(
        version: "0.2.0",
        build: "4",
        minimumSystemVersion: "14.0",
        bundleIdentifier: manifest.bundleIdentifier,
        assetURL: manifest.assetURL,
        sha256: manifest.sha256,
        size: manifest.size
    )
    #expect(newerBuild.isNewer(thanVersion: "0.2.0", build: "3"))
    #expect(FocusTraceSemanticVersion("1.10.0")! > FocusTraceSemanticVersion("1.9.9")!)
}
