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
func workflowBindingIsExclusiveToTheMenuBarSurface() {
    let binding = FlowGuidanceEngine.guidance(
        hasOpenWorkflows: true,
        currentWorkflowTitle: nil,
        capturePaused: false,
        isWithinSchedule: true,
        focusRemainingSeconds: nil,
        planMinutes: 15
    )
    #expect(binding.action == .bindWorkflow)
    #expect(
        WorkflowBindingSurfacePolicy.canPresent(binding, on: .menuBar)
    )
    #expect(
        !WorkflowBindingSurfacePolicy.canPresent(binding, on: .mainWindow)
    )

    let focus = FlowGuidanceEngine.guidance(
        hasOpenWorkflows: true,
        currentWorkflowTitle: "排查登录问题",
        capturePaused: false,
        isWithinSchedule: true,
        focusRemainingSeconds: nil,
        planMinutes: 15
    )
    #expect(
        WorkflowBindingSurfacePolicy.canPresent(focus, on: .mainWindow)
    )
}

@Test
func workflowConfirmationUsesUpperCenterWithoutPassiveOverlay() {
    let visibleFrame = CGRect(x: 0, y: 25, width: 1_440, height: 875)
    let decision = FocusTraceConfirmationLayout.frame(
        in: visibleFrame,
        size: CGSize(
            width: FocusTraceConfirmationLayout.panelWidth,
            height: FocusTraceConfirmationLayout.panelHeight
        )
    )

    #expect(decision.midX == visibleFrame.midX)
    #expect(
        decision.maxY
            == visibleFrame.maxY - FocusTraceConfirmationLayout.topInset
    )
    #expect(decision.midY > visibleFrame.midY)
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
func lockExcludesWorkflowTimeUntilTheSessionActuallyUnlocks() {
    let start = Date(timeIntervalSince1970: 2_000)
    let workflowID = UUID()
    let range = DateInterval(start: start, duration: 60)
    let interval = TaskIntervalRecord(
        taskID: workflowID,
        startedAt: start,
        endedAt: range.end,
        workflowSource: .manual
    )
    let markers = [
        TimelineMarkerRecord(
            date: start.addingTimeInterval(10),
            kind: .sessionBecameInactive,
            taskID: workflowID
        ),
        TimelineMarkerRecord(
            date: start.addingTimeInterval(15),
            kind: .screenSlept,
            taskID: workflowID
        ),
        TimelineMarkerRecord(
            date: start.addingTimeInterval(30),
            kind: .screenWoke,
            taskID: workflowID
        ),
        TimelineMarkerRecord(
            date: start.addingTimeInterval(40),
            kind: .sessionBecameActive,
            taskID: workflowID
        )
    ]

    let counted = SystemInactiveIntervalEngine.countedWorkflowIntervals(
        taskIntervals: [interval],
        markers: markers,
        range: range,
        now: range.end
    )

    #expect(counted.count == 2)
    #expect(counted[0].startedAt == start)
    #expect(counted[0].endedAt == start.addingTimeInterval(10))
    #expect(counted[1].startedAt == start.addingTimeInterval(40))
    #expect(counted[1].endedAt == range.end)
    #expect(
        counted.reduce(0) {
            $0 + $1.endedAt.timeIntervalSince($1.startedAt)
        } == 30
    )
}

@Test
func lockPausesWorkflowAndFocusAccountingUntilAValidReturn() {
    let workflowID = UUID()
    let otherWorkflowID = UUID()

    #expect(WorkAccountingGate.shouldCountWorkflow(
        isRecordingWindow: true,
        isSystemActive: true,
        workflowID: workflowID
    ))
    #expect(!WorkAccountingGate.shouldCountWorkflow(
        isRecordingWindow: true,
        isSystemActive: false,
        workflowID: workflowID
    ))
    #expect(WorkAccountingGate.shouldPauseFocusForSystemInactivity(
        hasRunningFocus: true,
        focusIsAlreadyPaused: false
    ))
    #expect(!WorkAccountingGate.shouldResumeSystemPausedFocus(
        wasPausedBySystem: true,
        isRecordingWindow: true,
        isSystemActive: true,
        focusWorkflowID: workflowID,
        currentWorkflowID: otherWorkflowID
    ))
    #expect(WorkAccountingGate.shouldResumeSystemPausedFocus(
        wasPausedBySystem: true,
        isRecordingWindow: true,
        isSystemActive: true,
        focusWorkflowID: workflowID,
        currentWorkflowID: workflowID
    ))
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
    #expect(
        FocusTraceUXContract.requirementDateSelectionPresentation
            == .graphicalCalendarPopover
    )
    #expect(!FocusTraceUXContract.calendarPopoverAnimationsEnabled)
    #expect(FocusTraceUXContract.calendarRefreshGranularity == .day)
    #expect(FocusTraceUXContract.calendarPrewarmMonthOffsets == [-1, 0, 1])
    #expect(FocusTraceUXContract.menuBarWidth == 304)
    #expect(FocusTraceUXContract.onboardingRequiredInputs == ["workflowName"])
    #expect(FocusTraceUXContract.primaryDailyActionCount == 1)
    #expect(FocusTraceUXContract.sidebarIconCanvasSize == 18)
    #expect(FocusTraceUXContract.sidebarTimelineIcon == "clock.arrow.circlepath")
    #expect(FocusTraceUXContract.timelinePaletteName == "radix-cool-v4")
    #expect(!FocusTraceUXContract.timelineCurrentWorkflowOutlineEnabled)
}

@Test
func timelineLabelsAndEndpointHoursStayInsideThePlotAtNarrowWidths() {
    #expect(FocusTraceTimelineLayout.rowLabelWidth >= 76)
    #expect(FocusTraceTimelineLayout.rowSpacing == 10)

    let plotWidth = 240.0
    let centers = (0..<FocusTraceTimelineLayout.hourLabelCount).map {
        FocusTraceTimelineLayout.hourLabelCenterX(
            index: $0,
            availableWidth: plotWidth
        )
    }
    #expect(centers.first == FocusTraceTimelineLayout.endpointHourLabelInset)
    #expect(
        centers.last
            == plotWidth - FocusTraceTimelineLayout.endpointHourLabelInset
    )
    #expect(centers == centers.sorted())

    let veryNarrowWidth = 24.0
    let narrowCenters = (0..<FocusTraceTimelineLayout.hourLabelCount).map {
        FocusTraceTimelineLayout.hourLabelCenterX(
            index: $0,
            availableWidth: veryNarrowWidth
        )
    }
    #expect(narrowCenters.allSatisfy { $0 >= 0 && $0 <= veryNarrowWidth })
}

@Test
func disclosureButtonsExpandHitAreaWithoutChangingLayout() {
    #expect(FocusTraceDisclosureInteraction.hitTargetSize == 36)
    let opened = FocusTraceDisclosureInteraction.stateAfterHeaderPress(
        isExpanded: false
    )
    let closed = FocusTraceDisclosureInteraction.stateAfterHeaderPress(
        isExpanded: opened
    )
    #expect(opened)
    #expect(!closed)
}

@Test
func timelineSemanticPaletteSeparatesContextToolsAndRisk() {
    #expect(
        FocusTraceTimelinePalette.workflows.map(\.hexadecimalRGB)
            == [0x29A383, 0x00A2C7, 0x0090FF, 0x3E63DD, 0x5B5BD6]
    )
    #expect(
        FocusTraceTimelinePalette.applications.map(\.hexadecimalRGB)
            == [0x56BA9F, 0x3DB9CF, 0x5EB1EF, 0x8DA4EF, 0x9B9EF0]
    )
    #expect(
        FocusTraceTimelinePalette.densityScale.map(\.hexadecimalRGB)
            == [0x29A383, 0x00A2C7, 0xFFC53D, 0xE54D2E]
    )
    #expect(FocusTraceTimelinePalette.workflowOther.hexadecimalRGB == 0x8B8D98)
    #expect(FocusTraceTimelinePalette.applicationOther.hexadecimalRGB == 0xB9BBC6)
}

@Test
func timelineCurrentWorkflowDoesNotUseDarkSegmentOutlines() {
    #expect(!FocusTraceUXContract.timelineCurrentWorkflowOutlineEnabled)
}

@Test
func timelineCategoryColorsFollowRankAndCapAtFive() {
    let ranked = ["workflow-a", "workflow-b", "workflow-c", "workflow-d", "workflow-e", "workflow-f"]
    #expect(TimelineCategoryPaletteAssignment.maximumColoredCategories == 5)
    #expect(TimelineCategoryPaletteAssignment.index(for: "workflow-a", rankedIDs: ranked) == 0)
    #expect(TimelineCategoryPaletteAssignment.index(for: "workflow-e", rankedIDs: ranked) == 4)
    #expect(TimelineCategoryPaletteAssignment.index(for: "workflow-f", rankedIDs: ranked) == nil)
    #expect(TimelineCategoryPaletteAssignment.index(for: "unknown", rankedIDs: ranked) == nil)
}

@Test
func mainWindowContractRemainsSingleInstance() {
    #expect(FocusTraceWindowContract.mainWindowID == "main")
    #expect(!FocusTraceWindowContract.allowsMultipleMainWindows)
    #expect(!FocusTraceWindowContract.exposesDedicatedSettingsWindow)
}

@Test
func settingsDataControlsUseOneDeletionEntryWithTwoConfirmedScopes() {
    #expect(
        FocusTraceDataSettingsContract.rows
            == [.retention, .export, .deletion]
    )
    #expect(FocusTraceDataSettingsContract.visibleDeletionEntryCount == 1)
    #expect(FocusTraceDataSettingsContract.deletionScopeCount == 2)
    #expect(FocusTraceDataSettingsContract.destructiveActionsRequireConfirmation)
}

@Test
func gettingStartedFollowsCreateBindWorkReviewWithoutAddingInputs() {
    #expect(
        FocusTraceGettingStartedContract.steps.map(\.id)
            == [.createWorkflow, .bindDesktop, .workNormally, .reviewEvidence]
    )
    #expect(
        FocusTraceGettingStartedContract.phase(
            hasOpenWorkflow: false,
            requiresDesktopBinding: true,
            hasVerifiedDesktopBinding: false,
            hasRecordedActivity: false
        ) == .createWorkflow
    )
    #expect(
        FocusTraceGettingStartedContract.phase(
            hasOpenWorkflow: true,
            requiresDesktopBinding: true,
            hasVerifiedDesktopBinding: false,
            hasRecordedActivity: false
        ) == .bindDesktop
    )
    #expect(
        FocusTraceGettingStartedContract.phase(
            hasOpenWorkflow: true,
            requiresDesktopBinding: true,
            hasVerifiedDesktopBinding: true,
            hasRecordedActivity: false
        ) == .workNormally
    )
    #expect(
        FocusTraceGettingStartedContract.phase(
            hasOpenWorkflow: true,
            requiresDesktopBinding: true,
            hasVerifiedDesktopBinding: true,
            hasRecordedActivity: true
        ) == .reviewEvidence
    )
    #expect(
        FocusTraceGettingStartedContract.phase(
            hasOpenWorkflow: true,
            requiresDesktopBinding: false,
            hasVerifiedDesktopBinding: false,
            hasRecordedActivity: false
        ) == .workNormally
    )
    #expect(FocusTraceUXContract.onboardingRequiredInputs == ["workflowName"])
}

@Test
func timelineApplicationRunsMergeAdjacentDominantBuckets() {
    let start = Date(timeIntervalSince1970: 1_750_000_000)
    let codex = AppIdentity(bundleID: "com.openai.codex", name: "Codex")
    let lark = AppIdentity(bundleID: "com.larksuite.suite", name: "飞书")
    func bucket(
        offsetMinutes: Int,
        app: AppIdentity?,
        activeSeconds: TimeInterval
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
        bucket(offsetMinutes: 0, app: codex, activeSeconds: 280),
        bucket(offsetMinutes: 5, app: codex, activeSeconds: 260),
        bucket(offsetMinutes: 10, app: nil, activeSeconds: 0),
        bucket(offsetMinutes: 15, app: codex, activeSeconds: 240),
        bucket(offsetMinutes: 20, app: lark, activeSeconds: 220)
    ])

    #expect(runs.count == 3)
    #expect(runs[0].app == codex)
    #expect(runs[0].bucketCount == 2)
    #expect(runs[0].end == start.addingTimeInterval(10 * 60))
    #expect(runs[0].activeSeconds == 540)
    #expect(runs[1].app == codex)
    #expect(runs[1].bucketCount == 1)
    #expect(runs[2].app == lark)
}

@Test
func calendarLayoutIsPreparedBeforePresentationAndRemainsBounded() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let selected = calendar.date(from: DateComponents(
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
    let datedCells = selectedLayout.cells.compactMap(\.date)

    #expect(layouts.count == FocusTracePerformanceBudget.calendarMonthOffsets.count)
    #expect(elapsed < FocusTracePerformanceBudget.calendarLayoutMaximumSeconds)
    #expect(selectedLayout.weekdaySymbols.count == 7)
    #expect(selectedLayout.cells.count.isMultiple(of: 7))
    #expect(datedCells.count == 31)
    let dayTexts = selectedLayout.cells
        .filter { $0.date != nil }
        .map(\.dayText)
    #expect(dayTexts.first == "1")
    #expect(dayTexts.last == "31")

    let capped = FocusTraceCalendarLayoutEngine.movedMonth(
        from: selected,
        by: 1,
        latestDate: selected,
        calendar: calendar
    )
    #expect(capped == FocusTraceCalendarLayoutEngine.startOfMonth(
        containing: selected,
        calendar: calendar
    ))
}

@Test
func calendarPopoverAnchorPressesAlternateExactlyOnce() {
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

    #expect(opened)
    #expect(!closed)
    #expect(!remainsClosed)
}

@Test
func requirementCalendarBoundsAllowFutureAndRespectEarliestDate() {
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

    #expect(!FocusTraceCalendarBounds.isSelectable(
        previousDay,
        minimumDate: earliest,
        calendar: calendar
    ))
    #expect(FocusTraceCalendarBounds.isSelectable(
        earliest,
        minimumDate: earliest,
        calendar: calendar
    ))
    #expect(FocusTraceCalendarBounds.isSelectable(
        futureDay,
        minimumDate: earliest,
        calendar: calendar
    ))

    let currentMonth = FocusTraceCalendarLayoutEngine.startOfMonth(
        containing: earliest,
        calendar: calendar
    )
    #expect(
        FocusTraceCalendarBounds.movedMonth(
            from: currentMonth,
            by: -1,
            minimumDate: earliest,
            calendar: calendar
        ) == currentMonth
    )
    #expect(
        FocusTraceCalendarBounds.movedMonth(
            from: currentMonth,
            by: 1,
            minimumDate: earliest,
            calendar: calendar
        ) == FocusTraceCalendarLayoutEngine.startOfMonth(
            containing: futureDay,
            calendar: calendar
        )
    )
}

@Test
func requirementCaptureStaysInInboxUntilExplicitlyPlanned() throws {
    let captured = try #require(RequirementEngine.captured(
        title: "  张三口头说：补上失败告警  ",
        source: "  周会  "
    ))
    #expect(captured.title == "张三口头说：补上失败告警")
    #expect(captured.source == "周会")
    #expect(captured.status == .inbox)
    #expect(captured.priority == .unplanned)
    #expect(captured.importance == .normal)
    #expect(captured.workflowID == nil)
    #expect(RequirementEngine.needsPlanning(captured))

    let workflowID = UUID()
    let attached = RequirementEngine.attached(captured, to: workflowID)
    #expect(attached.workflowID == workflowID)
    #expect(attached.status == .inbox)
    #expect(attached.status != .active)
    #expect(RequirementEngine.needsPlanning(attached))
    #expect(
        RequirementEngine.suggestedWorkflowTitle(
            from: "修复训练失败后的告警。补充对应文档",
            maximumLength: 20
        ) == "修复训练失败后的告警"
    )
}

@Test
func requirementPlanningSeparatesDeadlineImportanceAndWorkflow() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let capturedAt = calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 25,
        hour: 10
    ))!
    let selectedDeadline = calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 27,
        hour: 18
    ))!
    let workflowID = UUID()
    let captured = try #require(RequirementEngine.captured(
        title: "补上失败告警",
        at: capturedAt
    ))

    let planned = RequirementEngine.planned(
        captured,
        dueDate: selectedDeadline,
        importance: .high,
        workflowID: workflowID,
        calendar: calendar
    )

    #expect(planned.dueDate == calendar.startOfDay(for: selectedDeadline))
    #expect(planned.importance == .high)
    #expect(planned.workflowID == workflowID)
    #expect(planned.priority == .unplanned)
    #expect(planned.status == .planned)
    #expect(!RequirementEngine.needsPlanning(planned))
    #expect(
        RequirementEngine.queueSection(
            for: planned,
            at: capturedAt,
            calendar: calendar
        ) == .upcoming
    )
}

@Test
func requirementCanStartWithoutPlanningAndCompletesIndependentlyInsideWorkflow() throws {
    let workflowID = UUID()
    let first = try #require(RequirementEngine.captured(title: "补上失败告警"))
    let second = try #require(RequirementEngine.captured(title: "补充运行手册"))
    let attachedFirst = RequirementEngine.attached(first, to: workflowID)
    let attachedSecond = RequirementEngine.attached(second, to: workflowID)

    let started = RequirementEngine.started(attachedFirst, in: workflowID)
    #expect(RequirementEngine.needsPlanning(started))
    #expect(started.status == .active)
    #expect(started.workflowID == workflowID)

    let completed = RequirementEngine.completed(
        started,
        at: Date(timeIntervalSince1970: 100)
    )
    #expect(completed.status == .completed)
    #expect(completed.workflowID == workflowID)
    #expect(attachedSecond.status == .inbox)
    #expect(attachedSecond.workflowID == workflowID)
}

@Test
func deletingWorkflowDetachesOnlyItsUnfinishedRequirements() throws {
    let workflowID = UUID()
    let otherWorkflowID = UUID()
    let active = RequirementEngine.started(
        try #require(RequirementEngine.captured(title: "正在做")),
        in: workflowID
    )
    let completed = RequirementEngine.completed(
        RequirementEngine.attached(
            try #require(RequirementEngine.captured(title: "已经做完")),
            to: workflowID
        )
    )
    let unrelated = RequirementEngine.attached(
        try #require(RequirementEngine.captured(title: "其他工作流")),
        to: otherWorkflowID
    )

    let detached = RequirementEngine.detachedFromWorkflow(
        active,
        workflowID: workflowID
    )
    #expect(detached.workflowID == nil)
    #expect(detached.status == .inbox)
    #expect(
        RequirementEngine.detachedFromWorkflow(
            completed,
            workflowID: workflowID
        ) == completed
    )
    #expect(
        RequirementEngine.detachedFromWorkflow(
            unrelated,
            workflowID: workflowID
        ) == unrelated
    )
}

@Test
func workflowNamesAreUniqueAfterWhitespaceCaseAndWidthNormalization() {
    #expect(
        WorkflowNamePolicy.normalizedTitle("  发布   FocusTrace  ")
            == "发布 FocusTrace"
    )
    #expect(!WorkflowNamePolicy.isAvailable(
        "发布  focustrace",
        among: ["发布 FocusTrace"]
    ))
    #expect(!WorkflowNamePolicy.isAvailable(
        "Ｆｏｃｕｓ Ｔｒａｃｅ",
        among: ["focus trace"]
    ))
    #expect(WorkflowNamePolicy.isAvailable(
        "发布 FocusTrace 2",
        among: ["发布 FocusTrace"]
    ))
}

@Test
func requirementQueueUsesUrgencyThenImportanceAndPreservesLegacyAmbiguity() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 25,
        hour: 10
    ))!
    let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
    let active = RequirementRecord(
        title: "正在处理",
        capturedAt: now,
        status: .active
    )
    let overdue = RequirementRecord(
        title: "已逾期",
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
    let upcoming = RequirementRecord(
        title: "未来",
        capturedAt: now,
        dueDate: tomorrow,
        importance: .high,
        status: .planned
    )
    let unscheduled = RequirementRecord(
        title: "无日期",
        capturedAt: now,
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
        [legacy, todayLow, upcoming, active, unscheduled, overdue, todayHigh],
        at: now,
        calendar: calendar
    )
    #expect(ordered.map(\.id) == [
        active.id,
        overdue.id,
        todayHigh.id,
        todayLow.id,
        upcoming.id,
        unscheduled.id,
        legacy.id
    ])
    #expect(
        RequirementEngine.queueSection(
            for: legacy,
            at: now,
            calendar: calendar
        ) == .needsPlanning
    )
    #expect(RequirementEngine.needsPlanning(legacyAttached))
    #expect(RequirementEngine.summary(ordered, at: now, calendar: calendar) ==
        RequirementQueueSummary(
            overdueCount: 1,
            dueTodayCount: 2,
            needsPlanningCount: 1
        )
    )
}

@Test
func requirementDueReminderIsOneShotAndOnlyForPlannedOpenWork() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 25,
        hour: 10
    ))!
    let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
    let overdue = RequirementRecord(
        title: "逾期",
        dueDate: yesterday,
        status: .planned
    )
    let dueToday = RequirementRecord(
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
    let future = RequirementRecord(
        title: "未来",
        dueDate: tomorrow,
        status: .planned
    )
    let active = RequirementRecord(
        title: "正在处理",
        dueDate: now,
        status: .active
    )
    let completed = RequirementRecord(
        title: "完成",
        dueDate: now,
        status: .completed
    )
    let legacy = RequirementRecord(
        title: "旧安排",
        dueDate: now,
        priority: .today,
        status: .planned
    )

    let due = RequirementEngine.dueForReminder(
        [alreadySent, future, completed, dueToday, legacy, active, overdue],
        at: now,
        calendar: calendar
    )
    #expect(Set(due.map(\.id)) == Set([overdue.id, dueToday.id]))

    let rescheduled = RequirementEngine.planned(
        alreadySent,
        dueDate: tomorrow,
        importance: alreadySent.importance,
        workflowID: alreadySent.workflowID,
        calendar: calendar
    )
    #expect(rescheduled.reminderSentAt == nil)
}

@Test
func requirementQueueHandlesOneThousandItemsWithinBudget() {
    let now = Date(timeIntervalSince1970: 1_000_000)
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
    let ordered = RequirementEngine.ordered(requirements, at: now)
    let elapsed = Date().timeIntervalSince(measuredAt)

    #expect(ordered.count == FocusTracePerformanceBudget.requirementQueueCount)
    #expect(elapsed < FocusTracePerformanceBudget.requirementQueueMaximumSeconds)
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
func timelinePresentationUsesMinuteRefreshAndHandlesLargeDaysQuickly() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = calendar.date(from: DateComponents(
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

    #expect(snapshot.buckets.count == 144)
    #expect(!snapshot.eventBuckets.isEmpty)
    #expect(
        snapshot.summary.appSwitchCount
            == FocusTracePerformanceBudget.timelineActivityCount - 1
    )
    #expect(elapsed < FocusTracePerformanceBudget.timelinePresentationMaximumSeconds)

    let firstTick = start.addingTimeInterval(12.1)
    let secondTick = start.addingTimeInterval(58.9)
    #expect(
        TimelinePresentationEngine.renderMinute(for: firstTick, calendar: calendar)
            == TimelinePresentationEngine.renderMinute(for: secondTick, calendar: calendar)
    )
}

@Test
func timelinePresentationCacheInvalidatesOnlyForMeaningfulChanges() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.date(from: DateComponents(
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

    #expect(first == sameMinute)
    #expect(first != nextMinute)
    #expect(first != changedData)
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

private func workflowTransition(
    at date: Date,
    origin: WorkflowTransitionEndpoint,
    destination: WorkflowTransitionEndpoint,
    outcome: WorkflowTransitionOutcome = .automatic,
    trigger: WorkflowInterventionTrigger? = nil,
    reason: SpaceSwitchReason? = nil
) -> WorkflowTransitionRecord {
    WorkflowTransitionRecord(
        navigationStartedAt: date.addingTimeInterval(-2),
        settledAt: date.addingTimeInterval(-0.5),
        resolvedAt: date,
        origin: origin,
        destination: destination,
        outcome: outcome,
        reason: reason ?? (outcome == .confirmed ? .reachedCheckpoint : nil),
        interventionTrigger: trigger,
        navigationEventCount: 1
    )
}

@Test
func workflowInterventionPromptsOnlyOnThirdSwitchAndThenCoolsDown() {
    let start = Date(timeIntervalSince1970: 80_000)
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
    let first = workflowTransition(
        at: start,
        origin: endpointA,
        destination: endpointB
    )
    let second = workflowTransition(
        at: start.addingTimeInterval(120),
        origin: endpointB,
        destination: endpointA
    )

    #expect(!WorkflowSwitchInterventionEngine.decision(
        history: [],
        origin: endpointA,
        destination: endpointB,
        at: start,
        isEnabled: true
    ).shouldPrompt)
    #expect(!WorkflowSwitchInterventionEngine.decision(
        history: [first],
        origin: endpointB,
        destination: endpointA,
        at: start.addingTimeInterval(120),
        isEnabled: true
    ).shouldPrompt)

    let thirdDecision = WorkflowSwitchInterventionEngine.decision(
        history: [first, second],
        origin: endpointA,
        destination: endpointB,
        at: start.addingTimeInterval(240),
        isEnabled: true
    )
    #expect(thirdDecision.shouldPrompt)
    #expect(thirdDecision.trigger == .frequentSwitchBurst)

    let prompted = workflowTransition(
        at: start.addingTimeInterval(240),
        origin: endpointA,
        destination: endpointB,
        outcome: .confirmed,
        trigger: .frequentSwitchBurst
    )
    #expect(!WorkflowSwitchInterventionEngine.decision(
        history: [first, second, prompted],
        origin: endpointB,
        destination: endpointA,
        at: start.addingTimeInterval(300),
        isEnabled: true
    ).shouldPrompt)
}

@Test
func workflowInterventionIgnoresUnboundOrDisabledTransitions() {
    let workflow = WorkflowTransitionEndpoint(
        kind: .workflow,
        workflowID: UUID()
    )
    let unbound = WorkflowTransitionEndpoint(kind: .unbound)
    #expect(!WorkflowSwitchInterventionEngine.decision(
        history: [],
        origin: workflow,
        destination: unbound,
        at: Date(),
        isEnabled: true
    ).shouldPrompt)
    #expect(!WorkflowSwitchInterventionEngine.decision(
        history: [],
        origin: workflow,
        destination: WorkflowTransitionEndpoint(
            kind: .workflow,
            workflowID: UUID()
        ),
        at: Date(),
        isEnabled: false
    ).shouldPrompt)
}

@Test
func workflowInterventionAuditMeasuresPromptAndFollowingQuietWindow() {
    let start = Date(timeIntervalSince1970: 82_000)
    let endpointA = WorkflowTransitionEndpoint(
        kind: .workflow,
        workflowID: UUID()
    )
    let endpointB = WorkflowTransitionEndpoint(
        kind: .workflow,
        workflowID: UUID()
    )
    let transitions = [
        workflowTransition(at: start, origin: endpointA, destination: endpointB),
        workflowTransition(
            at: start.addingTimeInterval(60),
            origin: endpointB,
            destination: endpointA
        ),
        workflowTransition(
            at: start.addingTimeInterval(120),
            origin: endpointA,
            destination: endpointB,
            outcome: .confirmed,
            trigger: .frequentSwitchBurst
        ),
    ]
    let audit = WorkflowSwitchInterventionEngine.audit(
        transitions: transitions,
        range: start..<start.addingTimeInterval(3_600),
        now: start.addingTimeInterval(900)
    )
    #expect(audit.frequentSwitchEpisodes == 1)
    #expect(audit.promptsShown == 1)
    #expect(audit.confirmedPrompts == 1)
    #expect(audit.quietAfterPromptRate == 1)
}

private func observationAnalysis(
    recordedMinutes: Double,
    reliable: Bool,
    baselineDays: Int = 3,
    appSwitchDelta: Double? = nil,
    workflowSwitchDelta: Double? = nil
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
            baselineDays: baselineDays,
            appSwitchRateDeltaPercent: appSwitchDelta,
            workflowSwitchRateDeltaPercent: workflowSwitchDelta,
            attributedRatioDeltaPoints: nil,
            medianFocusDeltaMinutes: nil
        ),
        recommendation: DailyCoachRecommendation(
            kind: .maintainRound,
            title: "保持",
            rationale: "测试",
            evidence: [],
            confidence: .medium,
            action: .none,
            method: DailyTrainingMethod(
                title: "测试",
                steps: [],
                successMeasure: "测试"
            )
        ),
        previousRecommendationEvaluation: nil
    )
}

private func observationSummary(
    parkings: Int = 0,
    resumed: Int = 0,
    resumeLatency: TimeInterval? = nil
) -> DailySummary {
    DailySummary(
        appSwitchCount: 0,
        taskSwitchCount: 0,
        workflowSwitchCount: 0,
        suspectedDistractionCount: 0,
        confirmedDistractionCount: 0,
        averageReturnLatency: nil,
        medianFocusStreak: nil,
        taskParkingCount: parkings,
        resumedTaskCount: resumed,
        averageTaskResumeLatency: resumeLatency,
        appDurations: [:],
        taskDurations: [:]
    )
}

private func observationAudit(
    episodes: Int = 0,
    assessed: Int = 0,
    quiet: Int = 0
) -> WorkflowInterventionAudit {
    WorkflowInterventionAudit(
        frequentSwitchEpisodes: episodes,
        promptsShown: assessed,
        confirmedPrompts: assessed,
        timedOutPrompts: 0,
        assessedPrompts: assessed,
        quietAfterPromptCount: quiet
    )
}

private func reliableSwitchingLoadQuality() -> DailyDataQuality {
    DailyDataQuality(
        isReliableForBehavior: true,
        warnings: [],
        analysisScopes: ObservationLens.allCases.map {
            DailyAnalysisScopeReliability(
                lens: $0,
                isReliable: true,
                reason: "测试样本可靠"
            )
        }
    )
}

private func switchingLoadTransitionAudit(
    routes: [AutomationWorkflowTransitionRouteArtifact] = [],
    explicitReasonCoverage: Double? = nil
) -> AutomationWorkflowTransitionAuditArtifact {
    AutomationWorkflowTransitionAuditArtifact(
        protocolVersion: 2,
        dataSource: "semanticEvents",
        finalSwitches: routes.reduce(0) { $0 + $1.count },
        explicitReasonSwitches: routes.reduce(0) { $0 + $1.count },
        timedOutSwitches: 0,
        automaticSwitches: 0,
        unresolvedNavigations: 0,
        explicitReasonCoverage: explicitReasonCoverage,
        reasonedSwitches: routes.reduce(0) { $0 + $1.count },
        unreasonedSwitches: 0,
        cancelledNavigations: 0,
        reasonCounts: [:],
        routes: routes
    )
}

private func dashboardAnalysis(
    reliableLenses: Set<ObservationLens> = Set(ObservationLens.allCases),
    baselineDays: Int = 5,
    appSwitchDelta: Double? = 10,
    medianFocusDelta: Double? = 3,
    medianFocusMinutes: Double? = 20,
    trainingCount: Int = 5,
    successfulTrainingCount: Int = 4,
    feedbackCompletionRatio: Double? = 1
) -> DailyCoachingAnalysis {
    DailyCoachingAnalysis(
        metrics: DailyNormalizedMetrics(
            recordedMinutes: 240,
            attributedMinutes: 220,
            attributedRatio: 0.92,
            appSwitchesPerHour: 8,
            workflowSwitchesPerHour: 2,
            medianFocusMinutes: medianFocusMinutes,
            trainingCount: trainingCount,
            successfulTrainingCount: successfulTrainingCount,
            feedbackCompletionRatio: feedbackCompletionRatio,
            parkingCount: 2
        ),
        quality: DailyDataQuality(
            isReliableForBehavior: !reliableLenses.isEmpty,
            warnings: [],
            analysisScopes: ObservationLens.allCases.map {
                DailyAnalysisScopeReliability(
                    lens: $0,
                    isReliable: reliableLenses.contains($0),
                    reason: reliableLenses.contains($0) ? "样本可靠" : "样本不足"
                )
            }
        ),
        trend: DailyTrendComparison(
            baselineDays: baselineDays,
            appSwitchRateDeltaPercent: appSwitchDelta,
            workflowSwitchRateDeltaPercent: 5,
            attributedRatioDeltaPoints: 2,
            medianFocusDeltaMinutes: medianFocusDelta
        ),
        recommendation: DailyCoachRecommendation(
            kind: .maintainRound,
            title: "保持当前训练",
            rationale: "测试",
            evidence: [],
            confidence: .high,
            action: .none,
            method: DailyTrainingMethod(
                title: "测试",
                steps: [],
                successMeasure: "测试"
            )
        ),
        previousRecommendationEvaluation: nil
    )
}

private func dashboardSwitchingLoad(
    status: SwitchingLoadStatus = .stable,
    withinWorkflowRatio: Double = 0.4,
    highFragmentationWindows: Int = 2,
    finalSwitches: Int = 4,
    plannedSwitches: Int = 3,
    burdenSwitches: Int = 0,
    resumeRate: Double? = 0.5,
    averageDifficulty: Double? = 2.5,
    difficultySamples: Int = 5,
    successRate: Double? = 0.8
) -> SwitchingLoadAssessment {
    SwitchingLoadAssessment(
        status: status,
        confidence: .high,
        headline: "测试",
        convergingSignals: [],
        evidence: [],
        recommendedExperiment: "测试",
        metrics: SwitchingLoadMetrics(
            activeMinutes: 240,
            appSwitchesPerHour: 8,
            withinWorkflowAppSwitchRatio: withinWorkflowRatio,
            peakFiveMinuteAppSwitches: 7,
            highFragmentationWindows: highFragmentationWindows,
            activeFiveMinuteWindows: 40,
            finalWorkflowSwitches: finalSwitches,
            plannedWorkflowSwitches: plannedSwitches,
            highRecoveryBurdenSwitches: burdenSwitches,
            navigationEventsPerBurst: 1.5,
            explicitReasonCoverage: 1,
            shortDestinationSwitches: burdenSwitches,
            returnedWithin30Minutes: burdenSwitches,
            returnPointResumeRate: resumeRate,
            averageInterruptionReturnSeconds: 75,
            averageSubjectiveDifficulty: averageDifficulty,
            subjectiveDifficultySamples: difficultySamples,
            focusSuccessRate: successRate,
            comparableBaselineDays: 5,
            systemInactiveMinutes: 30
        ),
        traceCoverage: []
    )
}

private func dashboardDay(
    date: Date,
    isPartial: Bool = false,
    medianFocusMinutes: Double? = 20,
    highFragmentationWindows: Int = 4,
    withinWorkflowRatio: Double = 0.3,
    finalSwitches: Int = 4,
    burdenSwitches: Int = 0,
    resumeRate: Double? = 0.8,
    parkings: Int = 2,
    sessions: [FocusSessionRecord] = []
) -> AttentionDashboardDay {
    let successful = sessions.filter(\.isSuccessful).count
    let feedbackCount = sessions.compactMap(\.difficulty).count
    let feedbackRatio = sessions.isEmpty
        ? nil
        : Double(feedbackCount) / Double(sessions.count)
    let averageDifficulty = sessions.compactMap(\.difficulty).isEmpty
        ? nil
        : Double(sessions.compactMap(\.difficulty).reduce(0, +))
            / Double(feedbackCount)
    return AttentionDashboardDay(
        date: date,
        isPartial: isPartial,
        coaching: dashboardAnalysis(
            medianFocusMinutes: medianFocusMinutes,
            trainingCount: sessions.count,
            successfulTrainingCount: successful,
            feedbackCompletionRatio: feedbackRatio
        ),
        summary: observationSummary(
            parkings: parkings,
            resumed: resumeRate.map {
                Int((Double(parkings) * $0).rounded())
            } ?? 0,
            resumeLatency: 8 * 60
        ),
        switchingLoad: dashboardSwitchingLoad(
            withinWorkflowRatio: withinWorkflowRatio,
            highFragmentationWindows: highFragmentationWindows,
            finalSwitches: finalSwitches,
            burdenSwitches: burdenSwitches,
            resumeRate: resumeRate,
            averageDifficulty: averageDifficulty,
            difficultySamples: feedbackCount,
            successRate: sessions.isEmpty
                ? nil
                : Double(successful) / Double(sessions.count)
        ),
        interventionAudit: observationAudit(),
        focusSessions: sessions
    )
}

private func dashboardSession(
    date: Date,
    successful: Bool,
    difficulty: Int
) -> FocusSessionRecord {
    FocusSessionRecord(
        taskID: UUID(),
        startedAt: date.addingTimeInterval(9 * 60 * 60),
        endedAt: date.addingTimeInterval(
            9 * 60 * 60 + (successful ? 15 * 60 : 5 * 60)
        ),
        targetSeconds: 15 * 60,
        outcome: successful ? .completed : .notCompleted,
        difficulty: difficulty,
        confirmedDistractionCount: 0
    )
}

@Test
func attentionDashboardKeepsFiveIndependentDimensionsWithoutACompositeScore() {
    let dashboard = AttentionDashboardEngine.make(
        coaching: dashboardAnalysis(),
        summary: observationSummary(
            parkings: 2,
            resumed: 1,
            resumeLatency: 8 * 60
        ),
        switchingLoad: dashboardSwitchingLoad(),
        interventionAudit: observationAudit(
            episodes: 2,
            assessed: 1,
            quiet: 1
        )
    )

    #expect(dashboard.metrics.map(\.kind) == AttentionDashboardMetricKind.allCases)
    #expect(dashboard.reliableDimensionCount == 5)
    #expect(dashboard.boundary.contains("不合成为"))
    #expect(!dashboard.boundary.contains("脑负荷分数"))
    let switching = dashboard.metrics.first { $0.kind == .switchingBoundary }
    #expect(switching?.evidence.contains { $0.contains("高频段 2") } == true)
    #expect(switching?.evidence.contains { $0.contains("确认后稳定 100%") } == true)
}

@Test
func attentionDashboardDoesNotCallSameWorkflowToolSwitchesAttentionFailure() {
    let dashboard = AttentionDashboardEngine.make(
        coaching: dashboardAnalysis(appSwitchDelta: 60),
        summary: observationSummary(),
        switchingLoad: dashboardSwitchingLoad(withinWorkflowRatio: 0.85),
        interventionAudit: observationAudit()
    )
    let fragmentation = dashboard.metrics.first { $0.kind == .fragmentation }

    #expect(fragmentation?.state == .observed)
    #expect(fragmentation?.comparison.contains("同工作流工具协作") == true)
    #expect(fragmentation?.evidence.contains { $0.contains("不直接等于分心") } == true)
}

@Test
func attentionDashboardStillFlagsConcentratedFragmentationAgainstAHighBaseline() {
    let dashboard = AttentionDashboardEngine.make(
        coaching: dashboardAnalysis(appSwitchDelta: -12),
        summary: observationSummary(),
        switchingLoad: dashboardSwitchingLoad(
            withinWorkflowRatio: 0.3,
            highFragmentationWindows: 30
        ),
        interventionAudit: observationAudit()
    )
    let fragmentation = dashboard.metrics.first { $0.kind == .fragmentation }

    #expect(fragmentation?.state == .needsAttention)
    #expect(fragmentation?.comparison.contains("75%") == true)
}

@Test
func attentionDashboardGatesEachDimensionIndependently() {
    let dashboard = AttentionDashboardEngine.make(
        coaching: dashboardAnalysis(
            reliableLenses: [.contextRecovery],
            appSwitchDelta: nil,
            medianFocusDelta: nil
        ),
        summary: observationSummary(
            parkings: 2,
            resumed: 1,
            resumeLatency: 5 * 60
        ),
        switchingLoad: dashboardSwitchingLoad(),
        interventionAudit: observationAudit()
    )
    let states = Dictionary(
        uniqueKeysWithValues: dashboard.metrics.map { ($0.kind, $0.state) }
    )

    #expect(states[.sustainedProgress] == .unavailable)
    #expect(states[.fragmentation] == .unavailable)
    #expect(states[.switchingBoundary] == .unavailable)
    #expect(states[.contextRecovery] == .observed)
    #expect(states[.trainingFeedback] == .improving)
    #expect(dashboard.reliableDimensionCount == 2)
}

@Test
func attentionDashboardWaitsForFiveTrainingSamplesBeforeJudging() {
    let dashboard = AttentionDashboardEngine.make(
        coaching: dashboardAnalysis(
            trainingCount: 4,
            successfulTrainingCount: 4
        ),
        summary: observationSummary(),
        switchingLoad: dashboardSwitchingLoad(
            difficultySamples: 4,
            successRate: 1
        ),
        interventionAudit: observationAudit()
    )
    let training = dashboard.metrics.first { $0.kind == .trainingFeedback }

    #expect(training?.state == .calibrating)
    #expect(training?.evidence.contains { $0.contains("满 5 次") } == true)
}

@Test
func attentionDashboardUsesTenWorkdaysAndLinksTheExperimentToTheMainProblem() {
    let start = Date(timeIntervalSince1970: 2_000_000)
    let days = (0..<10).map { index in
        dashboardDay(
            date: start.addingTimeInterval(Double(index) * 86_400),
            medianFocusMinutes: index < 7 ? 20 : 10,
            highFragmentationWindows: index < 7 ? 4 : 20,
            withinWorkflowRatio: 0.3
        )
    }
    let dashboard = AttentionDashboardEngine.make(
        days: days,
        currentPlan: TrainingPlanRecord(
            version: 1,
            effectiveAt: start,
            focusMinutes: 20,
            reason: "测试"
        )
    )
    let fragmentation = dashboard.metrics.first {
        $0.kind == .fragmentation
    }
    let sustained = dashboard.metrics.first {
        $0.kind == .sustainedProgress
    }

    #expect(dashboard.version == 2)
    #expect(dashboard.baselineDays == 10)
    #expect(fragmentation?.trend?.direction == .worsening)
    #expect(sustained?.trend?.direction == .worsening)
    #expect(dashboard.finding?.kind == .fragmentation)
    #expect(dashboard.finding?.state == .needsAttention)
    #expect(dashboard.recommendation?.title.contains("单一产出") == true)
    #expect(
        dashboard.recommendation?.evidence
            == dashboard.finding?.evidence
    )
}

@Test
func attentionDashboardExcludesAnUnfinishedDayFromTrendConclusions() {
    let start = Date(timeIntervalSince1970: 3_000_000)
    let completed = (0..<9).map { index in
        dashboardDay(
            date: start.addingTimeInterval(Double(index) * 86_400),
            medianFocusMinutes: 20,
            highFragmentationWindows: 4
        )
    }
    let partial = dashboardDay(
        date: start.addingTimeInterval(9 * 86_400),
        isPartial: true,
        medianFocusMinutes: 2,
        highFragmentationWindows: 35
    )
    let dashboard = AttentionDashboardEngine.make(
        days: completed + [partial],
        currentPlan: TrainingPlanRecord(
            version: 1,
            effectiveAt: start,
            focusMinutes: 20,
            reason: "测试"
        )
    )

    #expect(dashboard.includesPartialDay == true)
    #expect(dashboard.finding?.state == .stable)
    #expect(
        dashboard.metrics.first { $0.kind == .fragmentation }?
            .trend?.direction == .stable
    )
}

@Test
func attentionDashboardDoesNotEscalateToolCollaborationAsFragmentation() {
    let start = Date(timeIntervalSince1970: 4_000_000)
    let days = (0..<10).map { index in
        dashboardDay(
            date: start.addingTimeInterval(Double(index) * 86_400),
            medianFocusMinutes: 20,
            highFragmentationWindows: index < 7 ? 4 : 20,
            withinWorkflowRatio: index < 7 ? 0.4 : 0.85
        )
    }
    let dashboard = AttentionDashboardEngine.make(
        days: days,
        currentPlan: TrainingPlanRecord(
            version: 1,
            effectiveAt: start,
            focusMinutes: 20,
            reason: "测试"
        )
    )
    let fragmentation = dashboard.metrics.first {
        $0.kind == .fragmentation
    }

    #expect(fragmentation?.trend?.direction == .stable)
    #expect(fragmentation?.comparison.contains("工具协作") == true)
    #expect(dashboard.finding?.state != .needsAttention)
}

@Test
func attentionDashboardEvaluatesTrainingAcrossDaysInRollingFiveSessions() {
    let start = Date(timeIntervalSince1970: 5_000_000)
    let days = (0..<5).map { index in
        let date = start.addingTimeInterval(Double(index) * 86_400)
        return dashboardDay(
            date: date,
            sessions: [
                dashboardSession(
                    date: date,
                    successful: index == 0,
                    difficulty: 4
                )
            ]
        )
    }
    let dashboard = AttentionDashboardEngine.make(
        days: days,
        currentPlan: TrainingPlanRecord(
            version: 1,
            effectiveAt: start,
            focusMinutes: 20,
            reason: "测试"
        )
    )
    let training = dashboard.metrics.first { $0.kind == .trainingFeedback }

    #expect(training?.trend?.reliableDayCount == 5)
    #expect(training?.trend?.recentMedian == 20)
    #expect(training?.state == .needsAttention)
    #expect(dashboard.finding?.kind == .trainingFeedback)
    #expect(dashboard.recommendation?.title.contains("5 次训练") == true)
}

@Test
func attentionDashboardDoesNotEscalateFragmentationWithoutAConsequence() {
    let start = Date(timeIntervalSince1970: 6_000_000)
    let days = (0..<10).map { index in
        dashboardDay(
            date: start.addingTimeInterval(Double(index) * 86_400),
            medianFocusMinutes: 20,
            highFragmentationWindows: index < 7 ? 4 : 20,
            withinWorkflowRatio: 0.3
        )
    }
    let dashboard = AttentionDashboardEngine.make(
        days: days,
        currentPlan: TrainingPlanRecord(
            version: 1,
            effectiveAt: start,
            focusMinutes: 20,
            reason: "测试"
        )
    )

    #expect(dashboard.finding?.state == .stable)
    #expect(dashboard.finding?.title.contains("没有出现恢复后果") == true)
    #expect(dashboard.recommendation?.action == DailyCoachAction.none)
}

@Test
func switchingLoadRefusesABrainLoadClaimWhenBehaviorDataIsUnreliable() {
    let start = Date(timeIntervalSince1970: 210_000)
    let range = DateInterval(start: start, duration: 60 * 60)
    let assessment = SwitchingLoadEngine.assess(
        activities: [
            ActivityRecord(
                app: AppIdentity(bundleID: "app", name: "App"),
                startedAt: start,
                endedAt: range.end,
                taskID: UUID(),
                focusSessionID: nil,
                classification: .allowed
            )
        ],
        taskIntervals: [],
        focusSessions: [],
        interruptions: [],
        workflowTransitions: [],
        taskParkings: [],
        markers: [],
        workflowContextCount: 0,
        range: range,
        now: range.end,
        quality: DailyDataQuality(
            isReliableForBehavior: false,
            warnings: ["样本不足"]
        ),
        trend: DailyTrendComparison(
            baselineDays: 5,
            appSwitchRateDeltaPercent: 100,
            workflowSwitchRateDeltaPercent: 100,
            attributedRatioDeltaPoints: nil,
            medianFocusDeltaMinutes: nil
        ),
        transitionAudit: switchingLoadTransitionAudit()
    )

    #expect(assessment.status == .unavailable)
    #expect(assessment.headline.contains("不能据此判断"))
    #expect(assessment.boundary.contains("不是脑活动"))
    #expect(
        assessment.traceCoverage.first {
            $0.family == .semanticTransitions
        }?.status == .qualityBlocked
    )
}

@Test
func sameWorkflowToolSwitchesRemainAQualifiedSignalNotAnOverloadVerdict() {
    let start = Date(timeIntervalSince1970: 220_000)
    let workflowID = UUID()
    let range = DateInterval(start: start, duration: 60 * 60)
    let apps = (0..<7).map { index in
        ActivityRecord(
            app: AppIdentity(
                bundleID: index.isMultiple(of: 2) ? "editor" : "terminal",
                name: index.isMultiple(of: 2) ? "Editor" : "Terminal"
            ),
            startedAt: start.addingTimeInterval(Double(index) * 8 * 60),
            endedAt: start.addingTimeInterval(Double(index + 1) * 8 * 60),
            taskID: workflowID,
            focusSessionID: nil,
            classification: .allowed
        )
    }
    let sessions = (0..<3).map { index in
        FocusSessionRecord(
            taskID: workflowID,
            startedAt: start.addingTimeInterval(Double(index) * 20 * 60),
            endedAt: start.addingTimeInterval(Double(index) * 20 * 60 + 15 * 60),
            targetSeconds: 15 * 60,
            outcome: .completed,
            difficulty: 2,
            confirmedDistractionCount: 0
        )
    }

    let assessment = SwitchingLoadEngine.assess(
        activities: apps,
        taskIntervals: [
            TaskIntervalRecord(
                taskID: workflowID,
                startedAt: start,
                endedAt: range.end,
                workflowSource: .manual
            )
        ],
        focusSessions: sessions,
        interruptions: [],
        workflowTransitions: [],
        taskParkings: [],
        markers: [],
        workflowContextCount: 1,
        range: range,
        now: range.end,
        quality: reliableSwitchingLoadQuality(),
        trend: DailyTrendComparison(
            baselineDays: 5,
            appSwitchRateDeltaPercent: 40,
            workflowSwitchRateDeltaPercent: 35,
            attributedRatioDeltaPoints: nil,
            medianFocusDeltaMinutes: nil
        ),
        transitionAudit: switchingLoadTransitionAudit()
    )

    #expect(assessment.status == .mixedEvidence)
    #expect(assessment.convergingSignals.count == 2)
    #expect(assessment.metrics.withinWorkflowAppSwitchRatio == 1)
    #expect(assessment.recommendedExperiment.contains("不减少同一工作流"))
    #expect(!assessment.headline.contains("脑"))
}

@Test
func switchingLoadRequiresConvergingBehaviorRecoveryAndSubjectiveEvidence() {
    let start = Date(timeIntervalSince1970: 230_000)
    let workflowA = UUID()
    let workflowB = UUID()
    let range = DateInterval(start: start, duration: 60 * 60)
    let endpointA = WorkflowTransitionEndpoint(
        kind: .workflow,
        workflowID: workflowA
    )
    let endpointB = WorkflowTransitionEndpoint(
        kind: .workflow,
        workflowID: workflowB
    )
    let transitions = [
        workflowTransition(
            at: start.addingTimeInterval(10 * 60),
            origin: endpointA,
            destination: endpointB,
            outcome: .confirmed,
            reason: .forcedInterruption
        ),
        workflowTransition(
            at: start.addingTimeInterval(30 * 60),
            origin: endpointA,
            destination: endpointB,
            outcome: .confirmed,
            reason: .forcedInterruption
        )
    ]
    let route = AutomationWorkflowTransitionRouteArtifact(
        fromWorkflow: "A",
        toWorkflow: "B",
        count: 2,
        reasonCounts: ["forcedInterruption": 2],
        medianDestinationMinutes: 3,
        returnedWithin30Minutes: 2,
        timeBucketCounts: ["morning": 2],
        outcomeCounts: ["confirmed": 2]
    )
    let sessions = (0..<3).map { index in
        FocusSessionRecord(
            taskID: workflowA,
            startedAt: start.addingTimeInterval(Double(index) * 20 * 60),
            endedAt: start.addingTimeInterval(Double(index) * 20 * 60 + 10 * 60),
            targetSeconds: 15 * 60,
            outcome: .partial,
            difficulty: 4,
            confirmedDistractionCount: 0
        )
    }
    let activities = (0..<8).map { index in
        ActivityRecord(
            app: AppIdentity(
                bundleID: index.isMultiple(of: 2) ? "a" : "b",
                name: index.isMultiple(of: 2) ? "A" : "B"
            ),
            startedAt: start.addingTimeInterval(Double(index) * 7 * 60),
            endedAt: start.addingTimeInterval(Double(index + 1) * 7 * 60),
            taskID: index < 4 ? workflowA : workflowB,
            focusSessionID: nil,
            classification: .allowed
        )
    }

    let assessment = SwitchingLoadEngine.assess(
        activities: activities,
        taskIntervals: [
            TaskIntervalRecord(
                taskID: workflowA,
                startedAt: start,
                endedAt: start.addingTimeInterval(30 * 60),
                workflowSource: .space
            ),
            TaskIntervalRecord(
                taskID: workflowB,
                startedAt: start.addingTimeInterval(30 * 60),
                endedAt: range.end,
                workflowSource: .space
            )
        ],
        focusSessions: sessions,
        interruptions: [],
        workflowTransitions: transitions,
        taskParkings: [],
        markers: [],
        workflowContextCount: 2,
        range: range,
        now: range.end,
        quality: reliableSwitchingLoadQuality(),
        trend: DailyTrendComparison(
            baselineDays: 5,
            appSwitchRateDeltaPercent: 35,
            workflowSwitchRateDeltaPercent: 30,
            attributedRatioDeltaPoints: nil,
            medianFocusDeltaMinutes: nil
        ),
        transitionAudit: switchingLoadTransitionAudit(
            routes: [route],
            explicitReasonCoverage: 1
        )
    )

    #expect(assessment.status == .elevated)
    #expect(assessment.convergingSignals.count >= 3)
    #expect(assessment.metrics.highRecoveryBurdenSwitches == 2)
    #expect(assessment.metrics.returnedWithin30Minutes == 2)
    #expect(assessment.recommendedExperiment.contains("回来先做什么"))
    #expect(
        Set(assessment.traceCoverage.map(\.family))
            == Set(SwitchingLoadTraceFamily.allCases)
    )
}

@Test
func observationPlanStartsBalancedAndReallocatesOnlyAnalysisAttention() {
    let initial = ObservationPlanEngine.makePlan(
        coaching: observationAnalysis(recordedMinutes: 0, reliable: false),
        summary: observationSummary(),
        interventionAudit: observationAudit()
    )
    #expect(initial.source == .initialDefault)
    #expect(initial.allocations.map(\.percent) == [25, 25, 25, 25])
    #expect(initial.rawCollectionMode == .minimalEventDrivenFixed)

    let unreliable = ObservationPlanEngine.makePlan(
        coaching: observationAnalysis(recordedMinutes: 60, reliable: false),
        summary: observationSummary(),
        interventionAudit: observationAudit()
    )
    #expect(unreliable.primaryAllocation?.lens == .dataQuality)
    #expect(unreliable.primaryAllocation?.percent == 70)

    let semantic = ObservationPlanEngine.makePlan(
        coaching: observationAnalysis(recordedMinutes: 60, reliable: true),
        summary: observationSummary(),
        interventionAudit: observationAudit(episodes: 1)
    )
    #expect(semantic.primaryAllocation?.lens == .workflowSemantics)
    #expect(semantic.allocations.reduce(0) { $0 + $1.percent } == 100)

    let recovery = ObservationPlanEngine.makePlan(
        coaching: observationAnalysis(recordedMinutes: 60, reliable: true),
        summary: observationSummary(parkings: 2, resumed: 1),
        interventionAudit: observationAudit()
    )
    #expect(recovery.primaryAllocation?.lens == .contextRecovery)

    let weakPrompt = ObservationPlanEngine.makePlan(
        coaching: observationAnalysis(recordedMinutes: 60, reliable: true),
        summary: observationSummary(),
        interventionAudit: observationAudit(
            episodes: 5,
            assessed: 5,
            quiet: 1
        )
    )
    #expect(weakPrompt.interventionRecommendation.contains("不增加弹窗"))
}

@Test
func workflowInterventionConfigurationIsExplicitAndInjectable() {
    let start = Date(timeIntervalSince1970: 84_000)
    let endpointA = WorkflowTransitionEndpoint(
        kind: .workflow,
        workflowID: UUID()
    )
    let endpointB = WorkflowTransitionEndpoint(
        kind: .workflow,
        workflowID: UUID()
    )
    let configuration = WorkflowInterventionConfiguration(
        version: 99,
        windowSeconds: 300,
        switchThreshold: 2,
        cooldownSeconds: 600,
        minimumBaselineWorkdays: 3,
        minimumAssessmentWindows: 5
    )
    let first = workflowTransition(
        at: start,
        origin: endpointA,
        destination: endpointB
    )
    let decision = WorkflowSwitchInterventionEngine.decision(
        history: [first],
        origin: endpointB,
        destination: endpointA,
        at: start.addingTimeInterval(60),
        isEnabled: true,
        configuration: configuration
    )
    #expect(decision.shouldPrompt)
    #expect(WorkflowInterventionConfiguration.initial.switchThreshold == 3)
}

@Test
func spaceSwitchGateRequiresMeaningfulVerifiedDeparture() {
    let workflowA = UUID()
    let workflowB = UUID()
    let now = Date(timeIntervalSince1970: 90_000)

    #expect(SpaceSwitchGateEngine.begin(
        origin: .bound(workflowID: workflowA),
        destination: .bound(workflowID: workflowB),
        at: now,
        isEnabled: true
    ) != nil)
    #expect(SpaceSwitchGateEngine.begin(
        origin: .bound(workflowID: workflowA),
        destination: .unbound,
        at: now,
        isEnabled: true
    ) != nil)
    #expect(SpaceSwitchGateEngine.begin(
        origin: .bound(workflowID: workflowA),
        destination: .bound(workflowID: workflowA),
        at: now,
        isEnabled: true
    ) == nil)
    #expect(SpaceSwitchGateEngine.begin(
        origin: .unbound,
        destination: .bound(workflowID: workflowB),
        at: now,
        isEnabled: true
    ) != nil)
    #expect(SpaceSwitchGateEngine.begin(
        origin: .unbound,
        destination: .unbound,
        at: now,
        isEnabled: true
    ) == nil)
    #expect(SpaceSwitchGateEngine.begin(
        origin: .bound(workflowID: workflowA),
        destination: .unknown,
        at: now,
        isEnabled: true
    ) == nil)
    #expect(SpaceSwitchGateEngine.begin(
        origin: .bound(workflowID: workflowA),
        destination: .conflict(workflowIDs: [workflowA, workflowB]),
        at: now,
        isEnabled: true
    ) == nil)
    #expect(SpaceSwitchGateEngine.begin(
        origin: .bound(workflowID: workflowA),
        destination: .bound(workflowID: workflowB),
        at: now,
        isEnabled: false
    ) == nil)
}

@Test
func spaceSwitchJourneyKeepsTheFirstWorkflowAndOnlyUsesTheFinalDestination() {
    let workflowA = UUID()
    let workflowB = UUID()
    let workflowC = UUID()
    let start = Date(timeIntervalSince1970: 90_500)

    let first = SpaceSwitchJourneyEngine.beginOrExtend(
        nil,
        origin: .bound(workflowID: workflowA),
        at: start
    )!
    let throughB = SpaceSwitchJourneyEngine.beginOrExtend(
        first,
        origin: .unknown,
        candidateDestination: .bound(workflowID: workflowB),
        at: start.addingTimeInterval(0.4)
    )!
    let finalC = SpaceSwitchJourneyEngine.beginOrExtend(
        throughB,
        origin: .unknown,
        candidateDestination: .bound(workflowID: workflowC),
        at: start.addingTimeInterval(0.8)
    )!

    #expect(finalC.origin == .bound(workflowID: workflowA))
    #expect(finalC.candidateDestination == .bound(workflowID: workflowC))
    #expect(finalC.startedAt == start)
    #expect(finalC.lastChangedAt == start.addingTimeInterval(0.8))
    #expect(finalC.eventCount == 3)
    #expect(
        SpaceSwitchJourneyEngine.finish(
            finalC,
            finalDestination: .bound(workflowID: workflowC),
            at: start.addingTimeInterval(1.9),
            isGateEnabled: true
        ) == .notSettled
    )

    guard case let .presentGate(pending) = SpaceSwitchJourneyEngine.finish(
        finalC,
        finalDestination: .bound(workflowID: workflowC),
        at: start.addingTimeInterval(2.0),
        isGateEnabled: true
    ) else {
        Issue.record("最后一次变化稳定 1.2 秒后应只为最终工作流弹一次")
        return
    }
    #expect(pending.origin == .bound(workflowID: workflowA))
    #expect(pending.destination == .bound(workflowID: workflowC))
    #expect(pending.startedAt == start.addingTimeInterval(2.0))
}

@Test
func spaceSwitchJourneyCancelsWhenTheFinalWorkflowIsTheOrigin() {
    let workflowA = UUID()
    let workflowB = UUID()
    let start = Date(timeIntervalSince1970: 90_700)
    let journey = SpaceSwitchJourneyEngine.beginOrExtend(
        nil,
        origin: .bound(workflowID: workflowA),
        candidateDestination: .bound(workflowID: workflowB),
        at: start
    )!

    #expect(
        SpaceSwitchJourneyEngine.finish(
            journey,
            finalDestination: .bound(workflowID: workflowA),
            at: start.addingTimeInterval(1.2),
            isGateEnabled: true
        ) == .unchanged(.bound(workflowID: workflowA))
    )
    #expect(
        SpaceSwitchJourneyEngine.finish(
            journey,
            finalDestination: .bound(workflowID: workflowB),
            at: start.addingTimeInterval(1.2),
            isGateEnabled: false
        ) == .applyWithoutGate(.bound(workflowID: workflowB))
    )
}

@Test
func spaceSwitchGateReturnsToOriginAndUpdatesDestinationSafely() {
    let workflowA = UUID()
    let workflowB = UUID()
    let workflowC = UUID()
    let now = Date(timeIntervalSince1970: 91_000)
    let pending = SpaceSwitchGateEngine.begin(
        origin: .bound(workflowID: workflowA),
        destination: .bound(workflowID: workflowB),
        at: now,
        isEnabled: true
    )!

    #expect(SpaceSwitchGateEngine.observe(
        .bound(workflowID: workflowA),
        while: pending
    ) == .returnedToOrigin)
    #expect(SpaceSwitchGateEngine.observe(
        .bound(workflowID: workflowB),
        while: pending
    ) == .stayedOnDestination)
    #expect(SpaceSwitchGateEngine.observe(
        .unknown,
        while: pending
    ) == .cannotResolve(.unknown))

    let changed = SpaceSwitchGateEngine.observe(
        .bound(workflowID: workflowC),
        while: pending
    )
    guard case let .destinationChanged(updated) = changed else {
        Issue.record("切到第三个桌面时应更新目标，而不是丢失最初工作流")
        return
    }
    #expect(updated.origin == pending.origin)
    #expect(updated.destination == .bound(workflowID: workflowC))
    #expect(updated.startedAt == pending.startedAt)
    #expect(updated.expiresAt == pending.expiresAt)
}

@Test
func spaceSwitchGateExpiresWithoutLockingTheUser() {
    let now = Date(timeIntervalSince1970: 92_000)
    let pending = SpaceSwitchGateEngine.begin(
        origin: .bound(workflowID: UUID()),
        destination: .unbound,
        at: now,
        isEnabled: true
    )!

    #expect(!SpaceSwitchGateEngine.hasExpired(
        pending,
        at: now.addingTimeInterval(9.9)
    ))
    #expect(SpaceSwitchGateEngine.hasExpired(
        pending,
        at: now.addingTimeInterval(10)
    ))
    #expect(
        pending.expiresAt.timeIntervalSince(pending.startedAt)
            == SpaceSwitchGateEngine.decisionWindowSeconds
    )
}

@Test
func spaceSwitchGateRefreshesAFullDecisionWindowAfterNavigationSettles() {
    let workflowA = UUID()
    let workflowB = UUID()
    let workflowC = UUID()
    let start = Date(timeIntervalSince1970: 92_500)
    let pending = SpaceSwitchGateEngine.begin(
        origin: .bound(workflowID: workflowA),
        destination: .bound(workflowID: workflowB),
        at: start,
        isEnabled: true
    )!
    let settledAt = start.addingTimeInterval(4)
    let refreshed = SpaceSwitchGateEngine.refreshed(
        pending,
        destination: .bound(workflowID: workflowC),
        at: settledAt
    )

    #expect(refreshed?.origin == .bound(workflowID: workflowA))
    #expect(refreshed?.destination == .bound(workflowID: workflowC))
    #expect(refreshed?.startedAt == settledAt)
    #expect(
        refreshed?.expiresAt
            == settledAt.addingTimeInterval(
                SpaceSwitchGateEngine.decisionWindowSeconds
            )
    )
    #expect(SpaceSwitchGateEngine.refreshed(
        pending,
        destination: .bound(workflowID: workflowA),
        at: settledAt
    ) == nil)
}

@Test
func workflowTransitionKeepsCompleteNativeSemantics() {
    let workflowA = UUID()
    let workflowB = UUID()
    let start = Date(timeIntervalSince1970: 93_000)
    let pending = PendingWorkflowTransition(
        navigationStartedAt: start,
        origin: WorkflowTransitionEndpoint(
            resolution: .bound(workflowID: workflowA)
        ),
        destination: WorkflowTransitionEndpoint(
            resolution: .bound(workflowID: workflowB)
        ),
        settledAt: start.addingTimeInterval(1.2),
        navigationEventCount: 3
    )
    let record = pending.resolved(
        at: start.addingTimeInterval(5),
        outcome: .confirmed,
        reason: .waitingForResult
    )

    #expect(record.origin.workflowID == workflowA)
    #expect(record.destination.workflowID == workflowB)
    #expect(record.outcome == .confirmed)
    #expect(record.reason == .waitingForResult)
    #expect(record.navigationEventCount == 3)
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
func workflowAttributionRecoversOnlyUnambiguousExplicitTrace() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 9))!
    let workflowA = UUID()
    let workflowB = UUID()
    let focusID = UUID()
    let app = AppIdentity(bundleID: "app", name: "App")
    let activities = [
        ActivityRecord(app: app, startedAt: day, endedAt: day.addingTimeInterval(10 * 60), taskID: workflowA, focusSessionID: nil, classification: .allowed),
        ActivityRecord(app: app, startedAt: day.addingTimeInterval(10 * 60), endedAt: day.addingTimeInterval(30 * 60), taskID: nil, focusSessionID: nil, classification: .allowed),
        ActivityRecord(app: app, startedAt: day.addingTimeInterval(30 * 60), endedAt: day.addingTimeInterval(40 * 60), taskID: nil, focusSessionID: focusID, classification: .allowed),
        ActivityRecord(app: app, startedAt: day.addingTimeInterval(40 * 60), endedAt: day.addingTimeInterval(50 * 60), taskID: nil, focusSessionID: nil, classification: .allowed),
        ActivityRecord(app: app, startedAt: day.addingTimeInterval(50 * 60), endedAt: day.addingTimeInterval(60 * 60), taskID: nil, focusSessionID: nil, classification: .allowed)
    ]
    let intervals = [
        TaskIntervalRecord(taskID: workflowA, startedAt: day.addingTimeInterval(10 * 60), endedAt: day.addingTimeInterval(30 * 60)),
        TaskIntervalRecord(taskID: workflowA, startedAt: day.addingTimeInterval(40 * 60), endedAt: day.addingTimeInterval(50 * 60)),
        TaskIntervalRecord(taskID: workflowB, startedAt: day.addingTimeInterval(40 * 60), endedAt: day.addingTimeInterval(50 * 60))
    ]
    let session = FocusSessionRecord(
        id: focusID,
        taskID: workflowB,
        startedAt: day.addingTimeInterval(30 * 60),
        endedAt: day.addingTimeInterval(40 * 60),
        targetSeconds: 10 * 60,
        outcome: .completed,
        difficulty: 2,
        confirmedDistractionCount: 0
    )

    let result = WorkflowAttributionEngine.summarize(
        activities: activities,
        taskIntervals: intervals,
        focusSessions: [session],
        now: day.addingTimeInterval(60 * 60)
    )

    #expect(result.recordedMinutes == 60)
    #expect(result.directMinutes == 10)
    #expect(result.intervalRecoveredMinutes == 20)
    #expect(result.focusSessionRecoveredMinutes == 10)
    #expect(result.unresolvedMinutes == 20)
    #expect(abs(result.attributedRatio - (2.0 / 3.0)) < 0.0001)
}

@Test
func dailyCoachKeepsNonWorkflowAnalysisWhenAttributionIsLow() {
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
    #expect(result.quality.isReliableForBehavior)
    #expect(result.quality.isReliable(.fragmentation))
    #expect(result.quality.isReliable(.contextRecovery))
    #expect(!result.quality.isReliable(.workflowSemantics))
    #expect(result.recommendation.kind == .startFocusRound)
    #expect(result.recommendation.action == .startFocus(minutes: 15))
    #expect(result.metrics.workflowAttribution?.directMinutes == 30)
    #expect(result.metrics.workflowAttribution?.unresolvedMinutes == 30)
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
    #expect(result.quality.isReliableForBehavior)
    #expect(result.quality.isReliable(.fragmentation))
    #expect(!result.quality.isReliable(.workflowSemantics))
    #expect(result.quality.warnings.contains { $0.contains("Space 识别噪声") })
    #expect(result.recommendation.kind == .startFocusRound)
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
func dailyCoachDoesNotTreatSwitchCountAloneAsRecoveryFailure() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 28, hour: 9)
    )!
    let task = UUID()
    let app = AppIdentity(bundleID: "app", name: "App")
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
        let startedAt = day.addingTimeInterval(Double(index) * 7 * 60)
        let endedAt = day.addingTimeInterval(Double(index + 1) * 7 * 60)
        intervals.append(
            TaskIntervalRecord(
                taskID: task,
                startedAt: startedAt,
                endedAt: endedAt,
                workflowSource: .space
            )
        )
    }
    let result = DailyCoachEngine.analyze(
        snapshot: FocusTraceLocalSnapshot(
            taskIntervals: intervals,
            activities: [
                ActivityRecord(
                    app: app,
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

    #expect(result.quality.isReliableForBehavior)
    #expect(result.metrics.workflowSwitchesPerHour >= 6)
    #expect(result.recommendation.kind != DailyCoachKind.agentParkingDrill)
}

@Test
func dailyCoachRequiresRepeatedExplicitHandoffsBeforeParkingAdvice() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 28, hour: 9)
    )!
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
    let app = AppIdentity(bundleID: "app", name: "App")
    let session = FocusSessionRecord(
        taskID: taskA,
        startedAt: day,
        endedAt: day.addingTimeInterval(15 * 60),
        targetSeconds: 15 * 60,
        outcome: .completed,
        difficulty: 2,
        confirmedDistractionCount: 0
    )
    let transitions = [
        workflowTransition(
            at: day.addingTimeInterval(20 * 60),
            origin: endpointA,
            destination: endpointB,
            outcome: .confirmed,
            reason: .waitingForResult
        ),
        workflowTransition(
            at: day.addingTimeInterval(40 * 60),
            origin: endpointB,
            destination: endpointA,
            outcome: .confirmed,
            reason: .forcedInterruption
        )
    ]
    let snapshot = FocusTraceLocalSnapshot(
        activities: [
            ActivityRecord(
                app: app,
                startedAt: day,
                endedAt: day.addingTimeInterval(60 * 60),
                taskID: taskA,
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
        workflowTransitions: transitions
    )
    let result = DailyCoachEngine.analyze(
        snapshot: snapshot,
        reportDate: day,
        generatedAt: day.addingTimeInterval(60 * 60),
        calendar: calendar
    )

    #expect(result.recommendation.kind == .agentParkingDrill)
    #expect(result.recommendation.evidence.contains("等待结果 1 次，被迫中断 1 次"))
    #expect(!result.recommendation.evidence.joined().contains("次/小时"))

    let issued = result.recommendation
    let completed = DailyCoachEngine.analyze(
        snapshot: FocusTraceLocalSnapshot(
            activities: snapshot.activities,
            focusSessions: snapshot.focusSessions,
            trainingPlans: snapshot.trainingPlans,
            workflowTransitions: transitions,
            taskParkings: [
                TaskParkingRecord(
                    taskID: taskA,
                    parkedAt: day.addingTimeInterval(25 * 60),
                    resumeCue: "private",
                    resumedAt: day.addingTimeInterval(35 * 60)
                )
            ]
        ),
        reportDate: day,
        generatedAt: day.addingTimeInterval(60 * 60),
        calendar: calendar,
        previousIssuedRecommendation: issued,
        previousIssuedMetrics: result.metrics
    )
    #expect(completed.previousRecommendationEvaluation?.status == .improved)
    #expect(completed.previousRecommendationEvaluation?.evidence.contains("已返回 1 次") == true)
}

@Test
func workflowTransitionAuditUsesFinalRoutesReasonsAndBoundedWorkTitles() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 27)
    )!
    let workflowA = UUID()
    let workflowB = UUID()
    let at: (Int, Int) -> Date = { hour, minute in
        day.addingTimeInterval(Double(hour * 3_600 + minute * 60))
    }
    let tasks = [
        TaskRecord(id: workflowA, title: "主召回\n性能优化"),
        TaskRecord(id: workflowB, title: "Codex 对话")
    ]
    let intervals = [
        TaskIntervalRecord(taskID: workflowA, startedAt: at(9, 0), endedAt: at(9, 10), workflowSource: .manual),
        TaskIntervalRecord(taskID: workflowB, startedAt: at(9, 10), endedAt: at(9, 14), workflowSource: .space),
        TaskIntervalRecord(taskID: workflowA, startedAt: at(9, 14), endedAt: at(9, 30), workflowSource: .space),
        TaskIntervalRecord(taskID: workflowB, startedAt: at(10, 0), endedAt: at(10, 20), workflowSource: .space)
    ]
    let markers = [
        TimelineMarkerRecord(date: at(9, 10), kind: .spaceSwitchUnstructured, taskID: workflowA),
        TimelineMarkerRecord(date: at(9, 14), kind: .spaceSwitchCheckpoint, taskID: workflowB),
        TimelineMarkerRecord(date: at(10, 0), kind: .spaceSwitchInterrupted, taskID: workflowA),
        TimelineMarkerRecord(date: at(11, 0), kind: .spaceSwitchCancelled, taskID: workflowA)
    ]
    let requirements = [
        RequirementRecord(title: "修复\n召回耗时", source: "SECRET_SOURCE", capturedAt: at(7, 0), status: .planned, workflowID: workflowA),
        RequirementRecord(title: "校验尾延迟", capturedAt: at(7, 1), status: .active, workflowID: workflowA),
        RequirementRecord(title: "补齐压测", capturedAt: at(7, 2), status: .planned, workflowID: workflowA),
        RequirementRecord(title: "第四个不会进入提示词", capturedAt: at(7, 3), status: .planned, workflowID: workflowA),
        RequirementRecord(title: "已完成内容", capturedAt: at(7, 4), status: .completed, workflowID: workflowA)
    ]

    let result = WorkflowTransitionAuditEngine.makeAudit(
        tasks: tasks,
        requirements: requirements,
        taskIntervals: intervals,
        activities: [
            ActivityRecord(app: AppIdentity(bundleID: "a", name: "A"), startedAt: at(9, 0), endedAt: at(9, 10), taskID: workflowA, focusSessionID: nil, classification: .allowed),
            ActivityRecord(app: AppIdentity(bundleID: "b", name: "B"), startedAt: at(9, 10), endedAt: at(9, 14), taskID: workflowB, focusSessionID: nil, classification: .allowed),
            ActivityRecord(app: AppIdentity(bundleID: "a", name: "A"), startedAt: at(9, 14), endedAt: at(9, 30), taskID: workflowA, focusSessionID: nil, classification: .allowed),
            ActivityRecord(app: AppIdentity(bundleID: "b", name: "B"), startedAt: at(10, 0), endedAt: at(10, 20), taskID: workflowB, focusSessionID: nil, classification: .allowed)
        ],
        markers: markers,
        range: day..<day.addingTimeInterval(24 * 3_600),
        now: at(18, 0),
        calendar: calendar
    )

    #expect(result.audit.reasonedSwitches == 3)
    #expect(result.audit.unreasonedSwitches == 0)
    #expect(result.audit.cancelledNavigations == 1)
    let route = try #require(result.audit.routes.first {
        $0.fromWorkflow == "主召回 性能优化" && $0.toWorkflow == "Codex 对话"
    })
    #expect(route.count == 2)
    #expect(route.reasonCounts["unstructured"] == 1)
    #expect(route.reasonCounts["forcedInterruption"] == 1)
    #expect(route.medianDestinationMinutes == 12)
    #expect(route.returnedWithin30Minutes == 1)
    let context = try #require(result.contexts.first {
        $0.workflowTitle == "主召回 性能优化"
    })
    #expect(context.activeMinutes == 26)
    #expect(
        context.openRequirementTitles == [
            "校验尾延迟",
            "修复 召回耗时",
            "补齐压测"
        ]
    )
    #expect(!context.openRequirementTitles.contains("第四个不会进入提示词"))
    #expect(!context.openRequirementTitles.contains("已完成内容"))
}

@Test
func workflowTransitionAuditPrefersNativeSemanticsWithoutDoubleCountingMarkers() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 28)
    )!
    let workflowA = UUID()
    let workflowB = UUID()
    let switchedAt = day.addingTimeInterval(9 * 3_600)
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
            TimelineMarkerRecord(
                date: switchedAt,
                kind: .spaceSwitchWaiting,
                taskID: workflowA
            )
        ],
        workflowTransitions: [
            WorkflowTransitionRecord(
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
        ],
        range: day..<day.addingTimeInterval(24 * 3_600),
        now: day.addingTimeInterval(18 * 3_600),
        calendar: calendar
    )

    #expect(result.audit.protocolVersion == 2)
    #expect(result.audit.dataSource == "semanticEvents")
    #expect(result.audit.finalSwitches == 1)
    #expect(result.audit.explicitReasonSwitches == 1)
    #expect(result.audit.explicitReasonCoverage == 1)
    #expect(result.audit.routes.first?.count == 1)
    #expect(result.audit.routes.first?.outcomeCounts?["confirmed"] == 1)
}

@Test
func workflowTransitionTimeoutDoesNotInventUserIntent() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
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
                workflowTransition(
                    at: switchedAt,
                    origin: WorkflowTransitionEndpoint(
                        kind: .workflow,
                        workflowID: workflowA
                    ),
                    destination: WorkflowTransitionEndpoint(
                        kind: .workflow,
                        workflowID: workflowB
                    ),
                    outcome: .timedOut,
                    trigger: .frequentSwitchBurst,
                    reason: .unstructured
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

    #expect(markdown.contains("主动说明 / 超时 / 自动：0 / 1 / 0 次"))
    #expect(markdown.contains("原因 未说明 1"))
    #expect(!markdown.contains("无明确计划"))
    #expect(!markdown.contains("已说明原因的最终跳转"))
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
    #expect(text.contains("\"schemaVersion\" : 6"))
    #expect(text.contains("\"reportCivilDate\" : \"2026-07-20\""))
    #expect(text.contains("\"recommendation\""))
    #expect(text.contains("\"appSwitchesPerHour\""))
    #expect(text.contains("\"observationPlan\""))
    #expect(text.contains("\"switchingLoad\""))
    #expect(text.contains("\"traceCoverage\""))
    #expect(text.contains("\"workflowAttribution\""))
    #expect(text.contains("\"analysisScopes\""))
    #expect(text.contains("\"minimalEventDrivenFixed\""))
    #expect(!text.contains("private.bundle"))
    #expect(!text.contains("Private App"))
    #expect(!text.contains("SECRET_RESUME_CUE"))
}

@Test
func automationReportV7CarriesTheSameAggregateAttentionTrendAsTheApp() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 10, hour: 9)
    )!
    let task = UUID()
    let activities = (0..<10).map { index -> ActivityRecord in
        let date = calendar.date(
            byAdding: .day,
            value: index,
            to: start
        )!
        return ActivityRecord(
            app: AppIdentity(
                bundleID: "aggregate.private.bundle",
                name: "Aggregate Private"
            ),
            startedAt: date,
            endedAt: date.addingTimeInterval(60 * 60),
            taskID: task,
            focusSessionID: nil,
            classification: .allowed
        )
    }
    let snapshot = FocusTraceLocalSnapshot(
        tasks: [TaskRecord(id: task, title: "工作流")],
        activities: activities,
        trainingPlans: [
            TrainingPlanRecord(
                version: 1,
                focusMinutes: 15,
                reason: "default"
            )
        ]
    )
    let reportDate = activities.last!.startedAt
    let report = AutomationReportEngine.makeReport(
        snapshot: snapshot,
        reportDate: reportDate,
        generatedAt: reportDate.addingTimeInterval(2 * 60 * 60),
        calendar: calendar
    )
    let trend = AutomationReportEngine.makeAttentionDashboard(
        snapshot: snapshot,
        through: reportDate,
        generatedAt: reportDate.addingTimeInterval(2 * 60 * 60),
        calendar: calendar,
        currentReport: report
    )
    let data = try AutomationReportEngine.jsonData(
        for: report,
        attentionTrend: trend
    )
    let text = String(decoding: data, as: UTF8.self)
    let markdown = AutomationReportEngine.markdown(
        for: report,
        attentionTrend: trend,
        timeZone: calendar.timeZone
    )

    #expect(text.contains("\"schemaVersion\" : 7"))
    #expect(text.contains("\"attentionTrend\""))
    #expect(text.contains("\"metrics\""))
    #expect(markdown.contains("最近十个工作日注意力趋势"))
    #expect(markdown.contains("下一步单项实验"))
    #expect(!text.contains("aggregate.private.bundle"))
    #expect(!text.contains("Aggregate Private"))
}

@Test
func automationReportV6KeepsLegacyV2ReadCompatibility() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 27, hour: 9)
    )!
    let report = AutomationReportEngine.makeReport(
        snapshot: FocusTraceLocalSnapshot(),
        reportDate: day,
        generatedAt: day,
        calendar: calendar
    )
    let v6Data = try AutomationReportEngine.jsonData(for: report)
    var legacyObject = try #require(
        JSONSerialization.jsonObject(with: v6Data) as? [String: Any]
    )
    legacyObject["schemaVersion"] = 2
    legacyObject.removeValue(forKey: "reportCivilDate")
    legacyObject.removeValue(forKey: "workflowContexts")
    legacyObject.removeValue(forKey: "transitionAudit")
    legacyObject.removeValue(forKey: "observationPlan")
    legacyObject.removeValue(forKey: "switchingLoad")
    if var normalized = legacyObject["normalized"] as? [String: Any] {
        normalized.removeValue(forKey: "workflowAttribution")
        legacyObject["normalized"] = normalized
    }
    if var quality = legacyObject["dataQuality"] as? [String: Any] {
        quality.removeValue(forKey: "analysisScopes")
        legacyObject["dataQuality"] = quality
    }
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(
        AutomationReportArtifact.self,
        from: legacyData
    )

    #expect(decoded.schemaVersion == 2)
    #expect(decoded.reportCivilDate == nil)
    #expect(decoded.workflowContexts == nil)
    #expect(decoded.transitionAudit == nil)
    #expect(decoded.observationPlan == nil)
    #expect(decoded.switchingLoad == nil)
    #expect(decoded.normalized.workflowAttribution == nil)
    #expect(decoded.dataQuality.analysisScopes == nil)
}

@Test
func codexReviewDecisionBriefRemainsShortAndCompatible() {
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
    #expect(review.hasValidShape)
    #expect(review.isConsistentWithBehaviorReliability(true))
    #expect(!review.isConsistentWithBehaviorReliability(false))
    #expect(review.displayedProblem == "今天没有形成带结果反馈的训练样本。")

    let blocked = CodexReviewArtifact(
        sourceReportID: review.sourceReportID,
        reportDate: review.reportDate,
        generatedAt: review.generatedAt,
        status: .dataQualityBlocked,
        problem: "工作流归因不足；当前不能据此判断注意力。",
        recommendation: "把当前桌面绑定到正在推进的工作流，并连续记录 30 分钟。",
        evidence: ["工作流归因率 68%"],
        nextCheck: "下一工作日检查归因率是否达到 70%。"
    )
    #expect(blocked.isConsistentWithBehaviorReliability(false))

    let repeatedEvidence = CodexReviewArtifact(
        sourceReportID: review.sourceReportID,
        reportDate: review.reportDate,
        generatedAt: review.generatedAt,
        status: .behaviorFinding,
        problem: review.displayedProblem,
        recommendation: review.recommendation,
        evidence: ["今日训练 0 次", "今日训练0次"],
        nextCheck: review.nextCheck
    )
    #expect(!repeatedEvidence.hasValidShape)
}

@Test
func codexReviewV3RejectsUngroundedWorkflowSemantics() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 28, hour: 9)
    )!
    let workflowA = UUID()
    let workflowB = UUID()
    let report = AutomationReportArtifact(
        report: AutomationReportEngine.makeReport(
            snapshot: FocusTraceLocalSnapshot(
                tasks: [
                    TaskRecord(id: workflowA, title: "等待 Agent"),
                    TaskRecord(id: workflowB, title: "处理需求")
                ],
                activities: [
                    ActivityRecord(
                        app: AppIdentity(bundleID: "app", name: "App"),
                        startedAt: day,
                        endedAt: day.addingTimeInterval(60 * 60),
                        taskID: workflowA,
                        focusSessionID: nil,
                        classification: .allowed
                    )
                ],
                trainingPlans: [
                    TrainingPlanRecord(
                        version: 1,
                        focusMinutes: 15,
                        reason: "default"
                    )
                ],
                workflowTransitions: [
                    workflowTransition(
                        at: day.addingTimeInterval(20 * 60),
                        origin: WorkflowTransitionEndpoint(
                            kind: .workflow,
                            workflowID: workflowA
                        ),
                        destination: WorkflowTransitionEndpoint(
                            kind: .workflow,
                            workflowID: workflowB
                        ),
                        outcome: .confirmed,
                        reason: .waitingForResult
                    ),
                    workflowTransition(
                        at: day.addingTimeInterval(40 * 60),
                        origin: WorkflowTransitionEndpoint(
                            kind: .workflow,
                            workflowID: workflowA
                        ),
                        destination: WorkflowTransitionEndpoint(
                            kind: .workflow,
                            workflowID: workflowB
                        ),
                        outcome: .confirmed,
                        reason: .waitingForResult
                    )
                ]
            ),
            reportDate: day,
            generatedAt: day.addingTimeInterval(60 * 60),
            calendar: calendar
        )
    )
    let grounded = CodexReviewArtifact(
        schemaVersion: 3,
        sourceReportID: report.reportID,
        reportDate: report.reportDate,
        generatedAt: day.addingTimeInterval(60 * 60),
        status: .behaviorFinding,
        problem: "等待 Agent 到处理需求的交接重复发生且没有返回点。",
        recommendation: "下一次等待结果时先保存返回点，再开始处理需求。",
        evidence: ["等待 Agent → 处理需求因等待结果发生 2 次"],
        nextCheck: "下一工作日检查该路线是否保存并返回一次。",
        analysisAudit: CodexReviewAnalysisAudit(
            source: .workflowRoute,
            selectedRoute: CodexReviewRouteSelection(
                fromWorkflow: "等待 Agent",
                toWorkflow: "处理需求",
                reason: .waitingForResult
            ),
            contextRelation: .adjacentDeliverables
        )
    )
    #expect(grounded.hasValidShape)
    #expect(grounded.isGrounded(in: report))

    let hallucinated = CodexReviewArtifact(
        schemaVersion: 3,
        sourceReportID: report.reportID,
        reportDate: report.reportDate,
        generatedAt: day.addingTimeInterval(60 * 60),
        status: .behaviorFinding,
        problem: grounded.displayedProblem,
        recommendation: grounded.recommendation,
        evidence: grounded.evidence,
        nextCheck: grounded.nextCheck,
        analysisAudit: CodexReviewAnalysisAudit(
            source: .workflowRoute,
            selectedRoute: CodexReviewRouteSelection(
                fromWorkflow: "等待 Agent",
                toWorkflow: "不存在的工作流",
                reason: .waitingForResult
            ),
            contextRelation: .differentGoals
        )
    )
    #expect(!hallucinated.isGrounded(in: report))

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let reportData = try encoder.encode(report)
    var reportObject = try #require(
        JSONSerialization.jsonObject(with: reportData) as? [String: Any]
    )
    var qualityObject = try #require(
        reportObject["dataQuality"] as? [String: Any]
    )
    qualityObject["analysisScopes"] = [
        ["lens": "dataQuality", "isReliable": true, "reason": "可说明范围"],
        ["lens": "fragmentation", "isReliable": true, "reason": "应用记录完整"],
        ["lens": "contextRecovery", "isReliable": true, "reason": "显式动作完整"],
        ["lens": "workflowSemantics", "isReliable": false, "reason": "覆盖不足"]
    ]
    reportObject["dataQuality"] = qualityObject
    let partialData = try JSONSerialization.data(withJSONObject: reportObject)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let partialReport = try decoder.decode(
        AutomationReportArtifact.self,
        from: partialData
    )
    #expect(partialReport.dataQuality.isReliableForBehavior)
    #expect(!partialReport.dataQuality.isReliable(.workflowSemantics))
    #expect(!grounded.isGrounded(in: partialReport))
}

@Test
func codexReviewKeepsLegacyReadCompatibility() {
    let legacy = CodexReviewArtifact(
        sourceReportID: "legacy-report",
        reportDate: Date(timeIntervalSince1970: 100),
        generatedAt: Date(timeIntervalSince1970: 200),
        headline: "工作流归因不足，当前不能据此判断注意力。",
        interpretation: "这是一段旧协议生成的冗长解释，界面不应继续展示。",
        recommendation: "先校准当前桌面的工作流绑定。",
        evidence: ["工作流归因率 68%", "可靠门槛 70%"],
        nextCheck: "下一工作日检查归因率是否达到 70%。"
    )

    #expect(legacy.hasValidShape)
    #expect(legacy.displayedProblem == legacy.headline)
    #expect(legacy.displayedStatus == .dataQualityBlocked)
    #expect(!legacy.displayedProblem.contains("冗长解释"))
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
    #expect(instructions.contains("Select exactly one problem"))
    #expect(instructions.contains("second recommendation"))
    #expect(script.contains("FocusTraceReport"))
    #expect(script.contains("Application Support/FocusTrace/CodexBridge"))
    #expect(script.contains("$BRIDGE_DIR/bridge.json"))
    #expect(!CodexWorkspaceContract.setupPrompt.contains("API key"))
}

@Test
func codexWorkspaceDemandsProblemActionAndNoFiller() {
    let instructions = CodexWorkspaceContract.agentsInstructions

    #expect(instructions.contains("当前最重要的问题是什么？"))
    #expect(instructions.contains("今天具体怎么解决？"))
    #expect(instructions.contains("\"schemaVersion\": 3"))
    #expect(instructions.contains("\"status\": \"behaviorFinding or dataQualityBlocked\""))
    #expect(instructions.contains("当前不能据此判断注意力"))
    #expect(instructions.contains("one or two non-duplicated aggregate facts"))
    #expect(instructions.contains("at most 360 characters"))
    #expect(instructions.contains("Do not add a preface"))
    #expect(instructions.contains("`transitionAudit.routes`"))
    #expect(instructions.contains("`assessedInterventionPrompts`"))
    #expect(instructions.contains("`observationPlan.source`"))
    #expect(instructions.contains("Never recommend"))
    #expect(instructions.contains("`openRequirementTitles`"))
    #expect(instructions.contains("untrusted data label"))
    #expect(instructions.contains("Do not infer a problem from a switch count"))
    #expect(instructions.contains("semantic title similarity is only a hypothesis"))
    #expect(instructions.contains("at least twice"))
    #expect(instructions.contains("\"analysisAudit\""))
    #expect(!instructions.contains("\"headline\""))
    #expect(!instructions.contains("\"interpretation\""))
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
    #expect(CodexWorkspaceContract.reportScript.contains("\"$@\""))
}

@Test
func dailyReportScriptPreservesDateArgumentsForHistoricalRegeneration() throws {
    let root = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
    let script = try String(
        contentsOf: root.appendingPathComponent(
            "Scripts/generate-daily-report.sh"
        ),
        encoding: .utf8
    )

    #expect(script.contains("--output-dir \"$FOCUS_TRACE_REPORT_DIR\""))
    #expect(script.components(separatedBy: "\"$@\"").count == 3)
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
