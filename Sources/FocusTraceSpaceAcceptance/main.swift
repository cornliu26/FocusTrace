@preconcurrency import AppKit
import Foundation
import FocusTraceCore
import FocusTraceMacSupport
import SwiftUI

private struct AcceptanceSlot: Identifiable, Equatable {
    let id: UUID
    let workflowID: UUID
    let bindingID: UUID
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

    let requiredSwitches = 30
    private let registry = SpaceAnchorRegistry()
    private let workspace = NSWorkspace.shared
    private var startedAt = Date()
    private var resolutionTask: Task<Void, Never>?
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(spaceChanged(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    func stop() {
        resolutionTask?.cancel()
        resolutionTask = nil
        workspace.notificationCenter.removeObserver(self)
        registry.releaseAll()
        isStarted = false
    }

    func bindCurrentSpace(using viewWindow: NSWindow?) {
        guard phase == .binding, slots.count < 3 else { return }
        // Accessibility-driven acceptance can invoke the button without first
        // making this process frontmost. Space assignment is defined by the
        // active Space, so explicitly activate the harness before creating the
        // invisible anchor and give AppKit one turn to settle.
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
            using: anchorWindow,
            bindingID: bindingID,
            restorationID: "acceptance-space-\(number)-\(bindingID.uuidString)"
        ) {
        case .created:
            slots.append(AcceptanceSlot(
                id: bindingID,
                workflowID: workflowID,
                bindingID: bindingID,
                number: number
            ))
            activeWorkflowID = workflowID
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
        status = "请在第一个待验收桌面点击“绑定当前桌面”"
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
        guard phase == .testing else {
            activeWorkflowID = resolvedWorkflowID()
            return
        }
        let previousWorkflowID = activeWorkflowID
        resolutionTask?.cancel()
        resolutionTask = Task { [weak self] in
            guard let self else { return }
            var candidateWorkflowID: UUID?
            var consecutiveSamples = 0

            // Full-screen and Mission Control animations briefly expose zero
            // or multiple anchors. Those transitional frames are not a Space
            // misidentification. Resolve only after the same bound anchor is
            // visible for three consecutive samples, while preserving the
            // one-second acceptance budget from the system notification.
            while Date().timeIntervalSince(eventAt) <= 1 {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }

                guard let workflowID = self.resolvedWorkflowID() else {
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

    private func resolvedWorkflowID() -> UUID? {
        guard case let .bound(workflowID) = registry.resolution() else { return nil }
        return workflowID
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
        .defaultSize(width: 560, height: 360)
    }
}
