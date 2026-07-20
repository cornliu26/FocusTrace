import AppKit
import Foundation
import SwiftUI
import FocusTraceMacSupport

@main
struct FocusTraceApp: App {
    @StateObject private var state: ApplicationState
    private let store: FocusTraceStore
    private let isSpaceAnchorProbe: Bool

    init() {
        let isSpaceAnchorProbe = CommandLine.arguments.contains("--space-anchor-probe")
        self.isSpaceAnchorProbe = isSpaceAnchorProbe
        do {
            let store = try FocusTraceStore(inMemory: isSpaceAnchorProbe)
            self.store = store
            _state = StateObject(wrappedValue: ApplicationState(store: store))
        } catch {
            fatalError("FocusTrace 无法初始化本地数据库：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup("FocusTrace", id: "main") {
            if isSpaceAnchorProbe {
                SpaceAnchorProbeView()
                    .frame(width: 1, height: 1)
            } else {
                RootView(state: state)
                    .frame(minWidth: 920, minHeight: 640)
                    .task { state.start() }
            }
        }
        .defaultSize(width: 1080, height: 760)

        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Label("FocusTrace", systemImage: state.currentFocusID == nil ? "scope" : "scope")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: state)
                .frame(width: 620, height: 560)
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
                let resolution = registry.resolution()
                let conflict = registry.bindCurrentSpace(workflowID: secondWorkflow)
                let released = registry.releaseCurrentSpace()
                let finalResolution = registry.resolution()
                let passed = first == .created(bindingID: bindingID)
                    && resolution == .bound(workflowID: firstWorkflow)
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
