import Foundation

public enum FlowNextAction: Equatable, Sendable {
    case resumeCapture
    case createWorkflow
    case bindWorkflow
    case viewFocus
    case openSchedule
    case startFocus(minutes: Int)
}

public struct FlowGuidance: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let buttonTitle: String
    public let action: FlowNextAction

    public init(title: String, detail: String, buttonTitle: String, action: FlowNextAction) {
        self.title = title
        self.detail = detail
        self.buttonTitle = buttonTitle
        self.action = action
    }
}

public enum WorkflowBindingSurface: Equatable, Sendable {
    case menuBar
    case mainWindow
}

public enum WorkflowBindingSurfacePolicy {
    /// A main app window may live on a different Space from the work the user
    /// was just viewing. Only the status item is presented in the user's
    /// current Space and can therefore give "current desktop" a reliable
    /// meaning.
    public static func canPresentBinding(
        on surface: WorkflowBindingSurface
    ) -> Bool {
        surface == .menuBar
    }

    public static func canPresent(
        _ guidance: FlowGuidance,
        on surface: WorkflowBindingSurface
    ) -> Bool {
        guidance.action != .bindWorkflow || canPresentBinding(on: surface)
    }
}

public enum FlowGuidanceEngine {
    /// Keeps the daily workflow to one visible decision. More detailed setup
    /// remains available, but it never competes with the next required action.
    public static func guidance(
        hasOpenWorkflows: Bool,
        currentWorkflowTitle: String?,
        capturePaused: Bool,
        isWithinSchedule: Bool,
        focusRemainingSeconds: Int?,
        planMinutes: Int
    ) -> FlowGuidance {
        if capturePaused {
            return FlowGuidance(
                title: "记录已暂停",
                detail: "恢复后会继续按当前工作流记录，不需要重新设置。",
                buttonTitle: "恢复记录",
                action: .resumeCapture
            )
        }
        if !hasOpenWorkflows {
            return FlowGuidance(
                title: "先告诉我你现在要推进什么",
                detail: "只起一个工作流名称即可，目标和允许应用都能稍后补充。",
                buttonTitle: "创建当前工作流",
                action: .createWorkflow
            )
        }
        guard let currentWorkflowTitle else {
            return FlowGuidance(
                title: "这个桌面还没有工作流，切换门尚未生效",
                detail: "绑定后，离开或进入工作流桌面时才会询问切换理由。",
                buttonTitle: "选择并绑定当前桌面",
                action: .bindWorkflow
            )
        }
        if let focusRemainingSeconds {
            let minutes = max(0, focusRemainingSeconds) / 60
            let seconds = max(0, focusRemainingSeconds) % 60
            return FlowGuidance(
                title: "正在专注：\(currentWorkflowTitle)",
                detail: String(format: "还剩 %02d:%02d；切回所属桌面会自动继续。", minutes, seconds),
                buttonTitle: "查看本轮专注",
                action: .viewFocus
            )
        }
        if !isWithinSchedule {
            return FlowGuidance(
                title: "已就绪：\(currentWorkflowTitle)",
                detail: "当前不在自动记录时段；调整一次后，之后会自动开始。",
                buttonTitle: "调整记录时段",
                action: .openSchedule
            )
        }
        let minutes = min(50, max(10, planMinutes))
        return FlowGuidance(
            title: "正在记录：\(currentWorkflowTitle)",
            detail: "平时直接工作即可；想做一轮训练时再开始计时。",
            buttonTitle: "开始 \(minutes) 分钟专注",
            action: .startFocus(minutes: minutes)
        )
    }
}
