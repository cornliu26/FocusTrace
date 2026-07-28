import Foundation

/// Legacy planning buckets written by FocusTrace 0.2 and earlier.
///
/// They did not record when "today" or "this week" was chosen, so they cannot
/// be migrated into a trustworthy deadline. New product behavior must use
/// `dueDate` and `RequirementImportance` instead.
public enum RequirementPriority: String, Codable, CaseIterable, Sendable {
    case unplanned
    case today
    case thisWeek
    case later
}

public enum RequirementImportance: String, Codable, CaseIterable, Sendable {
    case high
    case normal
    case low
}

public enum RequirementStatus: String, Codable, CaseIterable, Sendable {
    case inbox
    case planned
    case active
    case completed
    case archived
}

public enum RequirementQueueSection: String, Codable, CaseIterable, Sendable {
    case active
    case overdue
    case dueToday
    case upcoming
    case unscheduled
    case needsPlanning
}

public struct RequirementQueueSummary: Equatable, Sendable {
    public let overdueCount: Int
    public let dueTodayCount: Int
    public let needsPlanningCount: Int

    public init(
        overdueCount: Int,
        dueTodayCount: Int,
        needsPlanningCount: Int
    ) {
        self.overdueCount = overdueCount
        self.dueTodayCount = dueTodayCount
        self.needsPlanningCount = needsPlanningCount
    }
}

public struct RequirementRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var source: String
    public let capturedAt: Date
    public var dueDate: Date?
    public var importance: RequirementImportance
    public var reminderSentAt: Date?
    public var planningVersion: Int
    /// Kept only to make old, ambiguous planning visible until the user
    /// confirms a real deadline and importance.
    public var priority: RequirementPriority
    public var status: RequirementStatus
    public var workflowID: UUID?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        source: String = "",
        capturedAt: Date = Date(),
        dueDate: Date? = nil,
        importance: RequirementImportance = .normal,
        reminderSentAt: Date? = nil,
        planningVersion: Int = 1,
        priority: RequirementPriority = .unplanned,
        status: RequirementStatus = .inbox,
        workflowID: UUID? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.capturedAt = capturedAt
        self.dueDate = dueDate
        self.importance = importance
        self.reminderSentAt = reminderSentAt
        self.planningVersion = planningVersion
        self.priority = priority
        self.status = status
        self.workflowID = workflowID
        self.completedAt = completedAt
    }
}

public enum RequirementEngine {
    public static func captured(
        title: String,
        source: String = "",
        at date: Date = Date()
    ) -> RequirementRecord? {
        guard let cleanTitle = normalizedText(title) else { return nil }
        return RequirementRecord(
            title: cleanTitle,
            source: normalizedText(source) ?? "",
            capturedAt: date,
            planningVersion: 0
        )
    }

    public static func suggestedWorkflowTitle(
        from requirementTitle: String,
        maximumLength: Int = 36
    ) -> String {
        let clean = normalizedText(requirementTitle) ?? "新工作流"
        let firstSentence = clean.split(
            whereSeparator: { "。！？!?；;".contains($0) }
        ).first.map(String.init) ?? clean
        let limit = max(8, maximumLength)
        guard firstSentence.count > limit else { return firstSentence }
        let end = firstSentence.index(firstSentence.startIndex, offsetBy: limit)
        return String(firstSentence[..<end]).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    public static func ordered(_ requirements: [RequirementRecord]) -> [RequirementRecord] {
        ordered(requirements, at: Date())
    }

    public static func ordered(
        _ requirements: [RequirementRecord],
        at date: Date,
        calendar: Calendar = .current
    ) -> [RequirementRecord] {
        let today = calendar.startOfDay(for: date)
        return requirements.map { requirement in
            let dueDay = requirement.dueDate.map {
                calendar.startOfDay(for: $0)
            }
            return RequirementOrderingEntry(
                requirement: requirement,
                rank: orderingRank(
                    requirement,
                    dueDay: dueDay,
                    today: today
                ),
                dueDay: dueDay,
                importance: importanceRank(requirement.importance)
            )
        }.sorted { left, right in
            if left.rank != right.rank { return left.rank < right.rank }

            if left.dueDay != right.dueDay {
                switch (left.dueDay, right.dueDay) {
                case let (leftDate?, rightDate?):
                    return leftDate < rightDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    break
                }
            }

            if left.importance != right.importance {
                return left.importance < right.importance
            }
            return left.requirement.capturedAt < right.requirement.capturedAt
        }.map(\.requirement)
    }

    public static func planned(
        _ requirement: RequirementRecord,
        dueDate: Date?,
        importance: RequirementImportance,
        workflowID: UUID?,
        calendar: Calendar = .current
    ) -> RequirementRecord {
        var result = requirement
        let normalizedDueDate = dueDate.map { calendar.startOfDay(for: $0) }
        if result.dueDate != normalizedDueDate {
            result.reminderSentAt = nil
        }
        result.dueDate = normalizedDueDate
        result.importance = importance
        result.workflowID = workflowID
        result.planningVersion = 1
        result.priority = .unplanned
        if result.status == .inbox {
            result.status = .planned
        }
        return result
    }

    public static func attached(
        _ requirement: RequirementRecord,
        to workflowID: UUID
    ) -> RequirementRecord {
        var result = requirement
        result.workflowID = workflowID
        return result
    }

    public static func started(
        _ requirement: RequirementRecord,
        in workflowID: UUID
    ) -> RequirementRecord {
        var result = requirement
        result.workflowID = workflowID
        result.status = .active
        result.completedAt = nil
        return result
    }

    public static func completed(
        _ requirement: RequirementRecord,
        at date: Date = Date()
    ) -> RequirementRecord {
        var result = requirement
        result.status = .completed
        result.completedAt = date
        return result
    }

    public static func paused(_ requirement: RequirementRecord) -> RequirementRecord {
        var result = requirement
        result.status = result.planningVersion >= 1 && result.priority == .unplanned
            ? .planned
            : .inbox
        return result
    }

    public static func archived(_ requirement: RequirementRecord) -> RequirementRecord {
        var result = requirement
        result.status = .archived
        return result
    }

    public static func detachedFromWorkflow(
        _ requirement: RequirementRecord,
        workflowID: UUID
    ) -> RequirementRecord {
        guard requirement.workflowID == workflowID,
              ![RequirementStatus.completed, .archived].contains(requirement.status)
        else {
            return requirement
        }
        var result = requirement
        result.workflowID = nil
        if result.status == .active {
            result.status = result.planningVersion >= 1 && result.priority == .unplanned
                ? .planned
                : .inbox
        }
        return result
    }

    public static func needsPlanning(_ requirement: RequirementRecord) -> Bool {
        requirement.status == .inbox
            || requirement.planningVersion < 1
            || requirement.priority != .unplanned
    }

    public static func queueSection(
        for requirement: RequirementRecord,
        at date: Date,
        calendar: Calendar = .current
    ) -> RequirementQueueSection? {
        guard ![RequirementStatus.completed, .archived].contains(requirement.status) else {
            return nil
        }
        if requirement.status == .active { return .active }
        if needsPlanning(requirement) { return .needsPlanning }
        guard let dueDate = requirement.dueDate else { return .unscheduled }

        let dueDay = calendar.startOfDay(for: dueDate)
        let today = calendar.startOfDay(for: date)
        if dueDay < today { return .overdue }
        if dueDay == today { return .dueToday }
        return .upcoming
    }

    public static func summary(
        _ requirements: [RequirementRecord],
        at date: Date,
        calendar: Calendar = .current
    ) -> RequirementQueueSummary {
        var overdueCount = 0
        var dueTodayCount = 0
        var needsPlanningCount = 0
        for requirement in requirements {
            switch queueSection(for: requirement, at: date, calendar: calendar) {
            case .overdue:
                overdueCount += 1
            case .dueToday:
                dueTodayCount += 1
            case .needsPlanning:
                needsPlanningCount += 1
            default:
                break
            }
        }
        return RequirementQueueSummary(
            overdueCount: overdueCount,
            dueTodayCount: dueTodayCount,
            needsPlanningCount: needsPlanningCount
        )
    }

    public static func dueForReminder(
        _ requirements: [RequirementRecord],
        at date: Date,
        calendar: Calendar = .current
    ) -> [RequirementRecord] {
        ordered(requirements, at: date, calendar: calendar).filter { requirement in
            guard requirement.reminderSentAt == nil,
                  !needsPlanning(requirement),
                  requirement.status == .planned,
                  let dueDate = requirement.dueDate
            else {
                return false
            }
            return calendar.startOfDay(for: dueDate) <= calendar.startOfDay(for: date)
        }
    }

    private static func normalizedText(_ value: String) -> String? {
        let result = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func orderingRank(
        _ requirement: RequirementRecord,
        dueDay: Date?,
        today: Date
    ) -> Int {
        if requirement.status == .active { return 0 }
        if [RequirementStatus.completed, .archived].contains(requirement.status) {
            return statusRank(requirement.status)
        }
        if needsPlanning(requirement) { return 5 }
        guard let dueDay else { return 4 }
        if dueDay < today { return 1 }
        if dueDay == today { return 2 }
        return 3
    }

    private static func statusRank(_ status: RequirementStatus) -> Int {
        switch status {
        case .active: return 0
        case .inbox, .planned: return 5
        case .completed: return 6
        case .archived: return 7
        }
    }

    private static func importanceRank(_ importance: RequirementImportance) -> Int {
        switch importance {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }

    private struct RequirementOrderingEntry {
        let requirement: RequirementRecord
        let rank: Int
        let dueDay: Date?
        let importance: Int
    }
}
