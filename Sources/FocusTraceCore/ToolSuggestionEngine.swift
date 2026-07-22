import Foundation

public enum ToolSuggestionEngine {
    public static func suggestions(
        from activities: [ActivityRecord],
        taskID: UUID,
        now: Date = Date(),
        limit: Int = 8
    ) -> [AppIdentity] {
        var durations: [String: TimeInterval] = [:]
        var identities: [String: AppIdentity] = [:]
        for activity in activities where activity.taskID == taskID {
            let bundleID = activity.app.bundleID.lowercased()
            let name = activity.app.name.lowercased()
            guard ![.systemInactive, .trackerControl].contains(activity.classification),
                  !SystemActivityGate.isSystemInactiveApp(activity.app),
                  !bundleID.contains(".helper"),
                  !bundleID.contains("uiagent"),
                  !bundleID.contains(".xpc"),
                  !name.contains("helper") else { continue }
            identities[activity.app.bundleID] = activity.app
            durations[activity.app.bundleID, default: 0] += max(
                0,
                (activity.endedAt ?? now).timeIntervalSince(activity.startedAt)
            )
        }
        return durations
            .sorted {
                if $0.value == $1.value { return $0.key < $1.key }
                return $0.value > $1.value
            }
            .prefix(max(1, limit))
            .compactMap { identities[$0.key] }
    }
}
