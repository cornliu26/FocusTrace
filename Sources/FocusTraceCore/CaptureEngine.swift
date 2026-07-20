import Foundation

public struct OpenActivity: Equatable, Sendable {
    public let id: UUID
    public let app: AppIdentity
    public let startedAt: Date

    public init(id: UUID = UUID(), app: AppIdentity, startedAt: Date) {
        self.id = id
        self.app = app
        self.startedAt = startedAt
    }
}

public struct CaptureTransition: Equatable, Sendable {
    public let closed: OpenActivity?
    public let closedAt: Date?
    public let opened: OpenActivity?
    public let ignoredDuplicate: Bool

    public init(
        closed: OpenActivity? = nil,
        closedAt: Date? = nil,
        opened: OpenActivity? = nil,
        ignoredDuplicate: Bool = false
    ) {
        self.closed = closed
        self.closedAt = closedAt
        self.opened = opened
        self.ignoredDuplicate = ignoredDuplicate
    }
}

public struct ActivityCaptureStateMachine: Sendable {
    public private(set) var current: OpenActivity?
    public private(set) var isSystemActive = true

    public init(current: OpenActivity? = nil, isSystemActive: Bool = true) {
        self.current = current
        self.isSystemActive = isSystemActive
    }

    public mutating func activate(_ app: AppIdentity, at date: Date) -> CaptureTransition {
        guard isSystemActive else { return CaptureTransition(ignoredDuplicate: true) }
        if current?.app.bundleID == app.bundleID {
            return CaptureTransition(ignoredDuplicate: true)
        }
        let previous = current
        let opened = OpenActivity(app: app, startedAt: date)
        current = opened
        return CaptureTransition(closed: previous, closedAt: previous == nil ? nil : date, opened: opened)
    }

    public mutating func becomeInactive(at date: Date) -> CaptureTransition {
        guard isSystemActive else { return CaptureTransition(ignoredDuplicate: true) }
        isSystemActive = false
        let previous = current
        current = nil
        return CaptureTransition(closed: previous, closedAt: previous == nil ? nil : date)
    }

    public mutating func becomeActive(_ app: AppIdentity?, at date: Date) -> CaptureTransition {
        guard !isSystemActive else {
            if let app { return activate(app, at: date) }
            return CaptureTransition(ignoredDuplicate: true)
        }
        isSystemActive = true
        guard let app else { return CaptureTransition() }
        let opened = OpenActivity(app: app, startedAt: date)
        current = opened
        return CaptureTransition(opened: opened)
    }

    public mutating func stop(at date: Date) -> CaptureTransition {
        let previous = current
        current = nil
        return CaptureTransition(closed: previous, closedAt: previous == nil ? nil : date)
    }
}

public enum DistractionGate {
    public static func shouldTrigger(
        duration: TimeInterval,
        thresholdSeconds: Int,
        isAllowed: Bool,
        isFocusActive: Bool,
        baselineComplete: Bool
    ) -> Bool {
        isFocusActive
            && baselineComplete
            && !isAllowed
            && duration >= Double(thresholdSeconds)
    }
}

public enum SystemActivityGate {
    public static let loginWindowBundleID = "com.apple.loginwindow"

    public static func isSystemInactiveApp(_ app: AppIdentity) -> Bool {
        app.bundleID == loginWindowBundleID
    }
}

public enum TimelineDateEngine {
    /// Follow midnight only when the user was viewing the previous "today".
    /// A deliberately selected historical date is left untouched.
    public static func selectedDateAfterTick(
        selectedDate: Date,
        previousNow: Date,
        currentNow: Date,
        calendar: Calendar = .current
    ) -> Date {
        let previousDay = calendar.startOfDay(for: previousNow)
        let currentDay = calendar.startOfDay(for: currentNow)
        guard previousDay != currentDay,
              calendar.isDate(selectedDate, inSameDayAs: previousDay) else {
            return selectedDate
        }
        return currentDay
    }
}
