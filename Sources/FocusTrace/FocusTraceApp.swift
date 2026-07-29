import AppKit
import Foundation
import SwiftUI
import FocusTraceCore
import FocusTraceMacSupport

extension Notification.Name {
    static let focusTraceOpenMainWindowRequested = Notification.Name(
        "FocusTrace.openMainWindowRequested"
    )
}

@main
struct FocusTraceApp: App {
    @StateObject private var state: ApplicationState
    @StateObject private var updateManager: UpdateManager
    private let store: FocusTraceStore
    private let isSpaceAnchorProbe: Bool
    private let isUpdateLaunchProbe: Bool

    init() {
        let isSpaceAnchorProbe = CommandLine.arguments.contains("--space-anchor-probe")
        let isUpdateLaunchProbe = CommandLine.arguments.contains(
            "--update-launch-probe"
        )
        self.isSpaceAnchorProbe = isSpaceAnchorProbe
        self.isUpdateLaunchProbe = isUpdateLaunchProbe
        do {
            let store = try FocusTraceStore(
                inMemory: isSpaceAnchorProbe || isUpdateLaunchProbe
            )
            self.store = store
            _state = StateObject(wrappedValue: ApplicationState(store: store))
            _updateManager = StateObject(wrappedValue: UpdateManager())
        } catch {
            fatalError("FocusTrace 无法初始化本地数据库：\(error)")
        }
    }

    var body: some Scene {
        Window("FocusTrace", id: FocusTraceWindowContract.mainWindowID) {
            if isSpaceAnchorProbe {
                SpaceAnchorProbeView()
                    .frame(width: 1, height: 1)
            } else if isUpdateLaunchProbe {
                Color.clear
                    .frame(width: 1, height: 1)
            } else {
                RootView(state: state)
                    .frame(minWidth: 920, minHeight: 640)
                    .environmentObject(updateManager)
                    .task {
                        try? CodexWorkspaceMaintenance
                            .refreshExistingWorkspaceIfPresent()
                        state.start()
                    }
                    .task {
                        await updateManager.checkAutomatically(
                            enabled: state.preferences.automaticUpdateChecks
                        )
                    }
            }
        }
        .defaultSize(width: 1080, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarView(state: state)
                .environmentObject(updateManager)
        } label: {
            FocusTraceStatusItemLabel(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct FocusTraceStatusItemLabel: View {
    @ObservedObject var state: ApplicationState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label {
            Text(
                state.currentFocusID == nil
                    ? "FocusTrace"
                    : "FocusTrace 正在专注"
            )
        } icon: {
            FocusTraceStatusMark(isFocusing: state.currentFocusID != nil)
        }
        .labelStyle(.iconOnly)
        .onReceive(
            NotificationCenter.default.publisher(
                for: .focusTraceOpenMainWindowRequested
            )
        ) { _ in
            openWindow(id: FocusTraceWindowContract.mainWindowID)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct SpaceAnchorProbeView: View {
    var body: some View {
        Color.clear
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                let registry = SpaceAnchorRegistry()
                let firstWorkflow = UUID()
                let secondWorkflow = UUID()
                let bindingID = UUID()
                let first = registry.bindCurrentSpace(
                    workflowID: firstWorkflow,
                    bindingID: bindingID,
                    restorationID: "probe-\(bindingID.uuidString)"
                )
                let resolution = registry.resolutionForInteraction()
                let conflict = registry.bindCurrentSpace(workflowID: secondWorkflow)
                let released = registry.releaseCurrentSpace()
                let finalResolution = registry.resolutionForInteraction()
                let didCreate: Bool
                if case let .created(createdID, _) = first {
                    didCreate = createdID == bindingID
                } else {
                    didCreate = false
                }
                let passed = didCreate && resolution == .bound(workflowID: firstWorkflow)
                    && conflict == .occupied(workflowID: firstWorkflow)
                    && released == [bindingID]
                    && finalResolution == .unbound
                let output = passed
                    ? "FOCUSTRACE_SPACE_PROBE_PASS\n"
                    : "FOCUSTRACE_SPACE_PROBE_FAIL first=\(first) resolution=\(resolution) conflict=\(conflict) released=\(released) final=\(finalResolution)\n"
                FileHandle.standardOutput.write(Data(output.utf8))
                registry.releaseAll()
                NSApp.terminate(nil)
            }
    }
}
