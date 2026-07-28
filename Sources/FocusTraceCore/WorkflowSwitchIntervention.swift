import Foundation

/// Why FocusTrace asked for a decision at this workflow boundary.
///
/// The value is intentionally coarse: it records the policy decision, not
/// screen content, gestures or any free-form user text.
public enum WorkflowInterventionTrigger: String, Codable, CaseIterable, Sendable {
    case frequentSwitchBurst
}

public struct WorkflowInterventionConfiguration: Codable, Equatable, Sendable {
    public let version: Int
    public let windowSeconds: TimeInterval
    public let switchThreshold: Int
    public let cooldownSeconds: TimeInterval
    public let minimumBaselineWorkdays: Int
    public let minimumAssessmentWindows: Int

    public init(
        version: Int,
        windowSeconds: TimeInterval,
        switchThreshold: Int,
        cooldownSeconds: TimeInterval,
        minimumBaselineWorkdays: Int,
        minimumAssessmentWindows: Int
    ) {
        self.version = version
        self.windowSeconds = windowSeconds
        self.switchThreshold = switchThreshold
        self.cooldownSeconds = cooldownSeconds
        self.minimumBaselineWorkdays = minimumBaselineWorkdays
        self.minimumAssessmentWindows = minimumAssessmentWindows
    }

    public static let initial = WorkflowInterventionConfiguration(
        version: 1,
        windowSeconds: 10 * 60,
        switchThreshold: 3,
        cooldownSeconds: 10 * 60,
        minimumBaselineWorkdays: 3,
        minimumAssessmentWindows: 5
    )
}

public struct WorkflowSwitchInterventionDecision: Equatable, Sendable {
    public let shouldPrompt: Bool
    public let switchesInWindow: Int
    public let trigger: WorkflowInterventionTrigger?

    public init(
        shouldPrompt: Bool,
        switchesInWindow: Int,
        trigger: WorkflowInterventionTrigger?
    ) {
        self.shouldPrompt = shouldPrompt
        self.switchesInWindow = switchesInWindow
        self.trigger = trigger
    }
}

public struct WorkflowInterventionAudit: Equatable, Sendable {
    public let frequentSwitchEpisodes: Int
    public let promptsShown: Int
    public let confirmedPrompts: Int
    public let timedOutPrompts: Int
    public let assessedPrompts: Int
    public let quietAfterPromptCount: Int

    public init(
        frequentSwitchEpisodes: Int,
        promptsShown: Int,
        confirmedPrompts: Int,
        timedOutPrompts: Int,
        assessedPrompts: Int,
        quietAfterPromptCount: Int
    ) {
        self.frequentSwitchEpisodes = frequentSwitchEpisodes
        self.promptsShown = promptsShown
        self.confirmedPrompts = confirmedPrompts
        self.timedOutPrompts = timedOutPrompts
        self.assessedPrompts = assessedPrompts
        self.quietAfterPromptCount = quietAfterPromptCount
    }

    public var promptCoverage: Double? {
        guard frequentSwitchEpisodes > 0 else { return nil }
        return Double(promptsShown) / Double(frequentSwitchEpisodes)
    }

    public var confirmationRate: Double? {
        guard promptsShown > 0 else { return nil }
        return Double(confirmedPrompts) / Double(promptsShown)
    }

    public var quietAfterPromptRate: Double? {
        guard assessedPrompts > 0 else { return nil }
        return Double(quietAfterPromptCount) / Double(assessedPrompts)
    }
}

/// A deliberately conservative just-in-time policy.
///
/// One or two verified workflow switches can be ordinary multitasking. The
/// third final workflow-to-workflow switch inside ten minutes is the first
/// decision point. After that prompt, the policy stays silent for another ten
/// minutes so FocusTrace cannot become the interruption it is measuring.
public enum WorkflowSwitchInterventionEngine {
    public static let windowSeconds = WorkflowInterventionConfiguration.initial.windowSeconds
    public static let switchThreshold = WorkflowInterventionConfiguration.initial.switchThreshold
    public static let cooldownSeconds = WorkflowInterventionConfiguration.initial.cooldownSeconds

    public static func decision(
        history: [WorkflowTransitionRecord],
        origin: WorkflowTransitionEndpoint,
        destination: WorkflowTransitionEndpoint,
        at date: Date,
        isEnabled: Bool,
        configuration: WorkflowInterventionConfiguration = .initial
    ) -> WorkflowSwitchInterventionDecision {
        guard isEnabled,
              isWorkflowSwitch(origin: origin, destination: destination) else {
            return WorkflowSwitchInterventionDecision(
                shouldPrompt: false,
                switchesInWindow: 0,
                trigger: nil
            )
        }

        let recent = history.filter {
            isFinalWorkflowSwitch($0)
                && $0.resolvedAt < date
                && $0.resolvedAt >= date.addingTimeInterval(
                    -configuration.windowSeconds
                )
        }
        let countIncludingCurrent = recent.count + 1
        let isCoolingDown = history.contains {
            $0.interventionTrigger != nil
                && $0.resolvedAt < date
                && $0.resolvedAt >= date.addingTimeInterval(
                    -configuration.cooldownSeconds
                )
        }
        let shouldPrompt = !isCoolingDown
            && countIncludingCurrent >= configuration.switchThreshold
        return WorkflowSwitchInterventionDecision(
            shouldPrompt: shouldPrompt,
            switchesInWindow: countIncludingCurrent,
            trigger: shouldPrompt ? .frequentSwitchBurst : nil
        )
    }

    public static func audit(
        transitions: [WorkflowTransitionRecord],
        range: Range<Date>,
        now: Date,
        configuration: WorkflowInterventionConfiguration = .initial
    ) -> WorkflowInterventionAudit {
        let finalSwitches = transitions
            .filter {
                range.contains($0.resolvedAt)
                    && isFinalWorkflowSwitch($0)
            }
            .sorted { $0.resolvedAt < $1.resolvedAt }

        var episodeDates: [Date] = []
        var windowStartIndex = 0
        for (index, transition) in finalSwitches.enumerated() {
            let windowStart = transition.resolvedAt.addingTimeInterval(
                -configuration.windowSeconds
            )
            while windowStartIndex < index,
                  finalSwitches[windowStartIndex].resolvedAt < windowStart {
                windowStartIndex += 1
            }
            if let last = episodeDates.last,
               transition.resolvedAt.timeIntervalSince(last)
                < configuration.cooldownSeconds {
                continue
            }
            let priorCount = index - windowStartIndex
            if priorCount + 1 >= configuration.switchThreshold {
                episodeDates.append(transition.resolvedAt)
            }
        }

        let prompts = finalSwitches.filter {
            $0.interventionTrigger == .frequentSwitchBurst
                && ($0.outcome == .confirmed || $0.outcome == .timedOut)
        }
        let completedAssessmentCutoff = min(now, range.upperBound)
        let assessed = prompts.filter {
            $0.resolvedAt.addingTimeInterval(configuration.cooldownSeconds)
                <= completedAssessmentCutoff
        }
        let quiet = assessed.filter { prompt in
            !finalSwitches.contains {
                $0.resolvedAt > prompt.resolvedAt
                    && $0.resolvedAt
                        <= prompt.resolvedAt.addingTimeInterval(
                            configuration.cooldownSeconds
                        )
            }
        }

        return WorkflowInterventionAudit(
            frequentSwitchEpisodes: episodeDates.count,
            promptsShown: prompts.count,
            confirmedPrompts: prompts.filter { $0.outcome == .confirmed }.count,
            timedOutPrompts: prompts.filter { $0.outcome == .timedOut }.count,
            assessedPrompts: assessed.count,
            quietAfterPromptCount: quiet.count
        )
    }

    public static func isFinalWorkflowSwitch(
        _ transition: WorkflowTransitionRecord
    ) -> Bool {
        transition.source == .space
            && [.confirmed, .timedOut, .automatic].contains(
                transition.outcome
            )
            && isWorkflowSwitch(
                origin: transition.origin,
                destination: transition.destination
            )
    }

    private static func isWorkflowSwitch(
        origin: WorkflowTransitionEndpoint,
        destination: WorkflowTransitionEndpoint
    ) -> Bool {
        origin.kind == .workflow
            && destination.kind == .workflow
            && origin.workflowID != nil
            && destination.workflowID != nil
            && origin.workflowID != destination.workflowID
    }
}
