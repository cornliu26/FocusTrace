@preconcurrency import AppKit
import CoreGraphics
import FocusTraceCore
import SwiftUI

@MainActor
private final class SpaceSwitchGateOverlayModel: ObservableObject {
    @Published var originName = ""
    @Published var destinationName = ""
    @Published var remainingSeconds = 10
    @Published var isResolvingDestination = false
}

@MainActor
public final class SpaceSwitchGateController {
    private let model = SpaceSwitchGateOverlayModel()
    private var panel: NSPanel?
    private var countdownTask: Task<Void, Never>?
    private var onReasonSelected: ((SpaceSwitchReason) -> Void)?
    private let panelSize = NSSize(
        width: FocusTraceConfirmationLayout.panelWidth,
        height: FocusTraceConfirmationLayout.panelHeight
    )
    private let panelCornerRadius =
        FocusTraceConfirmationLayout.cornerRadius

    public init() {}

    public func show(
        originName: String,
        destinationName: String,
        expiresAt: Date,
        displayIdentifier: String?,
        isResolvingDestination: Bool = false,
        onReasonSelected: @escaping (SpaceSwitchReason) -> Void
    ) {
        model.originName = originName
        model.destinationName = destinationName
        model.remainingSeconds = max(0, Int(ceil(expiresAt.timeIntervalSinceNow)))
        model.isResolvingDestination = isResolvingDestination
        self.onReasonSelected = onReasonSelected
        ensurePanel(on: displayIdentifier)
        panel?.orderFrontRegardless()
        startCountdown(until: expiresAt)
    }

    public func beginResolvingDestination() {
        countdownTask?.cancel()
        countdownTask = nil
        model.isResolvingDestination = true
    }

    public func hide() {
        countdownTask?.cancel()
        countdownTask = nil
        onReasonSelected = nil
        panel?.orderOut(nil)
    }

    private func select(_ reason: SpaceSwitchReason) {
        onReasonSelected?(reason)
    }

    private func startCountdown(until expiresAt: Date) {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.model.remainingSeconds = max(
                    0,
                    Int(ceil(expiresAt.timeIntervalSinceNow))
                )
                if self.model.remainingSeconds == 0 { return }
                try? await Task.sleep(for: .seconds(1))
            }
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
            panel.title = "FocusTrace 工作流切换确认"
            // A workflow switch is a deliberate boundary, so it must remain
            // visible above ordinary and full-screen application windows.
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary
            ]
            let hostingView = NSHostingView(
                rootView: SpaceSwitchGateOverlayView(
                    model: model,
                    onSelect: { [weak self] reason in
                        self?.select(reason)
                    }
                )
            )
            // Clip the actual AppKit host, not only the SwiftUI background.
            // This keeps all four corners geometrically identical even when
            // the transparent borderless panel is captured over another app.
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = panelCornerRadius
            hostingView.layer?.cornerCurve = .continuous
            hostingView.layer?.masksToBounds = true
            panel.contentView = hostingView
            self.panel = panel
        }

        guard let panel, let screen = screen(for: displayIdentifier) else { return }
        panel.setFrame(
            FocusTraceConfirmationLayout.frame(
                in: screen.visibleFrame,
                size: panelSize
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
              let uuid = CGDisplayCreateUUIDFromDisplayID(
                number.uint32Value
              )?.takeRetainedValue(),
              let value = CFUUIDCreateString(nil, uuid) else {
            return nil
        }
        return value as String
    }
}

@MainActor
private struct SpaceSwitchGateOverlayView: View {
    @ObservedObject var model: SpaceSwitchGateOverlayModel
    let onSelect: (SpaceSwitchReason) -> Void

    private let accent = Color(red: 0.34, green: 0.88, blue: 0.77)
    private let cornerRadius =
        FocusTraceConfirmationLayout.cornerRadius

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(accent.opacity(0.14))
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("确认工作流切换")
                        .font(.subheadline.weight(.semibold))
                    Text(routeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("space-gate-route")
                }

                Spacer(minLength: 8)

                Text(model.isResolvingDestination
                     ? "识别中"
                     : "\(model.remainingSeconds) 秒")
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Color.primary.opacity(0.055),
                        in: Capsule()
                    )
                    .accessibilityIdentifier("space-gate-countdown")
            }

            HStack(spacing: 8) {
                reasonButton(
                    "阶段已到",
                    symbol: "checkmark.circle",
                    reason: .reachedCheckpoint,
                    identifier: "space-gate-reached-checkpoint"
                )
                reasonButton(
                    "等待结果",
                    symbol: "hourglass",
                    reason: .waitingForResult,
                    identifier: "space-gate-waiting-for-result"
                )
                reasonButton(
                    "被迫中断",
                    symbol: "exclamationmark.bubble",
                    reason: .forcedInterruption,
                    identifier: "space-gate-forced-interruption"
                )
            }

            Text("误触或还没收尾？直接滑回原桌面。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(
            width: FocusTraceConfirmationLayout.panelWidth,
            height: FocusTraceConfirmationLayout.panelHeight
        )
        .modifier(
            SpaceSwitchGateSurfaceModifier(
                cornerRadius: cornerRadius,
                tint: accent
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    Color(nsColor: .separatorColor).opacity(0.92),
                    lineWidth: 1
                )
        }
        .clipShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("工作流切换确认")
        .accessibilityIdentifier("space-switch-gate")
    }

    private var routeText: String {
        if model.isResolvingDestination {
            return "\(model.originName)  →  正在确认最终桌面"
        }
        return "\(model.originName)  →  \(model.destinationName)"
    }

    private func reasonButton(
        _ title: String,
        symbol: String,
        reason: SpaceSwitchReason,
        identifier: String
    ) -> some View {
        Button {
            onSelect(reason)
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .disabled(model.isResolvingDestination)
        .opacity(model.isResolvingDestination ? 0.46 : 1)
        .accessibilityIdentifier(identifier)
    }
}

private struct SpaceSwitchGateSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(
                .regular.tint(tint.opacity(0.16)).interactive(),
                in: shape
            )
        } else if reduceTransparency {
            content.background(
                Color(nsColor: .windowBackgroundColor),
                in: shape
            )
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}
