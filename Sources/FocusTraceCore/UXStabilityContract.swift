import Foundation

/// Shipped interaction choices that should only change through an intentional
/// product decision accompanied by updated regression tests.
public enum FocusTraceDateSelectionPresentation: String, Codable, Sendable {
    case graphicalCalendarPopover = "focusTrace.dateSelector.graphicalCalendarPopover"
}

public enum FocusTraceUXContract {
    public static let dateSelectionPresentation: FocusTraceDateSelectionPresentation =
        .graphicalCalendarPopover
    public static let menuBarWidth = 304.0
    public static let workflowNameInputIdentifier = "workflowName"
    public static let onboardingRequiredInputs = [workflowNameInputIdentifier]
    public static let primaryDailyActionCount = 1
    public static let sidebarIconCanvasSize = 18.0
    public static let sidebarTimelineIcon = "clock.arrow.circlepath"
    public static let timelinePaletteName = "verdant-v1"
}

public enum StablePaletteAssignment {
    public static func index(for value: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(count))
    }
}

public enum FocusTraceDateNavigation {
    public static func canMoveForward(
        selection: Date,
        latestDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        calendar.startOfDay(for: selection) < calendar.startOfDay(for: latestDate)
    }

    public static func movedSelection(
        _ selection: Date,
        byDays offset: Int,
        latestDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        let selectedDay = calendar.startOfDay(for: selection)
        let latestDay = calendar.startOfDay(for: latestDate)
        guard let moved = calendar.date(byAdding: .day, value: offset, to: selectedDay) else {
            return min(selectedDay, latestDay)
        }
        return min(moved, latestDay)
    }
}
