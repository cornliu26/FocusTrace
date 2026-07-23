@preconcurrency import AppKit
import CoreGraphics
import SwiftUI

@MainActor
private final class AttentionCueOverlayModel: ObservableObject {
    enum Mode: Equatable {
        case progress
        case reward
        case warning
    }

    @Published var mode: Mode = .progress
    @Published var taskName = ""
    @Published var message = ""
    @Published var progress = 0.0
    @Published var isStrongWarning = false
}

@MainActor
final class AttentionCueOverlayController {
    private let model = AttentionCueOverlayModel()
    private var panel: NSPanel?
    private var collapseTask: Task<Void, Never>?
    private let panelSize = NSSize(width: 300, height: 64)

    func updateProgress(
        taskName: String,
        elapsedSeconds: TimeInterval,
        displayIdentifier: String?
    ) {
        let fiveMinutes: TimeInterval = 5 * 60
        model.taskName = taskName
        model.progress = min(1, max(0, elapsedSeconds.truncatingRemainder(dividingBy: fiveMinutes) / fiveMinutes))
        ensurePanel(on: displayIdentifier)
        if model.mode == .progress {
            panel?.orderFrontRegardless()
        }
    }

    func showReward(
        taskName: String,
        milestoneMinutes: Int,
        displayIdentifier: String?
    ) {
        model.taskName = taskName
        model.message = "连续守住主线 \(milestoneMinutes) 分钟"
        model.isStrongWarning = false
        model.mode = .reward
        ensurePanel(on: displayIdentifier)
        panel?.orderFrontRegardless()
        collapse(after: 4)
    }

    func showSwitchWarning(
        taskName: String,
        switchCount: Int,
        strong: Bool,
        baselineComplete: Bool,
        displayIdentifier: String?
    ) {
        model.taskName = taskName
        model.isStrongWarning = strong
        if baselineComplete {
            model.message = strong
                ? "10 分钟切换了 \(switchCount) 次 · 先挂起或回到主线"
                : "10 分钟切换了 \(switchCount) 次 · 停一下，确认下一步"
        } else {
            model.message = "基线观察：10 分钟切换了 \(switchCount) 次工作流"
        }
        model.mode = .warning
        ensurePanel(on: displayIdentifier)
        panel?.orderFrontRegardless()
        collapse(after: strong ? 8 : 6)
    }

    func hide() {
        collapseTask?.cancel()
        collapseTask = nil
        panel?.orderOut(nil)
    }

    private func collapse(after seconds: TimeInterval) {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.model.mode = .progress
        }
    }

    private func ensurePanel(on displayIdentifier: String?) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: panelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.contentView = NSHostingView(rootView: AttentionCueOverlayView(model: model))
            self.panel = panel
        }

        guard let panel, let screen = screen(for: displayIdentifier) else { return }
        let frame = screen.visibleFrame
        panel.setFrame(
            NSRect(
                x: frame.maxX - panelSize.width,
                y: frame.midY - panelSize.height / 2,
                width: panelSize.width,
                height: panelSize.height
            ),
            display: false
        )
    }

    private func screen(for displayIdentifier: String?) -> NSScreen? {
        if let displayIdentifier,
           let match = NSScreen.screens.first(where: {
               Self.displayIdentifier(for: $0) == displayIdentifier
           }) {
            return match
        }
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private static func displayIdentifier(for screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
              let value = CFUUIDCreateString(nil, uuid) else {
            return nil
        }
        return value as String
    }
}

@MainActor
private struct AttentionCueOverlayView: View {
    @ObservedObject var model: AttentionCueOverlayModel

    var body: some View {
        ZStack(alignment: .trailing) {
            if model.mode == .progress {
                progressRail
                    .transition(.opacity)
            } else {
                expandedCue
                    .transition(.opacity)
            }
        }
        .frame(width: 300, height: 64, alignment: .trailing)
        .animation(.easeOut(duration: 0.16), value: model.mode)
    }

    private var progressRail: some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(.secondary.opacity(0.1))
            Capsule()
                .fill(FocusTraceTheme.accentGradient)
                .frame(height: max(4, 52 * model.progress))
        }
        .frame(width: 4, height: 52)
        .accessibilityLabel("当前工作流五分钟连续进度")
        .accessibilityValue("\(Int(model.progress * 100))%")
    }

    private var expandedCue: some View {
        HStack(spacing: 10) {
            FocusTraceBrandMark(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.message)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text("工作流 · \(model.taskName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .frame(width: 286, height: 48)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accentColor.opacity(0.28), lineWidth: 1)
        }
    }

    private var accentColor: Color {
        switch model.mode {
        case .progress: return FocusTraceTheme.sky
        case .reward: return FocusTraceTheme.mint
        case .warning: return model.isStrongWarning ? FocusTraceTheme.coral : FocusTraceTheme.amber
        }
    }
}
