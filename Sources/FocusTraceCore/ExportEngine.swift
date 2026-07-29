import Foundation

public struct ExportBundle: Codable, Sendable {
    public let exportedAt: Date
    public let tasks: [TaskRecord]
    public let taskIntervals: [TaskIntervalRecord]
    public let activities: [ActivityRecord]
    public let focusSessions: [FocusSessionRecord]
    public let interruptions: [InterruptionRecord]
    public let trainingPlans: [TrainingPlanRecord]
    public let attentionExperiments: [AttentionExperimentRecord]
    public let markers: [TimelineMarkerRecord]
    public let taskParkings: [TaskParkingRecord]

    public init(
        exportedAt: Date = Date(),
        tasks: [TaskRecord],
        taskIntervals: [TaskIntervalRecord],
        activities: [ActivityRecord],
        focusSessions: [FocusSessionRecord],
        interruptions: [InterruptionRecord],
        trainingPlans: [TrainingPlanRecord],
        attentionExperiments: [AttentionExperimentRecord] = [],
        markers: [TimelineMarkerRecord],
        taskParkings: [TaskParkingRecord] = []
    ) {
        self.exportedAt = exportedAt
        self.tasks = tasks
        self.taskIntervals = taskIntervals
        self.activities = activities
        self.focusSessions = focusSessions
        self.interruptions = interruptions
        self.trainingPlans = trainingPlans
        self.attentionExperiments = attentionExperiments
        self.markers = markers
        self.taskParkings = taskParkings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        tasks = try container.decodeIfPresent([TaskRecord].self, forKey: .tasks) ?? []
        taskIntervals = try container.decodeIfPresent([TaskIntervalRecord].self, forKey: .taskIntervals) ?? []
        activities = try container.decodeIfPresent([ActivityRecord].self, forKey: .activities) ?? []
        focusSessions = try container.decodeIfPresent([FocusSessionRecord].self, forKey: .focusSessions) ?? []
        interruptions = try container.decodeIfPresent([InterruptionRecord].self, forKey: .interruptions) ?? []
        trainingPlans = try container.decodeIfPresent([TrainingPlanRecord].self, forKey: .trainingPlans) ?? []
        attentionExperiments = try container.decodeIfPresent(
            [AttentionExperimentRecord].self,
            forKey: .attentionExperiments
        ) ?? []
        markers = try container.decodeIfPresent([TimelineMarkerRecord].self, forKey: .markers) ?? []
        taskParkings = try container.decodeIfPresent([TaskParkingRecord].self, forKey: .taskParkings) ?? []
    }
}

public enum ExportEngine {
    public static func jsonData(_ bundle: ExportBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    public static func activitiesCSV(_ activities: [ActivityRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        let header = "id,start_at,end_at,duration_seconds,app_name,bundle_id,task_id,focus_session_id,classification,source"
        let rows = activities.sorted { $0.startedAt < $1.startedAt }.map { item in
            [
                item.id.uuidString,
                formatter.string(from: item.startedAt),
                item.endedAt.map(formatter.string(from:)) ?? "",
                String(format: "%.3f", item.duration()),
                csvEscape(item.app.name),
                csvEscape(item.app.bundleID),
                item.taskID?.uuidString ?? "",
                item.focusSessionID?.uuidString ?? "",
                item.classification.rawValue,
                item.source.rawValue
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
