import Foundation

public enum RequirementPriority: String, Codable, CaseIterable, Sendable {
    case unplanned
    case today
    case thisWeek
    case later
}

public enum RequirementStatus: String, Codable, CaseIterable, Sendable {
    case inbox
    case planned
    case active
    case completed
    case archived
}

public struct RequirementRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var source: String
    public let capturedAt: Date
    public var dueDate: Date?
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
            capturedAt: date
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
        requirements.sorted { left, right in
            let leftStatus = statusRank(left.status)
            let rightStatus = statusRank(right.status)
            if leftStatus != rightStatus { return leftStatus < rightStatus }

            let leftPriority = priorityRank(left.priority)
            let rightPriority = priorityRank(right.priority)
            if leftPriority != rightPriority { return leftPriority < rightPriority }

            switch (left.dueDate, right.dueDate) {
            case let (leftDate?, rightDate?) where leftDate != rightDate:
                return leftDate < rightDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return left.capturedAt < right.capturedAt
            }
        }
    }

    public static func attached(
        _ requirement: RequirementRecord,
        to workflowID: UUID
    ) -> RequirementRecord {
        var result = requirement
        result.workflowID = workflowID
        if result.status == .inbox {
            result.status = .planned
        }
        return result
    }

    private static func normalizedText(_ value: String) -> String? {
        let result = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func statusRank(_ status: RequirementStatus) -> Int {
        switch status {
        case .active: return 0
        case .inbox: return 1
        case .planned: return 2
        case .completed: return 3
        case .archived: return 4
        }
    }

    private static func priorityRank(_ priority: RequirementPriority) -> Int {
        switch priority {
        case .today: return 0
        case .thisWeek: return 1
        case .later: return 2
        case .unplanned: return 3
        }
    }
}
