import SwiftUI

@main
struct FocusTraceApp: App {
    @StateObject private var state: ApplicationState
    private let store: FocusTraceStore

    init() {
        do {
            let store = try FocusTraceStore()
            self.store = store
            _state = StateObject(wrappedValue: ApplicationState(store: store))
        } catch {
            fatalError("FocusTrace 无法初始化本地数据库：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup("FocusTrace", id: "main") {
            RootView(state: state)
                .frame(minWidth: 920, minHeight: 640)
                .task { state.start() }
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
