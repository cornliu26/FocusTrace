import AppKit
import Foundation
import UserNotifications

final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let interruptionCategory = "FOCUS_TRACE_INTERRUPTION"
    static let returnAction = "RETURN_TO_TASK"
    static let necessaryAction = "MARK_NECESSARY"
    static let switchTaskAction = "SWITCH_TASK"
    static let endSessionAction = "END_SESSION"
    static let taskParkingCategory = "FOCUS_TRACE_TASK_PARKING"
    static let resumeParkingAction = "RESUME_PARKED_TASK"
    static let dismissParkingAction = "DISMISS_PARKED_TASK"

    weak var state: ApplicationState?

    func configure() {
        let actions = [
            UNNotificationAction(identifier: Self.returnAction, title: "返回任务", options: [.foreground]),
            UNNotificationAction(identifier: Self.necessaryAction, title: "本任务所需"),
            UNNotificationAction(identifier: Self.switchTaskAction, title: "切换任务", options: [.foreground]),
            UNNotificationAction(identifier: Self.endSessionAction, title: "结束专注", options: [.destructive])
        ]
        let category = UNNotificationCategory(
            identifier: Self.interruptionCategory,
            actions: actions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let taskParkingCategory = UNNotificationCategory(
            identifier: Self.taskParkingCategory,
            actions: [
                UNNotificationAction(
                    identifier: Self.resumeParkingAction,
                    title: "返回任务",
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: Self.dismissParkingAction,
                    title: "不再返回"
                )
            ],
            intentIdentifiers: []
        )
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([category, taskParkingCategory])
        center.delegate = self
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func sendInterruption(id: UUID, appName: String, taskName: String) {
        let content = UNMutableNotificationContent()
        content.title = "还在做「\(taskName)」吗？"
        content.body = "已在 \(appName) 停留一段时间。必要切换可以直接标记，不会算作分心。"
        content.categoryIdentifier = Self.interruptionCategory
        content.userInfo = ["interruptionID": id.uuidString]
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "interruption-\(id.uuidString)",
            content: content,
            trigger: nil
        )
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    func sendTargetReached(minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "本轮专注目标已完成"
        content.body = "你已经完成 \(minutes) 分钟。可以收尾并记录结果。"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "target-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    func sendTaskParkingReminder(id: UUID, taskName: String, resumeCue: String) {
        let content = UNMutableNotificationContent()
        content.title = "该回到「\(taskName)」了"
        content.body = "下一步：\(resumeCue)"
        content.categoryIdentifier = Self.taskParkingCategory
        content.userInfo = ["taskParkingID": id.uuidString]
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "task-parking-\(id.uuidString)",
            content: content,
            trigger: nil
        )
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if let rawID = response.notification.request.content.userInfo["taskParkingID"] as? String,
           let id = UUID(uuidString: rawID) {
            let action = response.actionIdentifier
            await MainActor.run { [weak self] in
                guard let state = self?.state else { return }
                switch action {
                case Self.resumeParkingAction, UNNotificationDefaultActionIdentifier:
                    state.resumeTaskParking(id)
                case Self.dismissParkingAction:
                    state.dismissTaskParking(id)
                default:
                    break
                }
            }
            return
        }
        guard let rawID = response.notification.request.content.userInfo["interruptionID"] as? String,
              let id = UUID(uuidString: rawID) else { return }
        let action = response.actionIdentifier
        await MainActor.run { [weak self] in
            guard let state = self?.state else { return }
            switch action {
            case Self.returnAction, UNNotificationDefaultActionIdentifier:
                state.returnToTask(interruptionID: id)
            case Self.necessaryAction:
                state.markNecessary(interruptionID: id)
            case Self.switchTaskAction:
                state.prepareTaskSwitch(interruptionID: id)
            case Self.endSessionAction:
                state.endFocusFromInterruption(interruptionID: id)
            default:
                break
            }
        }
    }
}
