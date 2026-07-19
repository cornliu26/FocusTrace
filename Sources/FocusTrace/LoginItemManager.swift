import Foundation
import ServiceManagement

@MainActor
enum LoginItemManager {
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                try service.register()
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "已启用"
        case .requiresApproval: return "等待在系统设置中批准"
        case .notFound: return "仅打包后的 .app 支持"
        case .notRegistered: return "未启用"
        @unknown default: return "未知"
        }
    }
}
