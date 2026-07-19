@preconcurrency import AppKit
import Combine
import Foundation
import FocusTraceCore

struct PendingSessionReview: Identifiable {
    let id: UUID
    let targetMinutes: Int
    let elapsedSeconds: Int
}

struct TrainingProposal: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let evidence: String
    let focusMinutes: Int
}

@MainActor
final class ApplicationState: ObservableObject {
    let store: FocusTraceStore
    let preferences: AppPreferences

    @Published private(set) var tasks: [FocusTaskModel] = []
    @Published private(set) var taskIntervals: [TaskIntervalModel] = []
    @Published private(set) var activities: [ActivitySegmentModel] = []
    @Published private(set) var focusSessions: [FocusSessionModel] = []
    @Published private(set) var interruptions: [InterruptionModel] = []
    @Published private(set) var trainingPlans: [TrainingPlanModel] = []
    @Published private(set) var markers: [TimelineMarkerModel] = []

    @Published var selectedDate = Calendar.current.startOfDay(for: Date())
    @Published private(set) var currentTaskID: UUID?
    @Published private(set) var currentFocusID: UUID?
    @Published private(set) var now = Date()
    @Published var pendingSessionReview: PendingSessionReview?
    @Published var trainingProposal: TrainingProposal?
    @Published var showTaskSwitcher = false
    @Published var errorMessage: String?
    @Published private(set) var isSystemActive = true

    private var captureMachine = ActivityCaptureStateMachine()
    private var activeSegment: ActivitySegmentModel?
    private var activeTaskInterval: TaskIntervalModel?
    private var distractionTask: Task<Void, Never>?
    private var focusClockTask: Task<Void, Never>?
    private var scheduleTask: Task<Void, Never>?
    private var lastAllowedBundleID: String?
    private var hasStarted = false

    private let workspaceMonitor = WorkspaceMonitor()
    private let notificationRouter = NotificationRouter()

    init(store: FocusTraceStore, preferences: AppPreferences = AppPreferences()) {
        self.store = store
        self.preferences = preferences
    }

    deinit {
        distractionTask?.cancel()
        focusClockTask?.cancel()
        scheduleTask?.cancel()
    }

    var activeTasks: [FocusTaskModel] {
        tasks.filter { !$0.isArchived }
    }

    var currentTask: FocusTaskModel? {
        guard let currentTaskID else { return nil }
        return tasks.first { $0.id == currentTaskID }
    }

    var currentFocus: FocusSessionModel? {
        guard let currentFocusID else { return nil }
        return focusSessions.first { $0.id == currentFocusID }
    }

    var currentPlan: TrainingPlanModel {
        if let plan = trainingPlans.max(by: { $0.version < $1.version }) {
            return plan
        }
        let fallback = TrainingPlanModel(
            version: 1,
            focusMinutes: 15,
            reminderThresholdSeconds: preferences.reminderThresholdSeconds,
            reason: "基线数据不足，使用默认 15 分钟"
        )
        store.insert(fallback)
        trainingPlans.append(fallback)
        try? store.save()
        return fallback
    }

    var isRecording: Bool {
        shouldRecord(at: now) && captureMachine.isSystemActive
    }

    var baselineDayCount: Int {
        Set(
            taskIntervals
                .filter { preferences.isWithinWorkSchedule($0.startedAt) }
                .map { Calendar.current.startOfDay(for: $0.startedAt) }
        ).count
    }

    var baselineComplete: Bool { baselineDayCount >= 3 }

    var baselineProgressText: String {
        baselineComplete ? "基线完成" : "基线采集中（\(baselineDayCount)/3 个工作日）"
    }

    var focusElapsedSeconds: Int {
        guard let focus = currentFocus else { return 0 }
        return max(0, Int((focus.endedAt ?? now).timeIntervalSince(focus.startedAt)))
    }

    var focusRemainingSeconds: Int {
        guard let focus = currentFocus else { return 0 }
        return max(0, focus.targetSeconds - focusElapsedSeconds)
    }

    var todayTrainingCount: Int {
        let interval = dayInterval(for: Date())
        return focusSessions.filter { interval.contains($0.startedAt) }.count
    }

    var selectedActivities: [ActivitySegmentModel] {
        let interval = dayInterval(for: selectedDate)
        return activities.filter { item in
            let end = item.endedAt ?? now
            return item.startedAt < interval.end && end >= interval.start
        }
    }

    var selectedTaskIntervals: [TaskIntervalModel] {
        let interval = dayInterval(for: selectedDate)
        return taskIntervals.filter { item in
            let end = item.endedAt ?? now
            return item.startedAt < interval.end && end >= interval.start
        }
    }

    var selectedInterruptions: [InterruptionModel] {
        let interval = dayInterval(for: selectedDate)
        return interruptions.filter { interval.contains($0.detectedAt) }
    }

    var selectedMarkers: [TimelineMarkerModel] {
        let interval = dayInterval(for: selectedDate)
        return markers.filter { interval.contains($0.date) }
    }

    var selectedSummary: DailySummary {
        MetricsEngine.dailySummary(
            activities: selectedActivities.map(\.record),
            taskIntervals: selectedTaskIntervals.map(\.record),
            interruptions: selectedInterruptions.map(\.record),
            now: now
        )
    }

    var analysisResult: AnalysisResult {
        let plan = currentPlan
        let result = AdaptiveAnalyzer.analyze(
            activities: activities.map(\.record),
            sessions: focusSessions.filter { $0.endedAt != nil }.map(\.record),
            interruptions: interruptions.map(\.record),
            currentPlan: plan.record
        )
        guard result.readiness == .ready, plan.version > 1 else { return result }
        let sessionsOnPlan = focusSessions.filter {
            $0.endedAt != nil && $0.startedAt >= plan.effectiveAt
        }.count
        let planAge = Date().timeIntervalSince(plan.effectiveAt)
        guard sessionsOnPlan >= 5, planAge >= 7 * 86_400 else {
            return AnalysisResult(
                readiness: .ready,
                suggestion: AnalysisSuggestion(
                    kind: .maintainPlan,
                    title: "继续验证当前计划",
                    evidence: "当前版本已完成 \(sessionsOnPlan)/5 次训练；同时需至少运行 7 天后再提出下一项调整。"
                ),
                insights: result.insights
            )
        }
        return result
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        if let loadWarning = store.loadWarning {
            errorMessage = loadWarning
        }
        recoverInterruptedState()
        reloadAll()
        ensureInitialPlan()
        purgeExpiredData()
        configureWorkspaceMonitor()
        notificationRouter.state = self
        notificationRouter.configure()
        workspaceMonitor.start()
        refreshCaptureForCurrentState()
        startScheduleObserver()
    }

    func completeOnboarding() {
        preferences.completeOnboarding()
        refreshCaptureForCurrentState()
    }

    func setCapturePaused(_ paused: Bool) {
        preferences.capturePaused = paused
        if paused {
            stopCurrentActivity(at: Date())
        } else {
            refreshCaptureForCurrentState()
        }
        objectWillChange.send()
    }

    func createTask(
        title: String,
        expectedOutcome: String,
        allowedBundleIDs: Set<String>
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let task = FocusTaskModel(
            title: cleanTitle,
            expectedOutcome: expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines),
            allowedBundleIDs: Array(allowedBundleIDs).sorted()
        )
        store.insert(task)
        tasks.append(task)
        saveOrReport()
        switchTask(to: task.id)
    }

    func updateTask(
        id: UUID,
        title: String,
        expectedOutcome: String,
        allowedBundleIDs: Set<String>
    ) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        task.title = cleanTitle
        task.expectedOutcome = expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines)
        task.allowedBundleIDs = Array(allowedBundleIDs).sorted()
        saveOrReport()
        objectWillChange.send()
    }

    func archiveTask(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        if currentTaskID == id { switchTask(to: nil) }
        task.isArchived = true
        saveOrReport()
        objectWillChange.send()
    }

    func switchTask(to taskID: UUID?) {
        let date = Date()
        if currentFocusID != nil {
            endFocus()
        }
        if let activeTaskInterval {
            activeTaskInterval.endedAt = date
            self.activeTaskInterval = nil
        }
        currentTaskID = taskID
        if let taskID {
            let interval = TaskIntervalModel(taskID: taskID, startedAt: date)
            store.insert(interval)
            taskIntervals.append(interval)
            activeTaskInterval = interval
        }
        insertMarker(.taskChanged, at: date, taskID: taskID)
        resegmentCurrentApp(at: date)
        saveOrReport()
        showTaskSwitcher = false
    }

    func startFocus(minutes: Int? = nil) {
        guard let taskID = currentTaskID, currentFocusID == nil else { return }
        let targetMinutes = min(50, max(10, minutes ?? currentPlan.focusMinutes))
        let focus = FocusSessionModel(taskID: taskID, targetSeconds: targetMinutes * 60)
        store.insert(focus)
        focusSessions.append(focus)
        currentFocusID = focus.id
        resegmentCurrentApp(at: focus.startedAt)
        startFocusClock()
        saveOrReport()
    }

    func endFocus() {
        guard let focus = currentFocus else { return }
        let date = Date()
        focus.endedAt = date
        let confirmed = interruptions.filter {
            $0.focusSessionID == focus.id
                && ($0.resolution == .returnedToTask || $0.resolution == .endedSession)
        }.count
        focus.confirmedDistractionCount = confirmed
        currentFocusID = nil
        focusClockTask?.cancel()
        focusClockTask = nil
        distractionTask?.cancel()
        distractionTask = nil
        pendingSessionReview = PendingSessionReview(
            id: focus.id,
            targetMinutes: focus.targetSeconds / 60,
            elapsedSeconds: Int(date.timeIntervalSince(focus.startedAt))
        )
        resegmentCurrentApp(at: date)
        saveOrReport()
    }

    func completeSessionReview(id: UUID, outcome: FocusOutcome, difficulty: Int) {
        guard let focus = focusSessions.first(where: { $0.id == id }) else { return }
        focus.outcome = outcome
        focus.difficulty = min(5, max(1, difficulty))
        pendingSessionReview = nil
        saveOrReport()
        refreshTrainingProposal()
    }

    func returnToTask(interruptionID: UUID) {
        resolveInterruption(interruptionID, as: .returnedToTask)
        if let bundleID = lastAllowedBundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
        }
        showMainWindow()
    }

    func markNecessary(interruptionID: UUID) {
        guard let interruption = interruption(with: interruptionID) else { return }
        resolveInterruption(interruptionID, as: .markedNecessary)
        if let task = tasks.first(where: { $0.id == interruption.taskID }),
           !task.allowedBundleIDs.contains(interruption.bundleID) {
            task.allowedBundleIDs.append(interruption.bundleID)
            task.allowedBundleIDs.sort()
            saveOrReport()
        }
    }

    func prepareTaskSwitch(interruptionID: UUID) {
        resolveInterruption(interruptionID, as: .switchedTask)
        showTaskSwitcher = true
        showMainWindow()
    }

    func endFocusFromInterruption(interruptionID: UUID) {
        resolveInterruption(interruptionID, as: .endedSession)
        endFocus()
    }

    func resolveInterruption(_ id: UUID, as resolution: InterruptionResolution) {
        guard let interruption = interruption(with: id), interruption.resolution == .unresolved else { return }
        interruption.resolution = resolution
        interruption.resolvedAt = Date()
        if let activity = activities.first(where: { $0.id == interruption.activityID }) {
            switch resolution {
            case .markedNecessary:
                activity.classification = .necessary
            case .switchedTask:
                activity.classification = .taskSwitch
            case .returnedToTask, .endedSession:
                activity.classification = .confirmedDistraction
            case .unresolved:
                activity.classification = .suspectedDistraction
            }
        }
        saveOrReport()
        objectWillChange.send()
    }

    func acceptTrainingProposal() {
        guard let proposal = trainingProposal else { return }
        createTrainingPlan(focusMinutes: proposal.focusMinutes, reason: "\(proposal.title)：\(proposal.evidence)")
        trainingProposal = nil
    }

    func dismissTrainingProposal() {
        trainingProposal = nil
    }

    func applyAnalysisSuggestion(_ suggestion: AnalysisSuggestion) {
        createTrainingPlan(
            focusMinutes: suggestion.proposedFocusMinutes ?? currentPlan.focusMinutes,
            reason: "\(suggestion.title)：\(suggestion.evidence)"
        )
    }

    func revertToPreviousPlan() {
        guard trainingPlans.count >= 2 else { return }
        let sorted = trainingPlans.sorted { $0.version < $1.version }
        let previous = sorted[sorted.count - 2]
        createTrainingPlan(focusMinutes: previous.focusMinutes, reason: "回退到版本 \(previous.version) 的训练时长")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            preferences.launchAtLogin = enabled
        } catch {
            errorMessage = "登录启动设置失败：\(error.localizedDescription)"
            preferences.launchAtLogin = false
        }
    }

    func shutdown() {
        let date = Date()
        if let focus = currentFocus, focus.endedAt == nil {
            focus.endedAt = date
            focus.outcome = .pending
        }
        currentFocusID = nil
        if let activeTaskInterval, activeTaskInterval.endedAt == nil {
            activeTaskInterval.endedAt = date
        }
        self.activeTaskInterval = nil
        currentTaskID = nil
        stopCurrentActivity(at: date)
        do {
            try store.flush()
        } catch {
            errorMessage = "退出前保存失败：\(error.localizedDescription)"
        }
    }

    func exportBundle() -> ExportBundle {
        ExportBundle(
            tasks: tasks.map(\.record),
            taskIntervals: taskIntervals.map(\.record),
            activities: activities.map(\.record),
            focusSessions: focusSessions.map(\.record),
            interruptions: interruptions.map(\.record),
            trainingPlans: trainingPlans.map(\.record),
            markers: markers.map(\.record)
        )
    }

    func writeJSON(to url: URL) {
        do {
            try ExportEngine.jsonData(exportBundle()).write(to: url, options: .atomic)
        } catch {
            errorMessage = "JSON 导出失败：\(error.localizedDescription)"
        }
    }

    func writeCSV(to url: URL) {
        do {
            try ExportEngine.activitiesCSV(activities.map(\.record)).write(
                to: url,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            errorMessage = "CSV 导出失败：\(error.localizedDescription)"
        }
    }

    func deleteSelectedDay() {
        let interval = dayInterval(for: selectedDate)
        activities.filter { interval.contains($0.startedAt) }.forEach { store.delete($0) }
        taskIntervals.filter { interval.contains($0.startedAt) }.forEach { store.delete($0) }
        focusSessions.filter { interval.contains($0.startedAt) }.forEach { store.delete($0) }
        interruptions.filter { interval.contains($0.detectedAt) }.forEach { store.delete($0) }
        markers.filter { interval.contains($0.date) }.forEach { store.delete($0) }
        saveOrReport()
        reloadAll()
    }

    func deleteAllBehaviorData() {
        stopCurrentActivity(at: Date())
        taskIntervals.forEach { store.delete($0) }
        activities.forEach { store.delete($0) }
        focusSessions.forEach { store.delete($0) }
        interruptions.forEach { store.delete($0) }
        markers.forEach { store.delete($0) }
        trainingPlans.forEach { store.delete($0) }
        currentTaskID = nil
        currentFocusID = nil
        activeTaskInterval = nil
        pendingSessionReview = nil
        trainingProposal = nil
        saveOrReport()
        reloadAll()
        ensureInitialPlan()
        refreshCaptureForCurrentState()
    }

    func taskName(for id: UUID?) -> String {
        guard let id else { return "未标注" }
        return tasks.first(where: { $0.id == id })?.title ?? "已删除任务"
    }

    func runningApps() -> [AppIdentity] {
        WorkspaceMonitor.runningApps().filter { $0.bundleID != Bundle.main.bundleIdentifier }
    }

    private func configureWorkspaceMonitor() {
        workspaceMonitor.onAppActivated = { [weak self] app, date in
            self?.handleAppActivation(app, at: date)
        }
        workspaceMonitor.onSpaceChanged = { [weak self] date in
            self?.insertMarker(.activeSpaceChanged, at: date, taskID: self?.currentTaskID)
        }
        workspaceMonitor.onSystemInactive = { [weak self] source, date in
            self?.handleSystemInactive(source: source, at: date)
        }
        workspaceMonitor.onSystemActive = { [weak self] source, app, date in
            self?.handleSystemActive(source: source, app: app, at: date)
        }
    }

    private func handleAppActivation(_ app: AppIdentity, at date: Date) {
        now = date
        guard shouldRecord(at: date) else {
            stopCurrentActivity(at: date)
            return
        }
        let transition = captureMachine.activate(app, at: date)
        guard !transition.ignoredDuplicate else { return }
        closeActiveSegment(at: date)
        guard let opened = transition.opened else { return }
        openSegment(for: opened, source: .appActivation)
    }

    private func handleSystemInactive(source: ActivityEventSource, at date: Date) {
        guard isSystemActive else { return }
        isSystemActive = false
        _ = captureMachine.becomeInactive(at: date)
        closeActiveSegment(at: date)
        distractionTask?.cancel()
        distractionTask = nil
        insertMarker(source == .screenSleep ? .screenSlept : .sessionBecameInactive, at: date, taskID: currentTaskID)
    }

    private func handleSystemActive(source: ActivityEventSource, app: AppIdentity?, at date: Date) {
        guard !isSystemActive else { return }
        isSystemActive = true
        insertMarker(source == .screenWake ? .screenWoke : .sessionBecameActive, at: date, taskID: currentTaskID)
        guard shouldRecord(at: date) else { return }
        let transition = captureMachine.becomeActive(app, at: date)
        if let opened = transition.opened {
            openSegment(for: opened, source: source)
        }
    }

    private func openSegment(for opened: OpenActivity, source: ActivityEventSource) {
        let task = currentTask
        let isTracker = opened.app.bundleID == Bundle.main.bundleIdentifier
            || opened.app.bundleID == "com.local.FocusTrace"
        let isAllowed = isTracker
            || currentFocusID == nil
            || task?.allowedBundleIDs.contains(opened.app.bundleID) == true
        let classification: ActivityClassification = isTracker ? .trackerControl : .allowed
        let segment = ActivitySegmentModel(
            id: opened.id,
            appName: opened.app.name,
            bundleID: opened.app.bundleID,
            startedAt: opened.startedAt,
            taskID: currentTaskID,
            focusSessionID: currentFocusID,
            classification: classification,
            source: source,
            isAllowedApp: isAllowed
        )
        store.insert(segment)
        activities.append(segment)
        activeSegment = segment
        if isAllowed, !isTracker {
            lastAllowedBundleID = opened.app.bundleID
        }
        saveOrReport()
        if !isAllowed {
            scheduleDistractionCheck(for: segment)
        }
    }

    private func closeActiveSegment(at date: Date) {
        distractionTask?.cancel()
        distractionTask = nil
        if let segment = activeSegment, segment.endedAt == nil {
            segment.endedAt = max(segment.startedAt, date)
        }
        activeSegment = nil
        saveOrReport()
    }

    private func stopCurrentActivity(at date: Date) {
        _ = captureMachine.stop(at: date)
        closeActiveSegment(at: date)
    }

    private func resegmentCurrentApp(at date: Date, classification: ActivityClassification? = nil) {
        let app = workspaceMonitor.frontmostApp
        stopCurrentActivity(at: date)
        guard shouldRecord(at: date), let app else { return }
        let transition = captureMachine.activate(app, at: date)
        if let opened = transition.opened {
            openSegment(for: opened, source: .appActivation)
            if let classification, let activeSegment {
                activeSegment.classification = classification
                saveOrReport()
            }
        }
    }

    private func scheduleDistractionCheck(for segment: ActivitySegmentModel) {
        distractionTask?.cancel()
        let segmentID = segment.id
        let threshold = max(5, preferences.reminderThresholdSeconds)
        distractionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(threshold))
            guard !Task.isCancelled else { return }
            self?.flagSuspectedDistraction(segmentID: segmentID)
        }
    }

    private func flagSuspectedDistraction(segmentID: UUID) {
        guard baselineComplete,
              let segment = activeSegment,
              segment.id == segmentID,
              segment.endedAt == nil,
              !segment.isAllowedApp,
              !segment.crossedReminderThreshold,
              let focusID = currentFocusID,
              let taskID = currentTaskID else {
            return
        }
        segment.crossedReminderThreshold = true
        segment.classification = .suspectedDistraction
        let interruption = InterruptionModel(
            activityID: segment.id,
            focusSessionID: focusID,
            taskID: taskID,
            appName: segment.appName,
            bundleID: segment.bundleID
        )
        store.insert(interruption)
        interruptions.append(interruption)
        insertMarker(.reminderSent, at: interruption.detectedAt, taskID: taskID)
        saveOrReport()
        notificationRouter.sendInterruption(
            id: interruption.id,
            appName: segment.appName,
            taskName: taskName(for: taskID)
        )
    }

    private func startFocusClock() {
        focusClockTask?.cancel()
        focusClockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.now = Date()
                guard let focus = self.currentFocus else { return }
                if !focus.targetNotificationSent && self.focusElapsedSeconds >= focus.targetSeconds {
                    focus.targetNotificationSent = true
                    self.notificationRouter.sendTargetReached(minutes: focus.targetSeconds / 60)
                    self.saveOrReport()
                }
            }
        }
    }

    private func startScheduleObserver() {
        scheduleTask?.cancel()
        scheduleTask = Task { [weak self] in
            var wasRecording = self?.shouldRecord(at: Date()) ?? false
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                let date = Date()
                self.now = date
                let shouldRecord = self.shouldRecord(at: date)
                if shouldRecord != wasRecording {
                    self.refreshCaptureForCurrentState()
                    wasRecording = shouldRecord
                }
            }
        }
    }

    private func refreshCaptureForCurrentState() {
        let date = Date()
        now = date
        guard shouldRecord(at: date), isSystemActive, let app = workspaceMonitor.frontmostApp else {
            stopCurrentActivity(at: date)
            return
        }
        handleAppActivation(app, at: date)
    }

    private func shouldRecord(at date: Date) -> Bool {
        preferences.hasCompletedOnboarding
            && !preferences.capturePaused
            && preferences.isWithinWorkSchedule(date)
    }

    private func refreshTrainingProposal() {
        let plan = currentPlan
        let completed = focusSessions
            .filter { $0.endedAt != nil && $0.outcome != .pending && $0.startedAt >= plan.effectiveAt }
            .sorted { $0.startedAt < $1.startedAt }

        if baselineComplete && plan.version == 1 {
            let baselineMinutes = TrainingEngine.initialFocusMinutes(
                baselineStreaks: TrainingEngine.baselineStreaks(from: activities.map(\.record))
            )
            if baselineMinutes != plan.focusMinutes {
                trainingProposal = TrainingProposal(
                    title: "使用个人基线设置首轮训练",
                    evidence: "根据前 3 个工作日的中位连续专注时长，建议 \(baselineMinutes) 分钟。",
                    focusMinutes: baselineMinutes
                )
                return
            }
        }

        guard completed.count >= 5, completed.count.isMultiple(of: 5) else { return }
        let lastFive = Array(completed.suffix(5)).map(\.record)
        guard let adjustment = TrainingEngine.progression(
            currentMinutes: plan.focusMinutes,
            lastFive: lastFive
        ) else { return }
        switch adjustment {
        case let .increase(minutes) where minutes != plan.focusMinutes:
            trainingProposal = TrainingProposal(
                title: "训练增加到 \(minutes) 分钟",
                evidence: "最近 5 次训练至少 4 次成功。",
                focusMinutes: minutes
            )
        case let .decrease(minutes) where minutes != plan.focusMinutes:
            trainingProposal = TrainingProposal(
                title: "训练降低到 \(minutes) 分钟",
                evidence: "最近 5 次训练成功不超过 2 次。先降低难度，再重建稳定性。",
                focusMinutes: minutes
            )
        default:
            break
        }
    }

    private func createTrainingPlan(focusMinutes: Int, reason: String) {
        let current = currentPlan
        let plan = TrainingPlanModel(
            version: current.version + 1,
            focusMinutes: min(50, max(10, focusMinutes)),
            sessionsPerDay: current.sessionsPerDay,
            breakMinutes: current.breakMinutes,
            reminderThresholdSeconds: preferences.reminderThresholdSeconds,
            reason: reason,
            previousPlanID: current.id
        )
        store.insert(plan)
        trainingPlans.append(plan)
        saveOrReport()
    }

    private func ensureInitialPlan() {
        guard trainingPlans.isEmpty else {
            refreshTrainingProposal()
            return
        }
        let plan = TrainingPlanModel(
            version: 1,
            focusMinutes: 15,
            reminderThresholdSeconds: preferences.reminderThresholdSeconds,
            reason: "基线数据不足，使用默认 15 分钟"
        )
        store.insert(plan)
        trainingPlans.append(plan)
        saveOrReport()
    }

    private func interruption(with id: UUID) -> InterruptionModel? {
        interruptions.first { $0.id == id }
    }

    private func insertMarker(_ kind: TimelineMarkerKind, at date: Date, taskID: UUID?) {
        let marker = TimelineMarkerModel(date: date, kind: kind, taskID: taskID)
        store.insert(marker)
        markers.append(marker)
        saveOrReport()
    }

    private func recoverInterruptedState() {
        let now = Date()
        do {
            for item in store.activities where item.endedAt == nil {
                item.endedAt = min(now, item.startedAt.addingTimeInterval(300))
                item.source = .recovery
            }
            for item in store.taskIntervals where item.endedAt == nil {
                item.endedAt = min(now, item.startedAt.addingTimeInterval(300))
            }
            for item in store.focusSessions where item.endedAt == nil {
                item.endedAt = min(now, item.startedAt.addingTimeInterval(Double(item.targetSeconds)))
                item.outcome = .pending
            }
            try store.flush()
        } catch {
            errorMessage = "恢复上次记录失败：\(error.localizedDescription)"
        }
    }

    private func purgeExpiredData() {
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -max(1, preferences.retentionDays),
            to: Date()
        ) else { return }
        activities.filter { ($0.endedAt ?? $0.startedAt) < cutoff }.forEach { store.delete($0) }
        taskIntervals.filter { ($0.endedAt ?? $0.startedAt) < cutoff }.forEach { store.delete($0) }
        focusSessions.filter { ($0.endedAt ?? $0.startedAt) < cutoff }.forEach { store.delete($0) }
        interruptions.filter { $0.detectedAt < cutoff }.forEach { store.delete($0) }
        markers.filter { $0.date < cutoff }.forEach { store.delete($0) }
        saveOrReport()
        reloadAll()
    }

    private func reloadAll() {
        tasks = store.tasks.sorted { $0.createdAt < $1.createdAt }
        taskIntervals = store.taskIntervals.sorted { $0.startedAt < $1.startedAt }
        activities = store.activities.sorted { $0.startedAt < $1.startedAt }
        focusSessions = store.focusSessions.sorted { $0.startedAt < $1.startedAt }
        interruptions = store.interruptions.sorted { $0.detectedAt < $1.detectedAt }
        trainingPlans = store.trainingPlans.sorted { $0.version < $1.version }
        markers = store.markers.sorted { $0.date < $1.date }
    }

    private func saveOrReport() {
        do {
            try store.save()
        } catch {
            errorMessage = "保存本地数据失败：\(error.localizedDescription)"
        }
    }

    private func dayInterval(for date: Date) -> DateInterval {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }
}
