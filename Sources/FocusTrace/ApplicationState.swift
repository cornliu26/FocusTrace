@preconcurrency import AppKit
import Combine
import Foundation
import FocusTraceCore
import FocusTraceMacSupport

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

struct PendingWorkflowUndo: Identifiable, Equatable {
    let id: UUID
    let workflowID: UUID
    let title: String
    let expiresAt: Date
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
    @Published private(set) var taskParkings: [TaskParkingModel] = []
    @Published private(set) var workflowSpaceBindings: [WorkflowSpaceBindingModel] = []
    @Published private(set) var spaceResolution: WorkflowSpaceResolution = .unknown

    @Published var selectedDate = Calendar.current.startOfDay(for: Date())
    @Published private(set) var currentTaskID: UUID?
    @Published private(set) var currentFocusID: UUID?
    @Published private(set) var pendingFocusDepartureAt: Date?
    @Published private(set) var now = Date()
    @Published var pendingSessionReview: PendingSessionReview?
    @Published private(set) var pendingWorkflowUndo: PendingWorkflowUndo?
    @Published var trainingProposal: TrainingProposal?
    @Published var showTaskSwitcher = false
    @Published var showTaskCreator = false
    @Published var showTaskParking = false
    @Published var showQuickStart = false
    @Published var errorMessage: String?
    @Published private(set) var isSystemActive = true

    private var captureMachine = ActivityCaptureStateMachine()
    private var activeSegment: ActivitySegmentModel?
    private var activeTaskInterval: TaskIntervalModel?
    private var distractionTask: Task<Void, Never>?
    private var focusClockTask: Task<Void, Never>?
    private var focusDepartureTask: Task<Void, Never>?
    private var scheduleTask: Task<Void, Never>?
    private var spaceResolutionTask: Task<Void, Never>?
    private var workflowUndoTask: Task<Void, Never>?
    private var lastAllowedBundleID: String?
    private var hasStarted = false

    private let workspaceMonitor = WorkspaceMonitor()
    private let notificationRouter = NotificationRouter()
    private let spaceAnchorRegistry = SpaceAnchorRegistry()

    init(store: FocusTraceStore, preferences: AppPreferences = AppPreferences()) {
        self.store = store
        self.preferences = preferences
    }

    deinit {
        distractionTask?.cancel()
        focusClockTask?.cancel()
        focusDepartureTask?.cancel()
        scheduleTask?.cancel()
        spaceResolutionTask?.cancel()
        workflowUndoTask?.cancel()
    }

    var activeTasks: [FocusTaskModel] {
        tasks.filter { $0.workflowLifecycle == .open }
    }

    var completedWorkflows: [FocusTaskModel] {
        tasks.filter { $0.workflowLifecycle == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var currentTask: FocusTaskModel? {
        guard let currentTaskID else { return nil }
        return tasks.first { $0.id == currentTaskID }
    }

    var currentFocus: FocusSessionModel? {
        guard let currentFocusID else { return nil }
        return focusSessions.first { $0.id == currentFocusID }
    }

    var isSpaceWorkflowModeEnabled: Bool {
        spaceAnchorRegistry.isEnabled
    }

    var currentSpaceWorkflowID: UUID? {
        guard case let .bound(workflowID) = spaceResolution else { return nil }
        return workflowID
    }

    var currentSpaceWorkflow: FocusTaskModel? {
        guard let currentSpaceWorkflowID else { return nil }
        return tasks.first { $0.id == currentSpaceWorkflowID }
    }

    var needsRebindBindings: [WorkflowSpaceBindingModel] {
        workflowSpaceBindings
            .filter { $0.state == .needsRebind }
            .sorted { $0.boundAt < $1.boundAt }
    }

    var spaceContextText: String {
        guard isSpaceWorkflowModeEnabled else {
            return needsRebindBindings.isEmpty ? "桌面工作流未启用" : "桌面绑定待恢复"
        }
        switch spaceResolution {
        case let .bound(workflowID):
            return "当前桌面 · \(taskName(for: workflowID))"
        case .unbound:
            return "当前桌面未绑定"
        case .unknown:
            return "正在识别当前桌面"
        case .conflict:
            return "当前桌面存在绑定冲突"
        }
    }

    var activeTaskParkings: [TaskParkingModel] {
        taskParkings
            .filter(\.isActive)
            .sorted {
                switch ($0.remindAt, $1.remindAt) {
                case let (left?, right?): return left < right
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return $0.parkedAt > $1.parkedAt
                }
            }
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
        return activeFocusElapsedSeconds(focus, at: focus.endedAt ?? now)
    }

    var focusRemainingSeconds: Int {
        guard let focus = currentFocus else { return 0 }
        return max(0, focus.targetSeconds - focusElapsedSeconds)
    }

    var isCurrentFocusPaused: Bool {
        currentFocus?.pausedAt != nil
    }

    var focusDepartureGraceRemaining: Int? {
        guard currentFocus?.pausedAt == nil, let pendingFocusDepartureAt else { return nil }
        return max(0, 10 - Int(now.timeIntervalSince(pendingFocusDepartureAt)))
    }

    var focusWorkflowName: String {
        taskName(for: currentFocus?.taskID)
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

    var selectedTaskParkings: [TaskParkingModel] {
        let interval = dayInterval(for: selectedDate)
        return taskParkings.filter { interval.contains($0.parkedAt) }
    }

    var selectedSummary: DailySummary {
        MetricsEngine.dailySummary(
            activities: selectedActivities.map(\.record),
            taskIntervals: selectedTaskIntervals.map(\.record),
            interruptions: selectedInterruptions.map(\.record),
            taskParkings: selectedTaskParkings.map(\.record),
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
        prepareStoredSpaceBindingsForLaunch()
        ensureInitialPlan()
        purgeExpiredData()
        configureWorkspaceMonitor()
        notificationRouter.state = self
        notificationRouter.configure()
        sendDueTaskParkingReminders(at: Date())
        workspaceMonitor.start()
        refreshCaptureForCurrentState()
        startScheduleObserver()
    }

    func completeOnboarding() {
        preferences.completeOnboarding()
        refreshCaptureForCurrentState()
    }

    func completeOnboardingAndCreateTask(
        title: String,
        expectedOutcome: String,
        allowedBundleIDs: Set<String>
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !allowedBundleIDs.isEmpty else { return }
        createTask(
            title: cleanTitle,
            expectedOutcome: expectedOutcome,
            allowedBundleIDs: allowedBundleIDs
        )
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

    func createWorkflowAndBindCurrentSpace(
        title: String,
        expectedOutcome: String = ""
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let workflow = FocusTaskModel(
            title: cleanTitle,
            expectedOutcome: expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines),
            allowedBundleIDs: []
        )
        store.insert(workflow)
        tasks.append(workflow)
        saveOrReport()
        bindCurrentSpace(to: workflow.id)
    }

    var suggestedWorkflowTitle: String {
        "工作流 \(tasks.count + 1)"
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
        if currentFocus?.taskID == id { endFocus() }
        if currentTaskID == id { switchTask(to: nil, source: .space) }
        let date = Date()
        releaseAllSpaceBindings(for: id, state: .released)
        activeTaskParkings
            .filter { $0.taskID == id }
            .forEach { $0.dismissedAt = date }
        task.isArchived = true
        task.workflowLifecycleRaw = WorkflowLifecycle.archived.rawValue
        saveOrReport()
        objectWillChange.send()
    }

    func bindCurrentSpace(to workflowID: UUID) {
        guard tasks.contains(where: {
            $0.id == workflowID && $0.workflowLifecycle == .open
        }) else {
            errorMessage = "只能把桌面绑定到进行中的工作流。"
            return
        }

        let reusable = workflowSpaceBindings.first {
            $0.workflowID == workflowID
                && $0.state == .needsRebind
                && !spaceAnchorRegistry.contains(bindingID: $0.id)
        }
        let bindingID = reusable?.id ?? UUID()
        let restorationID = reusable?.anchorRestorationID ?? UUID().uuidString

        switch spaceAnchorRegistry.bindCurrentSpace(
            workflowID: workflowID,
            bindingID: bindingID,
            restorationID: restorationID
        ) {
        case .created:
            let date = Date()
            if let reusable {
                reusable.state = .verified
                reusable.lastVerifiedAt = date
            } else {
                let binding = WorkflowSpaceBindingModel(
                    id: bindingID,
                    workflowID: workflowID,
                    anchorRestorationID: restorationID,
                    state: .verified,
                    boundAt: date,
                    lastVerifiedAt: date
                )
                store.insert(binding)
                workflowSpaceBindings.append(binding)
            }
            applySpaceResolution(spaceAnchorRegistry.resolution(), at: date, source: .space)
            saveOrReport()

        case .alreadyBound:
            applySpaceResolution(spaceAnchorRegistry.resolution(), at: Date(), source: .space)

        case let .occupied(existingWorkflowID):
            errorMessage = "当前桌面已绑定到“\(taskName(for: existingWorkflowID))”。请先解除当前桌面绑定。"

        case .failed:
            errorMessage = "无法确认当前桌面绑定。FocusTrace 没有保存这次绑定，请重试。"
        }
    }

    func unbindCurrentSpace() {
        let releasedIDs = spaceAnchorRegistry.releaseCurrentSpace()
        guard !releasedIDs.isEmpty else { return }
        for binding in workflowSpaceBindings where releasedIDs.contains(binding.id) {
            binding.state = .released
        }
        let stillEnabled = spaceAnchorRegistry.isEnabled
        if stillEnabled {
            applySpaceResolution(spaceAnchorRegistry.resolution(), at: Date(), source: .space)
        } else {
            spaceResolution = .unknown
            switchTask(to: nil, source: .space)
        }
        saveOrReport()
        objectWillChange.send()
    }

    func completeWorkflow(_ id: UUID) {
        guard let workflow = tasks.first(where: { $0.id == id && $0.workflowLifecycle == .open }) else {
            return
        }
        let date = Date()
        if currentFocus?.taskID == id { endFocus() }
        if currentTaskID == id { switchTask(to: nil, source: .space) }
        activeTaskParkings
            .filter { $0.taskID == id }
            .forEach { $0.dismissedAt = date }
        releaseAllSpaceBindings(for: id, state: .released)
        workflow.workflowLifecycleRaw = WorkflowLifecycle.completed.rawValue
        workflow.completedAt = date
        workflow.isArchived = false
        pendingWorkflowUndo = PendingWorkflowUndo(
            id: UUID(),
            workflowID: id,
            title: workflow.title,
            expiresAt: date.addingTimeInterval(30)
        )
        workflowUndoTask?.cancel()
        workflowUndoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.pendingWorkflowUndo = nil
        }
        saveOrReport()
        objectWillChange.send()
    }

    func undoWorkflowCompletion() {
        guard let pendingWorkflowUndo,
              pendingWorkflowUndo.expiresAt >= Date(),
              let workflow = tasks.first(where: { $0.id == pendingWorkflowUndo.workflowID }) else {
            self.pendingWorkflowUndo = nil
            return
        }
        workflow.workflowLifecycleRaw = WorkflowLifecycle.open.rawValue
        workflow.completedAt = nil
        workflow.isArchived = false
        for binding in workflowSpaceBindings
            where binding.workflowID == workflow.id && binding.state == .released {
            binding.state = .needsRebind
        }
        workflowUndoTask?.cancel()
        workflowUndoTask = nil
        self.pendingWorkflowUndo = nil
        saveOrReport()
        objectWillChange.send()
    }

    func reopenWorkflow(_ id: UUID) {
        guard let workflow = tasks.first(where: { $0.id == id && $0.workflowLifecycle != .open }) else {
            return
        }
        workflow.workflowLifecycleRaw = WorkflowLifecycle.open.rawValue
        workflow.completedAt = nil
        workflow.isArchived = false
        for binding in workflowSpaceBindings
            where binding.workflowID == workflow.id && binding.state == .released {
            binding.state = .needsRebind
        }
        saveOrReport()
        objectWillChange.send()
    }

    func switchTask(
        to taskID: UUID?,
        source: WorkflowIntervalSource = .manual,
        at date: Date = Date()
    ) {
        if source == .manual,
           spaceAnchorRegistry.isEnabled,
           taskID != currentSpaceWorkflowID {
            errorMessage = currentSpaceWorkflowID == nil
                ? "桌面工作流模式已启用。请先把当前桌面绑定到要处理的工作流。"
                : "当前桌面已绑定到“\(taskName(for: currentSpaceWorkflowID))”。请先解除绑定，再绑定新的工作流。"
            showTaskSwitcher = false
            return
        }
        if taskID == currentTaskID {
            if source == .space {
                handleFocusWorkflowContextChange(to: taskID, at: date)
            }
            if let taskID,
               let parking = activeTaskParkings.first(where: { $0.taskID == taskID }) {
                resolveTaskParking(parking, resumedAt: date)
            }
            showTaskSwitcher = false
            return
        }
        if currentFocusID != nil && source != .space {
            endFocus()
        }
        if let taskID,
           let parking = activeTaskParkings.first(where: { $0.taskID == taskID }) {
            resolveTaskParking(parking, resumedAt: date)
        }
        if let activeTaskInterval {
            activeTaskInterval.endedAt = date
            self.activeTaskInterval = nil
        }
        currentTaskID = taskID
        if let taskID {
            let interval = TaskIntervalModel(
                taskID: taskID,
                startedAt: date,
                workflowSource: source
            )
            store.insert(interval)
            taskIntervals.append(interval)
            activeTaskInterval = interval
        }
        if source == .space {
            handleFocusWorkflowContextChange(to: taskID, at: date)
        }
        insertMarker(source == .space ? .workflowChanged : .taskChanged, at: date, taskID: taskID)
        resegmentCurrentApp(at: date)
        saveOrReport()
        showTaskSwitcher = false
    }

    func parkCurrentTask(
        resumeCue: String,
        reminderMinutes: Int?,
        switchTo destinationTaskID: UUID?
    ) {
        guard let taskID = currentTaskID else { return }
        let cleanCue = resumeCue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCue.isEmpty, destinationTaskID != taskID else { return }
        if currentFocusID != nil {
            endFocus()
        }
        let date = Date()

        // A second parking point supersedes the older unresolved cue for the
        // same task, keeping the return list unambiguous.
        activeTaskParkings
            .filter { $0.taskID == taskID }
            .forEach { $0.dismissedAt = date }
        let reminder = reminderMinutes.flatMap {
            Calendar.current.date(byAdding: .minute, value: max(1, $0), to: date)
        }
        let parking = TaskParkingModel(
            taskID: taskID,
            parkedAt: date,
            resumeCue: cleanCue,
            remindAt: reminder,
            switchedToTaskID: destinationTaskID
        )
        store.insert(parking)
        taskParkings.append(parking)
        insertMarker(.taskParked, at: date, taskID: taskID)
        if spaceAnchorRegistry.isEnabled {
            // Parking changes presence, not the Space binding. The workflow
            // becomes active again only when its bound Space is re-entered.
            switchTask(to: nil, source: .space, at: date)
        } else {
            switchTask(to: destinationTaskID, at: date)
        }
        showTaskParking = false
        saveOrReport()
    }

    func resumeTaskParking(_ id: UUID) {
        guard let parking = taskParkings.first(where: { $0.id == id && $0.isActive }) else { return }
        switchTask(to: parking.taskID)
        showMainWindow()
    }

    func dismissTaskParking(_ id: UUID) {
        guard let parking = taskParkings.first(where: { $0.id == id && $0.isActive }) else { return }
        parking.dismissedAt = Date()
        saveOrReport()
        objectWillChange.send()
    }

    func startFocus(minutes: Int? = nil) {
        guard let taskID = currentTaskID, currentFocusID == nil else { return }
        focusDepartureTask?.cancel()
        focusDepartureTask = nil
        pendingFocusDepartureAt = nil
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
        focusDepartureTask?.cancel()
        focusDepartureTask = nil
        pendingFocusDepartureAt = nil
        finishCurrentPause(for: focus, at: date)
        let elapsedSeconds = activeFocusElapsedSeconds(focus, at: date)
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
            elapsedSeconds: elapsedSeconds
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
        spaceResolutionTask?.cancel()
        workflowUndoTask?.cancel()
        focusDepartureTask?.cancel()
        focusDepartureTask = nil
        pendingFocusDepartureAt = nil
        spaceAnchorRegistry.releaseAll()
        spaceResolution = .unknown
        if let focus = currentFocus, focus.endedAt == nil {
            finishCurrentPause(for: focus, at: date)
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
            markers: markers.map(\.record),
            taskParkings: taskParkings.map(\.record)
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
        taskParkings.filter { interval.contains($0.parkedAt) }.forEach { store.delete($0) }
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
        taskParkings.forEach { store.delete($0) }
        trainingPlans.forEach { store.delete($0) }
        currentTaskID = nil
        currentFocusID = nil
        focusDepartureTask?.cancel()
        focusDepartureTask = nil
        pendingFocusDepartureAt = nil
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

    func verifiedSpaceBindingCount(for workflowID: UUID) -> Int {
        workflowSpaceBindings.filter {
            $0.workflowID == workflowID && $0.state == .verified
        }.count
    }

    func runningApps() -> [AppIdentity] {
        WorkspaceMonitor.runningApps().filter { $0.bundleID != Bundle.main.bundleIdentifier }
    }

    func availableApps() -> [AppIdentity] {
        var appsByBundleID = Dictionary(
            uniqueKeysWithValues: runningApps()
                .filter { isSelectableTool($0) }
                .map { ($0.bundleID, $0) }
        )
        var historicalDurationByBundleID: [String: TimeInterval] = [:]
        var historicalIdentityByBundleID: [String: AppIdentity] = [:]
        for activity in activities
            where ![.systemInactive, .trackerControl].contains(activity.classification) {
            let identity = AppIdentity(
                bundleID: activity.bundleID,
                name: activity.appName
            )
            guard activity.bundleID != Bundle.main.bundleIdentifier,
                  !SystemActivityGate.isSystemInactiveApp(identity),
                  isSelectableTool(identity) else { continue }
            historicalIdentityByBundleID[activity.bundleID] = identity
            historicalDurationByBundleID[activity.bundleID, default: 0] += max(
                0,
                (activity.endedAt ?? now).timeIntervalSince(activity.startedAt)
            )
        }
        for (bundleID, duration) in historicalDurationByBundleID where duration >= 60 {
            if let identity = historicalIdentityByBundleID[bundleID] {
                appsByBundleID[bundleID] = identity
            }
        }
        return appsByBundleID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func isSelectableTool(_ app: AppIdentity) -> Bool {
        let bundleID = app.bundleID.lowercased()
        let name = app.name.lowercased()
        return !bundleID.contains(".helper")
            && !bundleID.contains("uiagent")
            && !bundleID.contains(".xpc")
            && !name.contains("helper")
    }

    private func configureWorkspaceMonitor() {
        workspaceMonitor.onAppActivated = { [weak self] app, date in
            self?.handleAppActivation(app, at: date)
        }
        workspaceMonitor.onSpaceChanged = { [weak self] date in
            guard let self else { return }
            self.insertMarker(.activeSpaceChanged, at: date, taskID: self.currentTaskID)
            self.scheduleSpaceResolution(after: date)
        }
        workspaceMonitor.onSystemInactive = { [weak self] source, date in
            self?.handleSystemInactive(source: source, at: date)
        }
        workspaceMonitor.onSystemActive = { [weak self] source, app, date in
            self?.handleSystemActive(source: source, app: app, at: date)
        }
    }

    private func handleAppActivation(_ app: AppIdentity, at date: Date) {
        updateClock(to: date)
        guard shouldRecord(at: date) else {
            stopCurrentActivity(at: date)
            return
        }
        if SystemActivityGate.isSystemInactiveApp(app) {
            handleSystemInactive(source: .sessionInactive, at: date)
            return
        }
        if !isSystemActive {
            handleSystemActive(source: .sessionActive, app: app, at: date)
            return
        }
        let transition = captureMachine.activate(app, at: date)
        guard !transition.ignoredDuplicate else { return }
        closeActiveSegment(at: date)
        guard let opened = transition.opened else { return }
        openSegment(for: opened, source: .appActivation)
    }

    private func handleSystemInactive(source: ActivityEventSource, at date: Date) {
        guard isSystemActive else {
            if source == .screenSleep {
                insertMarkerIfNotRecent(.screenSlept, at: date, taskID: currentTaskID)
            }
            return
        }
        isSystemActive = false
        _ = captureMachine.becomeInactive(at: date)
        closeActiveSegment(at: date)
        distractionTask?.cancel()
        distractionTask = nil
        insertMarker(source == .screenSleep ? .screenSlept : .sessionBecameInactive, at: date, taskID: currentTaskID)
    }

    private func handleSystemActive(source: ActivityEventSource, app: AppIdentity?, at date: Date) {
        guard !isSystemActive else { return }
        if source == .screenWake {
            insertMarkerIfNotRecent(.screenWoke, at: date, taskID: currentTaskID)
        }
        guard let app, !SystemActivityGate.isSystemInactiveApp(app) else {
            // Waking to the lock screen is still inactive. Recording resumes
            // only after a real application becomes frontmost.
            return
        }
        isSystemActive = true
        if source != .screenWake {
            insertMarkerIfNotRecent(.sessionBecameActive, at: date, taskID: currentTaskID)
        }
        guard shouldRecord(at: date) else { return }
        let transition = captureMachine.becomeActive(app, at: date)
        if let opened = transition.opened {
            openSegment(for: opened, source: source)
        }
    }

    private func openSegment(for opened: OpenActivity, source: ActivityEventSource) {
        let task = currentTask
        let applicableFocusID: UUID? = currentFocus.flatMap { focus in
            guard focus.taskID == currentTaskID,
                  focus.pausedAt == nil,
                  pendingFocusDepartureAt == nil else { return nil }
            return focus.id
        }
        let isSystemInactive = SystemActivityGate.isSystemInactiveApp(opened.app)
        let isTracker = opened.app.bundleID == Bundle.main.bundleIdentifier
            || opened.app.bundleID == "com.local.FocusTrace"
        let isAllowed = !isSystemInactive && (isTracker
            || applicableFocusID == nil
            || task?.allowedBundleIDs.contains(opened.app.bundleID) == true)
        let classification: ActivityClassification = isSystemInactive
            ? .systemInactive
            : (isTracker ? .trackerControl : .allowed)
        let segment = ActivitySegmentModel(
            id: opened.id,
            appName: opened.app.name,
            bundleID: opened.app.bundleID,
            startedAt: opened.startedAt,
            taskID: currentTaskID,
            focusSessionID: applicableFocusID,
            classification: classification,
            source: source,
            isAllowedApp: isAllowed
        )
        store.insert(segment)
        activities.append(segment)
        activeSegment = segment
        if isAllowed, !isTracker, !isSystemInactive {
            lastAllowedBundleID = opened.app.bundleID
        }
        saveOrReport()
        if !isAllowed, !isSystemInactive {
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

    private func handleFocusWorkflowContextChange(to workflowID: UUID?, at date: Date) {
        guard let focus = currentFocus, focus.endedAt == nil else {
            focusDepartureTask?.cancel()
            focusDepartureTask = nil
            pendingFocusDepartureAt = nil
            return
        }

        let transition = FocusWorkflowDepartureEngine.contextChanged(
            focusDepartureState(for: focus),
            to: workflowID,
            at: date
        )
        applyFocusDepartureState(transition.state, to: focus)
        for effect in transition.effects {
            switch effect {
            case let .scheduleGrace(deadline):
                focusDepartureTask?.cancel()
                focusDepartureTask = Task { [weak self] in
                    let delay = max(0, deadline.timeIntervalSince(Date()))
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled, let self else { return }
                    self.pauseFocusAfterDepartureGrace()
                }
            case .cancelGrace:
                focusDepartureTask?.cancel()
                focusDepartureTask = nil
            case .paused:
                break
            case .resumed:
                insertMarker(.focusResumed, at: date, taskID: focus.taskID)
                saveOrReport()
                objectWillChange.send()
            }
        }
    }

    private func pauseFocusAfterDepartureGrace() {
        guard let focus = currentFocus,
              focus.endedAt == nil,
              focus.pausedAt == nil,
              pendingFocusDepartureAt != nil else { return }
        if case let .bound(activeWorkflowID) = spaceAnchorRegistry.resolution(),
           activeWorkflowID == focus.taskID {
            // The user returned just before the grace deadline while the
            // debounced context update is still pending. Trust the verified
            // anchor and avoid a one-frame false pause.
            pendingFocusDepartureAt = nil
            focusDepartureTask = nil
            return
        }
        guard focus.taskID != currentTaskID else { return }
        let transition = FocusWorkflowDepartureEngine.graceElapsed(
            focusDepartureState(for: focus)
        )
        guard transition.effects.contains(where: {
            if case .paused = $0 { return true }
            return false
        }) else { return }
        applyFocusDepartureState(transition.state, to: focus)
        focusDepartureTask = nil
        distractionTask?.cancel()
        distractionTask = nil
        let date = Date()
        updateClock(to: date)
        insertMarker(.focusPaused, at: date, taskID: focus.taskID)
        saveOrReport()
        objectWillChange.send()
    }

    private func finishCurrentPause(for focus: FocusSessionModel, at date: Date) {
        guard let pausedAt = focus.pausedAt else { return }
        focus.accumulatedPausedSeconds = max(0, focus.accumulatedPausedSeconds ?? 0)
            + max(0, date.timeIntervalSince(pausedAt))
        focus.pausedAt = nil
    }

    private func activeFocusElapsedSeconds(_ focus: FocusSessionModel, at date: Date) -> Int {
        FocusWorkflowDepartureEngine.activeElapsedSeconds(
            startedAt: focus.startedAt,
            endedAt: date,
            state: focusDepartureState(for: focus)
        )
    }

    private func focusDepartureState(for focus: FocusSessionModel) -> FocusWorkflowDepartureState {
        FocusWorkflowDepartureState(
            focusWorkflowID: focus.taskID,
            pendingDepartureAt: pendingFocusDepartureAt,
            pausedAt: focus.pausedAt,
            accumulatedPausedSeconds: focus.accumulatedPausedSeconds ?? 0
        )
    }

    private func applyFocusDepartureState(
        _ state: FocusWorkflowDepartureState,
        to focus: FocusSessionModel
    ) {
        pendingFocusDepartureAt = state.pendingDepartureAt
        focus.pausedAt = state.pausedAt
        focus.accumulatedPausedSeconds = state.accumulatedPausedSeconds
    }

    private func flagSuspectedDistraction(segmentID: UUID) {
        guard baselineComplete,
              let segment = activeSegment,
              segment.id == segmentID,
              segment.endedAt == nil,
              !segment.isAllowedApp,
              !segment.crossedReminderThreshold,
              let focusID = segment.focusSessionID,
              focusID == currentFocusID,
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
                self.updateClock(to: Date())
                guard let focus = self.currentFocus else { return }
                if self.pendingFocusDepartureAt == nil,
                   focus.pausedAt == nil,
                   !focus.targetNotificationSent,
                   self.focusElapsedSeconds >= focus.targetSeconds {
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
                self.updateClock(to: date)
                let shouldRecord = self.shouldRecord(at: date)
                if shouldRecord != wasRecording {
                    self.refreshCaptureForCurrentState()
                    wasRecording = shouldRecord
                }
                self.sendDueTaskParkingReminders(at: date)
            }
        }
    }

    private func refreshCaptureForCurrentState() {
        let date = Date()
        updateClock(to: date)
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

    private func insertMarkerIfNotRecent(
        _ kind: TimelineMarkerKind,
        at date: Date,
        taskID: UUID?
    ) {
        if let previous = markers.last(where: { $0.kind == kind }),
           abs(date.timeIntervalSince(previous.date)) < 2 {
            return
        }
        insertMarker(kind, at: date, taskID: taskID)
    }

    private func updateClock(to date: Date) {
        selectedDate = TimelineDateEngine.selectedDateAfterTick(
            selectedDate: selectedDate,
            previousNow: now,
            currentNow: date
        )
        now = date
    }

    private func resolveTaskParking(_ parking: TaskParkingModel, resumedAt date: Date) {
        guard parking.isActive else { return }
        parking.resumedAt = date
        insertMarker(.taskResumed, at: date, taskID: parking.taskID)
        saveOrReport()
        objectWillChange.send()
    }

    private func sendDueTaskParkingReminders(at date: Date) {
        let dueIDs = Set(TaskParkingEngine.dueForReminder(
            taskParkings.map(\.record),
            at: date
        ).map(\.id))
        for parking in taskParkings where dueIDs.contains(parking.id) {
            parking.reminderSentAt = date
            notificationRouter.sendTaskParkingReminder(
                id: parking.id,
                taskName: taskName(for: parking.taskID),
                resumeCue: parking.resumeCue
            )
        }
        if !dueIDs.isEmpty {
            saveOrReport()
            objectWillChange.send()
        }
    }

    private func recoverInterruptedState() {
        let now = Date()
        do {
            for item in store.activities where item.endedAt == nil {
                item.endedAt = min(now, item.startedAt.addingTimeInterval(300))
                item.source = .recovery
            }
            for item in store.activities where item.bundleID == SystemActivityGate.loginWindowBundleID {
                item.classification = .systemInactive
                item.isAllowedApp = false
            }
            for item in store.taskIntervals where item.endedAt == nil {
                item.endedAt = min(now, item.startedAt.addingTimeInterval(300))
            }
            for item in store.focusSessions where item.endedAt == nil {
                let recoveredEnd = min(now, item.startedAt.addingTimeInterval(Double(item.targetSeconds)))
                if let pausedAt = item.pausedAt {
                    item.accumulatedPausedSeconds = max(0, item.accumulatedPausedSeconds ?? 0)
                        + max(0, recoveredEnd.timeIntervalSince(pausedAt))
                    item.pausedAt = nil
                }
                item.endedAt = recoveredEnd
                item.outcome = .pending
            }
            try store.flush()
        } catch {
            errorMessage = "恢复上次记录失败：\(error.localizedDescription)"
        }
    }

    private func prepareStoredSpaceBindingsForLaunch() {
        var changed = false
        for binding in workflowSpaceBindings
            where binding.state == .verified || binding.state == .conflict {
            binding.state = .needsRebind
            changed = true
        }
        spaceResolution = .unknown
        if changed { saveOrReport() }
    }

    private func scheduleSpaceResolution(after eventDate: Date) {
        guard spaceAnchorRegistry.isEnabled else { return }
        spaceResolution = .unknown
        // Close the old workflow at the event boundary before debouncing the
        // new Space. This prevents even a short transition from inheriting
        // the previous workflow's attribution.
        switchTask(to: nil, source: .space, at: eventDate)
        spaceResolutionTask?.cancel()
        spaceResolutionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            self.applySpaceResolution(
                self.spaceAnchorRegistry.resolution(),
                at: max(eventDate, Date()),
                source: .space
            )
        }
    }

    private func applySpaceResolution(
        _ resolution: WorkflowSpaceResolution,
        at date: Date,
        source: WorkflowIntervalSource
    ) {
        spaceResolution = resolution
        switch resolution {
        case let .bound(workflowID):
            guard tasks.contains(where: {
                $0.id == workflowID && $0.workflowLifecycle == .open
            }) else {
                errorMessage = "当前桌面绑定的工作流已经结束，请解除或重新绑定。"
                switchTask(to: nil, source: .space, at: date)
                return
            }
            switchTask(to: workflowID, source: source, at: date)

        case .unbound:
            // Once Space mode is enabled, an unbound desktop is an explicit
            // context boundary. Never carry the previous workflow forward.
            switchTask(to: nil, source: source, at: date)

        case .unknown:
            // Unknown is deliberately unattributed. This state is normally
            // transient during the 600 ms Space-change debounce.
            switchTask(to: nil, source: source, at: date)

        case let .conflict(workflowIDs):
            switchTask(to: nil, source: source, at: date)
            let names = workflowIDs.map { taskName(for: $0) }.joined(separator: "、")
            errorMessage = "当前桌面检测到多个工作流锚点（\(names)），已停止任务归因。请解除后重新绑定。"
        }
        updateClock(to: date)
    }

    private func releaseAllSpaceBindings(
        for workflowID: UUID,
        state: WorkflowSpaceBindingState
    ) {
        spaceAnchorRegistry.releaseAll(workflowID: workflowID)
        for binding in workflowSpaceBindings where binding.workflowID == workflowID {
            binding.state = state
        }
        if currentSpaceWorkflowID == workflowID {
            spaceResolution = spaceAnchorRegistry.isEnabled
                ? spaceAnchorRegistry.resolution()
                : .unknown
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
        taskParkings.filter { max($0.resumedAt ?? .distantPast, $0.dismissedAt ?? $0.parkedAt) < cutoff }
            .forEach { store.delete($0) }
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
        taskParkings = store.taskParkings.sorted { $0.parkedAt < $1.parkedAt }
        workflowSpaceBindings = store.workflowSpaceBindings.sorted { $0.boundAt < $1.boundAt }
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
