@preconcurrency import AppKit
import Foundation
import FocusTraceCore
import FocusTraceMacSupport
import SwiftUI

private struct AcceptanceSlot: Identifiable, Equatable {
    let id: UUID
    let workflowID: UUID
    let bindingID: UUID
    let identity: WorkflowSpaceIdentity
    let number: Int
}

private struct AcceptanceResult: Codable {
    let startedAt: Date
    let completedAt: Date
    let requiredSwitches: Int
    let observedSwitches: Int
    let correctSwitches: Int
    let mismatchCount: Int
    let maximumLatencySeconds: TimeInterval
    let passed: Bool
}

@MainActor
private final class SpaceAcceptanceModel: NSObject, ObservableObject {
    enum Phase: Equatable {
        case binding
        case testing
        case passed
        case failed
    }

    @Published private(set) var phase: Phase = .binding
    @Published private(set) var slots: [AcceptanceSlot] = []
    @Published private(set) var activeWorkflowID: UUID?
    @Published private(set) var observedSwitches = 0
    @Published private(set) var correctSwitches = 0
    @Published private(set) var mismatchCount = 0
    @Published private(set) var maximumLatencySeconds: TimeInterval = 0
    @Published private(set) var status = "请在第一个待验收桌面点击“绑定当前桌面”"
    @Published private(set) var outputPath: String?
    @Published private(set) var currentSpaceSummary = "Space: 尚未读取"
    @Published private(set) var existingSpaceIsolationStatus = "现有桌面隔离：尚未开始"
    @Published private(set) var insertionRegressionStatus = "新增桌面回归：尚未开始"
    @Published private(set) var removalRegressionStatus = "删除桌面回归：尚未开始"
    @Published private(set) var gateStatus = "切换门交互：尚未验收"
    @Published private(set) var gateSelectionCount = 0
    @Published private(set) var realSpaceGateStatus = "真实 Space 链路：尚未验收"

    let requiredSwitches = 30
    private let registry = SpaceAnchorRegistry()
    private let realGateRegistry = SpaceAnchorRegistry()
    private let workspace = NSWorkspace.shared
    private let gateController = SpaceSwitchGateController()
    private var startedAt = Date()
    private var resolutionTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    private var gateTimeoutTask: Task<Void, Never>?
    private var realGateResolutionTask: Task<Void, Never>?
    private var realGateTimeoutTask: Task<Void, Never>?
    private var realGateOrigin: WorkflowSpaceResolution?
    private var realGateJourney: SpaceSwitchJourney?
    private weak var realGateWindow: NSWindow?
    private var isRunningRealSpaceGateAcceptance = false
    private var isStarted = false
    private var initialSpaceIdentities: [WorkflowSpaceIdentity] = []
    private var insertedIdentity: WorkflowSpaceIdentity?
    private var originalReverifiedAfterInsertion = false

    var screenSummary: String {
        NSScreen.screens.enumerated().map { index, screen in
            let frame = screen.frame
            return "S\(index): x\(Int(frame.minX)) y\(Int(frame.minY)) \(Int(frame.width))×\(Int(frame.height))"
        }.joined(separator: " · ")
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(spaceChanged(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        refreshSpaceSummary()
        snapshotTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                self.reconcileCurrentSpaces()
                self.evaluateSpaceRegression()
            }
        }
    }

    func stop() {
        resolutionTask?.cancel()
        resolutionTask = nil
        snapshotTask?.cancel()
        snapshotTask = nil
        gateTimeoutTask?.cancel()
        gateTimeoutTask = nil
        realGateResolutionTask?.cancel()
        realGateResolutionTask = nil
        realGateTimeoutTask?.cancel()
        realGateTimeoutTask = nil
        gateController.hide()
        workspace.notificationCenter.removeObserver(self)
        registry.releaseAll()
        realGateRegistry.releaseAll()
        isStarted = false
    }

    func bindCurrentSpace(using viewWindow: NSWindow?) {
        guard phase == .binding, slots.count < 3 else { return }
        // Explicit binding uses the display where the user clicks. Passive
        // Space changes are resolved separately from per-display deltas.
        guard let anchorWindow = viewWindow else {
            status = "没有找到当前桌面的验收窗口，请重新打开验收工具。"
            return
        }
        anchorWindow.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let number = slots.count + 1
        let workflowID = UUID()
        let bindingID = UUID()
        switch registry.bindCurrentSpace(
            workflowID: workflowID,
            bindingID: bindingID,
            restorationID: "acceptance-space-\(number)-\(bindingID.uuidString)"
        ) {
        case let .created(_, identity):
            slots.append(AcceptanceSlot(
                id: bindingID,
                workflowID: workflowID,
                bindingID: bindingID,
                identity: identity,
                number: number
            ))
            activeWorkflowID = workflowID
            refreshSpaceSummary()
            if slots.count == 1 {
                initialSpaceIdentities = registry.allSpaceIdentities() ?? [identity]
                existingSpaceIsolationStatus = "现有桌面隔离：请切换到另一个已有桌面"
                insertionRegressionStatus = "新增桌面回归：等待创建一个标准 macOS 桌面"
                removalRegressionStatus = "删除桌面回归：等待新增桌面验收"
            }
            if slots.count == 3 {
                phase = .testing
                startedAt = Date()
                status = "三个桌面已绑定。现在在这三个桌面之间往返切换 30 次。"
            } else {
                status = "桌面 \(number) 已绑定。请切换到另一个尚未绑定的 macOS 桌面。"
            }

        case .alreadyBound:
            status = "这个桌面已经绑定过；请切换到另一个桌面。"

        case .occupied:
            status = "这个桌面已经绑定到其他验收槽位；请切换到另一个桌面。"

        case .failed:
            status = "系统尚未确认当前桌面锚点，请稍后重试。"
        }
    }

    func reset() {
        resolutionTask?.cancel()
        resolutionTask = nil
        registry.releaseAll()
        phase = .binding
        slots = []
        activeWorkflowID = nil
        observedSwitches = 0
        correctSwitches = 0
        mismatchCount = 0
        maximumLatencySeconds = 0
        outputPath = nil
        initialSpaceIdentities = []
        insertedIdentity = nil
        originalReverifiedAfterInsertion = false
        existingSpaceIsolationStatus = "现有桌面隔离：尚未开始"
        insertionRegressionStatus = "新增桌面回归：尚未开始"
        removalRegressionStatus = "删除桌面回归：尚未开始"
        gateTimeoutTask?.cancel()
        gateTimeoutTask = nil
        gateController.hide()
        gateStatus = "切换门交互：尚未验收"
        gateSelectionCount = 0
        realGateResolutionTask?.cancel()
        realGateResolutionTask = nil
        realGateTimeoutTask?.cancel()
        realGateTimeoutTask = nil
        realGateRegistry.releaseAll()
        realGateOrigin = nil
        realGateJourney = nil
        realGateWindow = nil
        isRunningRealSpaceGateAcceptance = false
        realSpaceGateStatus = "真实 Space 链路：尚未验收"
        status = "请在第一个待验收桌面点击“绑定当前桌面”"
    }

    func showGateForAcceptance() {
        gateTimeoutTask?.cancel()
        let expiresAt = Date().addingTimeInterval(
            SpaceSwitchGateEngine.decisionWindowSeconds
        )
        gateStatus = "切换门交互：弹窗已显示，等待按钮或 10 秒超时"
        gateController.show(
            originName: "验收工作流 A",
            destinationName: "验收工作流 B",
            expiresAt: expiresAt,
            displayIdentifier: nil
        ) { [weak self] reason in
            guard let self else { return }
            self.gateTimeoutTask?.cancel()
            self.gateTimeoutTask = nil
            self.gateSelectionCount += 1
            self.gateStatus = "切换门交互：按钮回调成功（\(self.reasonName(reason))）· 共 \(self.gateSelectionCount) 次"
            self.gateController.hide()
        }
        let selectionCount = gateSelectionCount
        gateTimeoutTask = Task { [weak self] in
            let remaining = max(0, expiresAt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self,
                  self.gateSelectionCount == selectionCount else { return }
            self.gateController.hide()
            self.gateStatus = "切换门交互：10 秒超时已安全放行"
        }
    }

    func simulateReturnToOrigin() {
        let originID = UUID()
        let destinationID = UUID()
        let now = Date()
        guard let pending = SpaceSwitchGateEngine.begin(
            origin: .bound(workflowID: originID),
            destination: .bound(workflowID: destinationID),
            at: now,
            isEnabled: true
        ) else {
            gateStatus = "切换门交互：无法创建回退验收上下文"
            return
        }
        showGateForAcceptance()
        guard SpaceSwitchGateEngine.observe(
            .bound(workflowID: originID),
            while: pending
        ) == .returnedToOrigin else {
            gateStatus = "切换门交互：回到原桌面未被识别"
            return
        }
        gateTimeoutTask?.cancel()
        gateTimeoutTask = nil
        gateController.hide()
        gateStatus = "切换门交互：滑回原桌面后已取消，不产生目标工作流归因"
    }

    func runRealSpaceGateAcceptance(using window: NSWindow?) {
        guard !isRunningRealSpaceGateAcceptance else { return }
        guard let window else {
            realSpaceGateStatus = "真实 Space 链路：找不到验收窗口"
            return
        }
        realGateRegistry.releaseAll()
        let workflowID = UUID()
        switch realGateRegistry.bindCurrentSpace(
            workflowID: workflowID,
            restorationID: "gate-space-acceptance-\(workflowID.uuidString)"
        ) {
        case .created, .alreadyBound:
            break
        case .occupied, .failed:
            realSpaceGateStatus = "真实 Space 链路：无法在当前桌面建立隔离绑定"
            return
        }
        realGateOrigin = .bound(workflowID: workflowID)
        realGateJourney = nil
        realGateWindow = window
        isRunningRealSpaceGateAcceptance = true
        realSpaceGateStatus = "真实 Space 链路：正在进入临时全屏桌面"
        window.toggleFullScreen(nil)
    }

    private func reasonName(_ reason: SpaceSwitchReason) -> String {
        switch reason {
        case .reachedCheckpoint:
            return "阶段已到"
        case .waitingForResult:
            return "等待结果"
        case .forcedInterruption:
            return "被迫中断"
        case .unstructured:
            return "未选择理由"
        }
    }

    func openMissionControl() {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.status = "Mission Control 打开失败：\(error.localizedDescription)"
                }
            }
        }
    }

    var activeSlotNumber: Int? {
        guard let activeWorkflowID else { return nil }
        return slots.first(where: { $0.workflowID == activeWorkflowID })?.number
    }

    @objc private func spaceChanged(_ notification: Notification) {
        let eventAt = Date()
        if isRunningRealSpaceGateAcceptance {
            handleRealSpaceGateChange(at: eventAt)
            return
        }
        guard phase == .testing else {
            resolutionTask?.cancel()
            resolutionTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, let self else { return }
                self.reconcileCurrentSpaces()
                self.refreshSpaceSummary()
                self.evaluateSpaceRegression()
            }
            return
        }
        let previousWorkflowID = activeWorkflowID
        resolutionTask?.cancel()
        resolutionTask = Task { [weak self] in
            guard let self else { return }
            var candidateWorkflowID: UUID?
            var consecutiveSamples = 0

            // Mission Control animations can briefly report the previous
            // current Space. Resolve only after the same bound identity is
            // returned for three consecutive samples, while preserving the
            // one-second acceptance budget from the system notification.
            while Date().timeIntervalSince(eventAt) <= 1 {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }

                guard let workflowID = self.resolvedWorkflowID(afterSpaceChange: consecutiveSamples == 0) else {
                    candidateWorkflowID = nil
                    consecutiveSamples = 0
                    continue
                }
                guard workflowID != previousWorkflowID else { return }

                if workflowID == candidateWorkflowID {
                    consecutiveSamples += 1
                } else {
                    candidateWorkflowID = workflowID
                    consecutiveSamples = 1
                }

                guard consecutiveSamples >= 3 else { continue }
                self.record(
                    workflowID: workflowID,
                    latency: Date().timeIntervalSince(eventAt)
                )
                return
            }

            // An ambiguous Mission Control frame is ignored. A different
            // bound anchor that appeared but failed to stabilize in one second
            // remains a genuine acceptance failure.
            if let candidateWorkflowID, candidateWorkflowID != previousWorkflowID {
                self.record(
                    workflowID: candidateWorkflowID,
                    latency: Date().timeIntervalSince(eventAt)
                )
            }
        }
    }

    private func handleRealSpaceGateChange(at eventAt: Date) {
        guard let origin = realGateOrigin,
              let journey = SpaceSwitchJourneyEngine.beginOrExtend(
                  realGateJourney,
                  origin: origin,
                  at: eventAt
              ) else {
            finishRealSpaceGateAcceptance(
                status: "真实 Space 链路：无法保留最初工作流"
            )
            return
        }
        realGateJourney = journey
        realSpaceGateStatus = "真实 Space 链路：正在等待最终桌面稳定"
        realGateResolutionTask?.cancel()
        realGateResolutionTask = Task { [weak self] in
            try? await Task.sleep(
                for: .seconds(SpaceSwitchJourneyEngine.settleDelaySeconds)
            )
            guard !Task.isCancelled, let self,
                  self.isRunningRealSpaceGateAcceptance,
                  let journey = self.realGateJourney else { return }
            let destination = self.realGateRegistry.resolutionAfterSpaceChange()
            let now = Date()
            guard case let .presentGate(pending) = SpaceSwitchJourneyEngine.finish(
                journey,
                finalDestination: destination,
                at: now,
                isGateEnabled: true
            ) else {
                self.finishRealSpaceGateAcceptance(
                    status: "真实 Space 链路：收到系统事件，但目标桌面未可靠解析"
                )
                return
            }
            self.realSpaceGateStatus = "真实 Space 链路：已收到系统事件并显示切换门"
            self.gateController.show(
                originName: "真实验收工作流",
                destinationName: "临时全屏桌面",
                expiresAt: pending.expiresAt,
                displayIdentifier: nil
            ) { [weak self] reason in
                self?.finishRealSpaceGateAcceptance(
                    status: "真实 Space 链路：通过（系统事件 → 弹窗 → \(self?.reasonName(reason) ?? reason.rawValue)）"
                )
            }
            self.realGateTimeoutTask?.cancel()
            self.realGateTimeoutTask = Task { [weak self] in
                let remaining = max(0, pending.expiresAt.timeIntervalSinceNow)
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled, let self else { return }
                self.finishRealSpaceGateAcceptance(
                    status: "真实 Space 链路：通过（系统事件 → 弹窗 → 10 秒安全放行）"
                )
            }
        }
    }

    private func finishRealSpaceGateAcceptance(status: String) {
        realGateResolutionTask?.cancel()
        realGateResolutionTask = nil
        realGateTimeoutTask?.cancel()
        realGateTimeoutTask = nil
        gateController.hide()
        isRunningRealSpaceGateAcceptance = false
        realGateOrigin = nil
        realGateJourney = nil
        realGateRegistry.releaseAll()
        realSpaceGateStatus = status
        guard let window = realGateWindow else { return }
        realGateWindow = nil
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    private func resolvedWorkflowID(afterSpaceChange: Bool = false) -> UUID? {
        let resolution = afterSpaceChange
            ? registry.resolutionAfterSpaceChange()
            : registry.resolutionForInteraction()
        guard case let .bound(workflowID) = resolution else { return nil }
        return workflowID
    }

    private func reconcileCurrentSpaces() {
        guard let resolution = registry.resolutionForChangedDisplay() else { return }
        if case let .bound(workflowID) = resolution {
            activeWorkflowID = workflowID
        } else {
            activeWorkflowID = nil
        }
        refreshSpaceSummary()
    }

    private func refreshSpaceSummary() {
        guard let identity = registry.currentInteractionIdentity()
                ?? registry.lastResolvedIdentity
                ?? registry.currentIdentity() else {
            currentSpaceSummary = "Space: 无法读取"
            return
        }
        let uuid = identity.spaceUUID?.prefix(8) ?? "no-uuid"
        let bound = slots.first.map { slot in
            let boundUUID = slot.identity.spaceUUID?.prefix(8) ?? "no-uuid"
            return "\(slot.identity.managedSpaceID)/\(boundUUID)"
        } ?? "none"
        currentSpaceSummary = "Space: \(identity.managedSpaceID)/\(uuid) · 首次绑定: \(bound)"
    }

    private func evaluateSpaceRegression() {
        guard let first = slots.first,
              let currentIdentity = registry.currentInteractionIdentity()
                ?? registry.lastResolvedIdentity
                ?? registry.currentIdentity() else { return }
        let isOriginal = first.identity.identifiesSameSpace(as: currentIdentity)
        if !isOriginal,
           identity(currentIdentity, existsIn: initialSpaceIdentities),
           activeWorkflowID == nil {
            existingSpaceIsolationStatus = "现有桌面隔离：通过；桌面 \(currentIdentity.managedSpaceID) 未继承首次绑定"
        }

        if !isOriginal,
           !identity(currentIdentity, existsIn: initialSpaceIdentities),
           activeWorkflowID == nil {
            insertedIdentity = currentIdentity
            insertionRegressionStatus = "新增桌面回归：通过第 1/2 步，新桌面 \(currentIdentity.managedSpaceID) 未继承绑定；请返回原桌面"
            return
        }

        guard isOriginal, activeWorkflowID == first.workflowID,
              let insertedIdentity else { return }
        if !originalReverifiedAfterInsertion {
            originalReverifiedAfterInsertion = true
            insertionRegressionStatus = "新增桌面回归：通过；新桌面 \(insertedIdentity.managedSpaceID) 未绑定，原桌面 \(currentIdentity.managedSpaceID) 仍命中原工作流"
            removalRegressionStatus = "删除桌面回归：请删除刚才新增的测试桌面"
        }

        let currentInventory = registry.allSpaceIdentities() ?? []
        guard !identity(insertedIdentity, existsIn: currentInventory) else { return }
        removalRegressionStatus = "删除桌面回归：通过；测试桌面 \(insertedIdentity.managedSpaceID) 已删除，原桌面 \(currentIdentity.managedSpaceID) 仍命中原工作流"
        writeSpaceRegressionReport()
    }

    private func identity(
        _ identity: WorkflowSpaceIdentity,
        existsIn identities: [WorkflowSpaceIdentity]
    ) -> Bool {
        identities.contains { $0.identifiesSameSpace(as: identity) }
    }

    private func writeSpaceRegressionReport() {
        guard existingSpaceIsolationStatus.contains("通过"),
              insertionRegressionStatus.contains("通过"),
              removalRegressionStatus.contains("通过") else { return }
        let report = [
            existingSpaceIsolationStatus,
            insertionRegressionStatus,
            removalRegressionStatus,
        ].joined(separator: "\n") + "\n"
        let outputURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/space-regression.txt")
        try? report.write(
            to: outputURL,
            atomically: true,
            encoding: .utf8
        )
    }

    private func record(workflowID: UUID?, latency: TimeInterval) {
        guard phase == .testing else { return }
        observedSwitches += 1
        maximumLatencySeconds = max(maximumLatencySeconds, latency)
        if let workflowID,
           workflowID != activeWorkflowID,
           slots.contains(where: { $0.workflowID == workflowID }),
           latency <= 1 {
            correctSwitches += 1
            activeWorkflowID = workflowID
            status = "已识别桌面 \(activeSlotNumber ?? 0)：\(observedSwitches)/\(requiredSwitches)"
        } else {
            mismatchCount += 1
            activeWorkflowID = workflowID
            status = "第 \(observedSwitches) 次未可靠识别；继续切换，结果会保留。"
        }
        if observedSwitches >= requiredSwitches {
            finish()
        }
    }

    private func finish() {
        let passed = correctSwitches == requiredSwitches
            && mismatchCount == 0
            && maximumLatencySeconds <= 1
        phase = passed ? .passed : .failed
        status = passed
            ? "验收通过：30/30 次正确，最大延迟 \(String(format: "%.3f", maximumLatencySeconds)) 秒。"
            : "验收未通过：正确 \(correctSwitches)/\(requiredSwitches)，误识别 \(mismatchCount) 次。"
        let result = AcceptanceResult(
            startedAt: startedAt,
            completedAt: Date(),
            requiredSwitches: requiredSwitches,
            observedSwitches: observedSwitches,
            correctSwitches: correctSwitches,
            mismatchCount: mismatchCount,
            maximumLatencySeconds: maximumLatencySeconds,
            passed: passed
        )
        do {
            let outputURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".build/space-acceptance-result.json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(result).write(to: outputURL, options: .atomic)
            outputPath = outputURL.path
        } catch {
            status += " 结果文件写入失败：\(error.localizedDescription)"
        }
    }
}

private struct WindowSpaceBehavior: NSViewRepresentable {
    let onResolve: @MainActor (NSWindow) -> Void

    final class Coordinator {
        weak var configuredWindow: NSWindow?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view.window, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window, coordinator: context.coordinator) }
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        guard coordinator.configuredWindow !== window else {
            onResolve(window)
            return
        }
        coordinator.configuredWindow = window
        // Each acceptance window must be able to become its own full-screen
        // Space. Using canJoinAllSpaces/fullScreenAuxiliary made the HUD follow
        // every Space but also removed that eligibility after the first AppKit
        // update, which made repeatable mouse-driven acceptance impossible.
        // Move newly-created windows to the Space where the user launched the
        // harness. Pin them after AppKit finishes assignment so subsequent
        // Space switches remain real and independently observable.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
        window.level = .normal
        window.isMovableByWindowBackground = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onResolve(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard coordinator.configuredWindow === window else { return }
            window.collectionBehavior = [.managed, .fullScreenPrimary]
        }
    }
}

private struct AcceptanceView: View {
    @ObservedObject var model: SpaceAcceptanceModel
    @State private var viewWindow: NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "rectangle.3.group")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("FocusTrace 三桌面验收")
                        .font(.title2.bold())
                    Text("独立内存模式，不读取或写入正式 FocusTrace 数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(model.status)
                .font(.headline)

            Text(model.screenSummary)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)

            Text(model.currentSpaceSummary)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)

            Text(model.existingSpaceIsolationStatus)
                .font(.caption)
                .foregroundStyle(model.existingSpaceIsolationStatus.contains("通过") ? .green : .secondary)

            Text(model.insertionRegressionStatus)
                .font(.caption)
                .foregroundStyle(model.insertionRegressionStatus.contains("通过") ? .green : .secondary)

            Text(model.removalRegressionStatus)
                .font(.caption)
                .foregroundStyle(model.removalRegressionStatus.contains("通过") ? .green : .secondary)

            HStack(spacing: 12) {
                ForEach(1...3, id: \.self) { number in
                    HStack(spacing: 6) {
                        Image(systemName: slotSymbol(number))
                            .foregroundStyle(slotColor(number))
                        Text("桌面 \(number)")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.quaternary, in: Capsule())
                }
            }

            if model.phase == .binding {
                Button("绑定当前桌面") { model.bindCurrentSpace(using: viewWindow) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("b", modifiers: .command)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(
                        value: Double(model.observedSwitches),
                        total: Double(model.requiredSwitches)
                    )
                    HStack {
                        Text("正确 \(model.correctSwitches) / \(model.requiredSwitches)")
                        Spacer()
                        Text("误识别 \(model.mismatchCount)")
                        Spacer()
                        Text("最大延迟 \(model.maximumLatencySeconds, specifier: "%.3f") 秒")
                    }
                    .font(.caption)
                    .monospacedDigit()
                }
            }

            Button("打开 Mission Control") { model.openMissionControl() }

            Divider()

            Text(model.gateStatus)
                .font(.caption)
                .foregroundStyle(
                    model.gateStatus.contains("成功")
                        || model.gateStatus.contains("安全放行")
                        || model.gateStatus.contains("已取消")
                        ? .green
                        : .secondary
                )
                .accessibilityIdentifier("space-gate-acceptance-status")

            HStack {
                Button("显示真实切换门") { model.showGateForAcceptance() }
                    .accessibilityIdentifier("show-real-space-gate")
                Button("模拟滑回原桌面") { model.simulateReturnToOrigin() }
                    .accessibilityIdentifier("simulate-space-gate-return")
            }

            Text(model.realSpaceGateStatus)
                .font(.caption)
                .foregroundStyle(
                    model.realSpaceGateStatus.contains("通过")
                        ? .green
                        : .secondary
                )
                .accessibilityIdentifier("real-space-gate-status")

            Button("自动验收真实 Space 切换") {
                model.runRealSpaceGateAcceptance(using: viewWindow)
            }
            .accessibilityIdentifier("run-real-space-gate-acceptance")

            if let outputPath = model.outputPath {
                Text("结果：\(outputPath)")
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }

            HStack {
                Button("重新开始") { model.reset() }
                Spacer()
                Button("退出验收") {
                    model.stop()
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(WindowSpaceBehavior { viewWindow = $0 })
        .onAppear { model.start() }
    }

    private func slotSymbol(_ number: Int) -> String {
        guard model.slots.contains(where: { $0.number == number }) else { return "circle" }
        return model.activeSlotNumber == number ? "checkmark.circle.fill" : "checkmark.circle"
    }

    private func slotColor(_ number: Int) -> Color {
        model.activeSlotNumber == number ? .green : .secondary
    }
}

@main
private struct FocusTraceSpaceAcceptanceApp: App {
    @StateObject private var model = SpaceAcceptanceModel()

    var body: some Scene {
        WindowGroup("FocusTrace 三桌面验收") {
            AcceptanceView(model: model)
        }
        .defaultSize(width: 560, height: 500)
    }
}
