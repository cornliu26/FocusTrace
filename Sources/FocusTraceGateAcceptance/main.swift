@preconcurrency import AppKit
import FocusTraceCore
import FocusTraceMacSupport
import Foundation

private struct GateAcceptanceResult: Codable {
    let completedAt: Date
    let outcome: String
}

@MainActor
private final class GateAcceptanceDelegate: NSObject, NSApplicationDelegate {
    private let controller = SpaceSwitchGateController()
    private var timeoutTask: Task<Void, Never>?
    // Computer Use needs enough time to inspect the accessibility tree before
    // pressing a button. Production continues to use the engine's 10 seconds;
    // this window only proves that the shared panel is visible and clickable.
    private let interactiveAcceptanceSeconds: TimeInterval = 30

    func applicationDidFinishLaunching(_ notification: Notification) {
        let expiresAt = Date().addingTimeInterval(
            interactiveAcceptanceSeconds
        )
        controller.show(
            originName: "验收工作流 A",
            destinationName: "验收工作流 B",
            expiresAt: expiresAt,
            displayIdentifier: nil
        ) { [weak self] reason in
            self?.finish(outcome: reason.rawValue)
        }
        timeoutTask = Task { [weak self] in
            let remaining = max(0, expiresAt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.finish(outcome: SpaceSwitchReason.unstructured.rawValue)
        }
    }

    private func finish(outcome: String) {
        timeoutTask?.cancel()
        timeoutTask = nil
        controller.hide()
        let result = GateAcceptanceResult(
            completedAt: Date(),
            outcome: outcome
        )
        let outputURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/gate-acceptance-result.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(result).write(to: outputURL, options: .atomic)
        NSApp.terminate(nil)
    }
}

@main
private enum FocusTraceGateAcceptance {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = GateAcceptanceDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()
        _ = delegate
    }
}
