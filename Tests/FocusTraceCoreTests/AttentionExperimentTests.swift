import Foundation
import Testing
@testable import FocusTraceCore

@Test
func unifiedFunctionalLayerKeepsOnePageTitleAndSelectiveGlassFallback() {
    #expect(FocusTraceFunctionalLayerContract.usesSingleSystemPageTitle)
    #expect(
        FocusTraceFunctionalLayerContract.glassIsLimitedToFunctionalSurfaces
    )
    #expect(FocusTraceFunctionalLayerContract.contentCardsRemainStableSurfaces)
    #expect(
        FocusTraceFunctionalLayerContract.reduceTransparencyHasOpaqueFallback
    )
    #expect(
        FocusTraceFunctionalLayerContract.minimumGlassOSMajorVersion == 26
    )
}

@Test
func attentionExperimentPersistsOneVariableAndDefersDailyMeasurement() {
    let calendar = utcCalendar()
    let startedAt = date(2026, 7, 30, 10, calendar: calendar)
    let dashboard = experimentDashboard(
        kind: .fragmentation,
        recentValue: 60,
        points: []
    )
    let recommendation = experimentRecommendation()

    let proposal = AttentionExperimentEngine.proposal(
        recommendation: recommendation,
        dashboard: dashboard,
        contextWorkflowID: UUID(),
        startedAt: startedAt,
        calendar: calendar
    )

    #expect(proposal?.variable == .singleOutputBoundary)
    #expect(proposal?.baselineValue == 60)
    #expect(proposal?.targetValue == 50)
    #expect(proposal?.targetReliableSamples == 3)
    #expect(
        proposal?.measurementStartsAt
            == date(2026, 7, 31, 0, calendar: calendar)
    )
    #expect(proposal?.status == .active)
}

@Test
func attentionExperimentAllowsOnlyOneActiveRecord() {
    let calendar = utcCalendar()
    let active = experimentRecord(
        startedAt: date(2026, 7, 30, 10, calendar: calendar),
        targetReliableSamples: 3,
        calendar: calendar
    )
    #expect(!AttentionExperimentEngine.canStartNew(in: [active]))

    let stopped = AttentionExperimentEngine.stopped(
        active,
        at: date(2026, 7, 30, 11, calendar: calendar)
    )
    #expect(AttentionExperimentEngine.canStartNew(in: [stopped]))
}

@Test
func attentionExperimentSeparatesOpportunityMissingnessAndQualityBlocking() {
    let calendar = utcCalendar()
    let startedAt = date(2026, 7, 29, 10, calendar: calendar)
    let points = [
        trendPoint(
            2026, 7, 30,
            value: nil,
            availability: .noOpportunity,
            calendar: calendar
        ),
        trendPoint(
            2026, 7, 31,
            value: 58,
            availability: .missingInput,
            calendar: calendar
        ),
        trendPoint(
            2026, 8, 1,
            value: 55,
            availability: .qualityBlocked,
            calendar: calendar
        ),
        trendPoint(
            2026, 8, 2,
            value: 45,
            availability: .reliable,
            calendar: calendar
        )
    ]
    let experiment = experimentRecord(
        startedAt: startedAt,
        targetReliableSamples: 1,
        calendar: calendar
    )
    let dashboard = experimentDashboard(
        kind: .fragmentation,
        recentValue: 60,
        points: points
    )
    let focusSessions = [
        (2026, 7, 30),
        (2026, 7, 31),
        (2026, 8, 1),
        (2026, 8, 2)
    ].map {
        completedExperimentSession(
            taskID: UUID(),
            startedAt: date(
                $0.0,
                $0.1,
                $0.2,
                10,
                calendar: calendar
            )
        )
    }

    let progress = AttentionExperimentEngine.evaluate(
        experiment,
        dashboard: dashboard,
        taskIntervals: [],
        focusSessions: focusSessions,
        now: date(2026, 8, 3, 12, calendar: calendar),
        calendar: calendar
    )

    #expect(progress.state == .ready)
    #expect(progress.reliableSamples == 1)
    #expect(progress.noOpportunityCount == 1)
    #expect(progress.missingInputCount == 1)
    #expect(progress.qualityBlockedCount == 1)
    #expect(progress.targetMet == true)
}

@Test
func attentionExperimentMatchesWorkflowAndTimeBandBeforeComparing() {
    let calendar = utcCalendar()
    let workflowID = UUID()
    let startedAt = date(2026, 7, 29, 10, calendar: calendar)
    let points = [
        trendPoint(
            2026, 7, 30,
            value: 48,
            availability: .reliable,
            calendar: calendar
        ),
        trendPoint(
            2026, 7, 31,
            value: 44,
            availability: .reliable,
            calendar: calendar
        )
    ]
    let experiment = AttentionExperimentRecord(
        metricKind: .fragmentation,
        variable: .singleOutputBoundary,
        title: "单一产出",
        hypothesis: "减少碎片",
        methodTitle: "保持一个变量",
        steps: ["只改产出边界"],
        successMeasure: "碎片下降",
        evidence: ["趋势恶化"],
        action: .startFocus(minutes: 15),
        baselineValue: 60,
        targetValue: 50,
        lowerIsBetter: true,
        targetReliableSamples: 1,
        startedAt: startedAt,
        measurementStartsAt: date(2026, 7, 30, 0, calendar: calendar),
        contextWorkflowID: workflowID,
        contextTimeBand: .morning
    )
    let intervals = [
        TaskIntervalRecord(
            taskID: workflowID,
            startedAt: date(2026, 7, 30, 9, calendar: calendar),
            endedAt: date(2026, 7, 30, 9, calendar: calendar)
                .addingTimeInterval(11 * 60)
        ),
        TaskIntervalRecord(
            taskID: workflowID,
            startedAt: date(2026, 7, 31, 15, calendar: calendar),
            endedAt: date(2026, 7, 31, 15, calendar: calendar)
                .addingTimeInterval(30 * 60)
        )
    ]
    let focusSessions = [
        completedExperimentSession(
            taskID: workflowID,
            startedAt: date(2026, 7, 30, 9, calendar: calendar)
        ),
        completedExperimentSession(
            taskID: workflowID,
            startedAt: date(2026, 7, 31, 15, calendar: calendar)
        )
    ]

    let progress = AttentionExperimentEngine.evaluate(
        experiment,
        dashboard: experimentDashboard(
            kind: .fragmentation,
            recentValue: 60,
            points: points
        ),
        taskIntervals: intervals,
        focusSessions: focusSessions,
        now: date(2026, 8, 1, 12, calendar: calendar),
        calendar: calendar
    )

    #expect(progress.reliableSamples == 1)
    #expect(progress.noOpportunityCount == 1)
    #expect(progress.observedValue == 48)
}

@Test
func attentionExperimentRequiresObservedUseOfTheChangedVariable() {
    let calendar = utcCalendar()
    let workflowID = UUID()
    let day = date(2026, 7, 30, 9, calendar: calendar)
    let experiment = AttentionExperimentRecord(
        metricKind: .fragmentation,
        variable: .singleOutputBoundary,
        title: "单一产出",
        hypothesis: "减少碎片",
        methodTitle: "单一变量",
        steps: ["完成一轮专注训练"],
        successMeasure: "碎片下降",
        evidence: ["趋势恶化"],
        action: .startFocus(minutes: 15),
        baselineValue: 60,
        targetValue: 50,
        lowerIsBetter: true,
        targetReliableSamples: 1,
        startedAt: day.addingTimeInterval(-24 * 60 * 60),
        measurementStartsAt: calendar.startOfDay(for: day),
        contextWorkflowID: workflowID,
        contextTimeBand: .morning
    )
    let dashboard = experimentDashboard(
        kind: .fragmentation,
        recentValue: 60,
        points: [
            trendPoint(
                2026, 7, 30,
                value: 45,
                availability: .reliable,
                calendar: calendar
            )
        ]
    )
    let interval = TaskIntervalRecord(
        taskID: workflowID,
        startedAt: day,
        endedAt: day.addingTimeInterval(11 * 60)
    )

    let withoutAction = AttentionExperimentEngine.evaluate(
        experiment,
        dashboard: dashboard,
        taskIntervals: [interval],
        focusSessions: [],
        calendar: calendar
    )
    let withAction = AttentionExperimentEngine.evaluate(
        experiment,
        dashboard: dashboard,
        taskIntervals: [interval],
        focusSessions: [
            completedExperimentSession(
                taskID: workflowID,
                startedAt: day
            )
        ],
        calendar: calendar
    )

    #expect(withoutAction.reliableSamples == 0)
    #expect(withoutAction.missingInputCount == 1)
    #expect(withAction.reliableSamples == 1)
    #expect(withAction.state == .ready)
}

@Test
func attentionExperimentTrainingRequiresFiveComparableDifficultySamples() {
    let calendar = utcCalendar()
    let workflowID = UUID()
    let startedAt = date(2026, 7, 30, 14, calendar: calendar)
    let experiment = AttentionExperimentRecord(
        metricKind: .trainingFeedback,
        variable: .focusDuration,
        title: "缩短训练",
        hypothesis: "降低难度",
        methodTitle: "训练负荷校准",
        steps: ["只缩短五分钟"],
        successMeasure: "成功率至少 80%，难度不高于 3",
        evidence: ["最近训练反馈下降"],
        action: .startFocus(minutes: 10),
        baselineValue: 40,
        targetValue: 80,
        targetSecondaryValue: 3,
        lowerIsBetter: false,
        targetReliableSamples: 5,
        startedAt: startedAt,
        measurementStartsAt: startedAt,
        contextWorkflowID: workflowID,
        contextTimeBand: .afternoon
    )
    var sessions: [FocusSessionRecord] = []
    for offset in 0..<5 {
        let sessionStart = startedAt.addingTimeInterval(
            Double(offset) * 24 * 60 * 60
        )
        sessions.append(
            FocusSessionRecord(
                taskID: workflowID,
                startedAt: sessionStart,
                endedAt: sessionStart.addingTimeInterval(10 * 60),
                targetSeconds: 10 * 60,
                outcome: .completed,
                difficulty: offset == 4 ? 3 : 2,
                confirmedDistractionCount: 0
            )
        )
    }

    let progress = AttentionExperimentEngine.evaluate(
        experiment,
        dashboard: experimentDashboard(
            kind: .trainingFeedback,
            recentValue: 40,
            points: []
        ),
        taskIntervals: [],
        focusSessions: sessions,
        calendar: calendar
    )

    #expect(progress.state == .ready)
    #expect(progress.reliableSamples == 5)
    #expect(progress.observedValue == 100)
    #expect(progress.observedSecondaryValue == 2)
    #expect(progress.targetMet == true)
}

@Test
func attentionExperimentKeepsItsFirstTenDayEvidenceWindow() {
    let calendar = utcCalendar()
    let startedAt = date(2026, 7, 19, 10, calendar: calendar)
    let reliableDays = Set([20, 21, 22])
    let points = (20...31).map { day in
        trendPoint(
            2026,
            7,
            day,
            value: reliableDays.contains(day) ? 45 : nil,
            availability: reliableDays.contains(day)
                ? .reliable
                : .noOpportunity,
            calendar: calendar
        )
    }
    let sessions = reliableDays.map { day in
        completedExperimentSession(
            taskID: UUID(),
            startedAt: date(2026, 7, day, 10, calendar: calendar)
        )
    }
    let progress = AttentionExperimentEngine.evaluate(
        experimentRecord(
            startedAt: startedAt,
            targetReliableSamples: 3,
            calendar: calendar
        ),
        dashboard: experimentDashboard(
            kind: .fragmentation,
            recentValue: 60,
            points: points
        ),
        taskIntervals: [],
        focusSessions: sessions,
        calendar: calendar
    )

    #expect(progress.state == .ready)
    #expect(progress.reliableSamples == 3)
    #expect(progress.targetMet == true)
}

@Test
func attentionDashboardKeepsExperimentWindowBesideMovingTrendWindow() {
    let calendar = utcCalendar()
    let startedAt = date(2026, 7, 1, 10, calendar: calendar)
    let experiment = experimentRecord(
        startedAt: startedAt,
        targetReliableSamples: 3,
        calendar: calendar
    )
    let activityDates = (1...20).map {
        calendar.date(byAdding: .day, value: $0, to: startedAt)!
    }
    let activities = activityDates.map { day in
        ActivityRecord(
            app: AppIdentity(bundleID: "test.app", name: "Test"),
            startedAt: day,
            endedAt: day.addingTimeInterval(60),
            taskID: nil,
            focusSessionID: nil,
            classification: .allowed
        )
    }
    let reportDate = activityDates.last!
    let withoutExperiment = AttentionDashboardEngine.candidateDates(
        in: FocusTraceLocalSnapshot(activities: activities),
        through: reportDate,
        calendar: calendar
    )
    let withExperiment = AttentionDashboardEngine.candidateDates(
        in: FocusTraceLocalSnapshot(
            activities: activities,
            attentionExperiments: [experiment]
        ),
        through: reportDate,
        calendar: calendar
    )

    #expect(withoutExperiment.count == 10)
    #expect(withExperiment.count == 20)
    #expect(
        withExperiment.first
            == calendar.startOfDay(for: activityDates.first!)
    )
    #expect(
        withExperiment.last
            == calendar.startOfDay(for: reportDate)
    )
}

@Test
func attentionExperimentEndsTenDayWindowAsInsufficientEvidence() {
    let calendar = utcCalendar()
    let startedAt = date(2026, 7, 19, 10, calendar: calendar)
    let points = (20...29).map { day in
        trendPoint(
            2026,
            7,
            day,
            value: nil,
            availability: .noOpportunity,
            calendar: calendar
        )
    }
    let experiment = experimentRecord(
        startedAt: startedAt,
        targetReliableSamples: 3,
        calendar: calendar
    )
    let progress = AttentionExperimentEngine.evaluate(
        experiment,
        dashboard: experimentDashboard(
            kind: .fragmentation,
            recentValue: 60,
            points: points
        ),
        taskIntervals: [],
        focusSessions: [],
        calendar: calendar
    )
    let completed = AttentionExperimentEngine.completed(
        experiment,
        progress: progress,
        at: date(2026, 7, 30, 10, calendar: calendar)
    )

    #expect(progress.state == .ready)
    #expect(progress.reliableSamples == 0)
    #expect(progress.targetMet == nil)
    #expect(progress.summary.contains("证据窗口已结束"))
    #expect(completed.result == .insufficientEvidence)
}

@Test
func localSnapshotDecodesWithoutAttentionExperiments() throws {
    let decoder = JSONDecoder()
    let snapshot = try decoder.decode(
        FocusTraceLocalSnapshot.self,
        from: Data(#"{"tasks":[],"activities":[]}"#.utf8)
    )
    #expect(snapshot.attentionExperiments.isEmpty)
}

@Test
func localSnapshotDecodesPersistedAttentionExperiment() throws {
    let calendar = utcCalendar()
    let experiment = experimentRecord(
        startedAt: date(2026, 7, 30, 10, calendar: calendar),
        targetReliableSamples: 3,
        calendar: calendar
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let encoded = try encoder.encode(experiment)
    let record = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    let root: [String: Any] = [
        "tasks": [],
        "activities": [],
        "attentionExperiments": [["record": record]]
    ]
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(
        FocusTraceLocalSnapshot.self,
        from: JSONSerialization.data(withJSONObject: root)
    )

    #expect(snapshot.attentionExperiments == [experiment])
}

@Test
func contextRecoveryUsesNaturalReturnAfterExplicitHandoff() {
    let calendar = utcCalendar()
    let start = date(2026, 7, 30, 9, calendar: calendar)
    let workflowA = UUID()
    let workflowB = UUID()
    let transitions = [
        WorkflowTransitionRecord(
            navigationStartedAt: start,
            settledAt: start.addingTimeInterval(1),
            resolvedAt: start.addingTimeInterval(2),
            origin: WorkflowTransitionEndpoint(
                kind: .workflow,
                workflowID: workflowA
            ),
            destination: WorkflowTransitionEndpoint(
                kind: .workflow,
                workflowID: workflowB
            ),
            outcome: .confirmed,
            reason: .waitingForResult,
            navigationEventCount: 1
        ),
        WorkflowTransitionRecord(
            navigationStartedAt: start.addingTimeInterval(10 * 60),
            settledAt: start.addingTimeInterval(10 * 60 + 1),
            resolvedAt: start.addingTimeInterval(10 * 60 + 2),
            origin: WorkflowTransitionEndpoint(
                kind: .workflow,
                workflowID: workflowB
            ),
            destination: WorkflowTransitionEndpoint(
                kind: .workflow,
                workflowID: workflowA
            ),
            outcome: .confirmed,
            reason: .reachedCheckpoint,
            navigationEventCount: 1
        )
    ]
    let quality = DailyDataQuality(
        isReliableForBehavior: true,
        warnings: [],
        analysisScopes: ObservationLens.allCases.map {
            DailyAnalysisScopeReliability(
                lens: $0,
                isReliable: true,
                reason: "test"
            )
        }
    )
    let assessment = SwitchingLoadEngine.assess(
        activities: [],
        taskIntervals: [],
        focusSessions: [],
        interruptions: [],
        workflowTransitions: transitions,
        taskParkings: [],
        markers: [],
        workflowContextCount: 2,
        range: DateInterval(
            start: start,
            end: start.addingTimeInterval(60 * 60)
        ),
        now: start.addingTimeInterval(60 * 60),
        quality: quality,
        trend: DailyTrendComparison(
            baselineDays: 3,
            appSwitchRateDeltaPercent: 0,
            workflowSwitchRateDeltaPercent: 0,
            attributedRatioDeltaPoints: 0,
            medianFocusDeltaMinutes: 0
        ),
        transitionAudit: AutomationWorkflowTransitionAuditArtifact(
            explicitReasonCoverage: 1,
            reasonedSwitches: 2,
            unreasonedSwitches: 0,
            cancelledNavigations: 0,
            reasonCounts: [:],
            routes: []
        )
    )

    #expect(assessment.metrics.workflowRecoveryOpportunities == 1)
    #expect(assessment.metrics.workflowRecoveriesWithin30Minutes == 1)
    #expect(assessment.metrics.workflowRecoveryRate == 1)
}

private func experimentRecommendation() -> DailyCoachRecommendation {
    DailyCoachRecommendation(
        kind: .startFocusRound,
        title: "把高碎片时段改成单一产出块",
        rationale: "碎片化与连续工作同时恶化",
        evidence: ["近三日高碎片窗口 60%"],
        confidence: .medium,
        action: .startFocus(minutes: 15),
        method: DailyTrainingMethod(
            title: "单一产出实验",
            steps: ["只改变产出边界"],
            successMeasure: "碎片下降至少 10 个百分点"
        )
    )
}

private func experimentDashboard(
    kind: AttentionDashboardMetricKind,
    recentValue: Double,
    points: [AttentionTrendPoint]
) -> AttentionDashboard {
    let trend = AttentionMetricTrend(
        kind: kind,
        unit: kind == .sustainedProgress ? "分钟" : "%",
        lowerIsBetter: [.fragmentation, .switchingBoundary].contains(kind),
        direction: .worsening,
        points: points,
        baselineMedian: recentValue - 10,
        recentMedian: recentValue,
        typicalLowerBound: recentValue - 12,
        typicalUpperBound: recentValue - 8,
        reliableDayCount: 7,
        comparison: "近 3 日 \(recentValue)"
    )
    let metric = AttentionDashboardMetric(
        kind: kind,
        state: .needsAttention,
        title: "测试指标",
        value: "\(recentValue)",
        comparison: "趋势恶化",
        evidence: ["可靠趋势"],
        trend: trend
    )
    return AttentionDashboard(
        version: 3,
        recordedMinutes: 120,
        baselineDays: 7,
        reliableDimensionCount: 1,
        metrics: [metric],
        finding: AttentionDashboardFinding(
            state: .needsAttention,
            kind: kind,
            title: "当前问题",
            detail: "可靠趋势正在恶化",
            evidence: ["可靠趋势"]
        ),
        recommendation: experimentRecommendation()
    )
}

private func experimentRecord(
    startedAt: Date,
    targetReliableSamples: Int,
    calendar: Calendar
) -> AttentionExperimentRecord {
    AttentionExperimentRecord(
        metricKind: .fragmentation,
        variable: .singleOutputBoundary,
        title: "单一产出",
        hypothesis: "减少碎片",
        methodTitle: "单一变量",
        steps: ["只改产出边界"],
        successMeasure: "碎片下降",
        evidence: ["趋势恶化"],
        action: .startFocus(minutes: 15),
        baselineValue: 60,
        targetValue: 50,
        lowerIsBetter: true,
        targetReliableSamples: targetReliableSamples,
        startedAt: startedAt,
        measurementStartsAt: calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: startedAt)
        )!,
        contextTimeBand: .morning
    )
}

private func trendPoint(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    value: Double?,
    availability: AttentionMeasurementAvailability,
    calendar: Calendar
) -> AttentionTrendPoint {
    AttentionTrendPoint(
        date: date(year, month, day, 12, calendar: calendar),
        value: value,
        sampleCount: availability == .noOpportunity ? 0 : 4,
        isReliable: availability == .reliable,
        isPartial: false,
        availability: availability
    )
}

private func completedExperimentSession(
    taskID: UUID,
    startedAt: Date
) -> FocusSessionRecord {
    FocusSessionRecord(
        taskID: taskID,
        startedAt: startedAt,
        endedAt: startedAt.addingTimeInterval(15 * 60),
        targetSeconds: 15 * 60,
        outcome: .completed,
        difficulty: 2,
        confirmedDistractionCount: 0
    )
}

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    calendar: Calendar
) -> Date {
    calendar.date(
        from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        )
    )!
}
