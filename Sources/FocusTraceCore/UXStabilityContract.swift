import Foundation

/// Shipped interaction choices that should only change through an intentional
/// product decision accompanied by updated regression tests.
public enum FocusTraceDateSelectionPresentation: String, Codable, Sendable {
    case graphicalCalendarPopover = "focusTrace.dateSelector.graphicalCalendarPopover"
}

public enum FocusTraceRequirementDateSelectionPresentation: String, Codable, Sendable {
    case graphicalCalendarPopover =
        "focusTrace.requirementDateSelector.graphicalCalendarPopover"
}

public enum FocusTraceCalendarPopoverEvent: Sendable {
    case anchorPressed
    case dismissRequested
}

public enum FocusTraceCalendarPopoverState {
    public static func next(
        isPresented: Bool,
        event: FocusTraceCalendarPopoverEvent
    ) -> Bool {
        switch event {
        case .anchorPressed:
            return !isPresented
        case .dismissRequested:
            return false
        }
    }
}

public enum FocusTraceCalendarBounds {
    public static func isSelectable(
        _ date: Date,
        minimumDate: Date? = nil,
        maximumDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Bool {
        let day = calendar.startOfDay(for: date)
        if let minimumDate,
           day < calendar.startOfDay(for: minimumDate) {
            return false
        }
        if let maximumDate,
           day > calendar.startOfDay(for: maximumDate) {
            return false
        }
        return true
    }

    public static func movedMonth(
        from month: Date,
        by offset: Int,
        minimumDate: Date? = nil,
        maximumDate: Date? = nil,
        calendar: Calendar = .current
    ) -> Date {
        let currentMonth = FocusTraceCalendarLayoutEngine.startOfMonth(
            containing: month,
            calendar: calendar
        )
        guard let moved = calendar.date(
            byAdding: .month,
            value: offset,
            to: currentMonth
        ) else {
            return currentMonth
        }
        var result = FocusTraceCalendarLayoutEngine.startOfMonth(
            containing: moved,
            calendar: calendar
        )
        if let minimumDate {
            result = max(
                result,
                FocusTraceCalendarLayoutEngine.startOfMonth(
                    containing: minimumDate,
                    calendar: calendar
                )
            )
        }
        if let maximumDate {
            result = min(
                result,
                FocusTraceCalendarLayoutEngine.startOfMonth(
                    containing: maximumDate,
                    calendar: calendar
                )
            )
        }
        return result
    }
}

public enum FocusTraceDisclosureInteraction {
    public static let hitTargetSize = 36.0

    public static func stateAfterHeaderPress(isExpanded: Bool) -> Bool {
        !isExpanded
    }
}

public enum FocusTraceUXContract {
    public static let dateSelectionPresentation: FocusTraceDateSelectionPresentation =
        .graphicalCalendarPopover
    public static let requirementDateSelectionPresentation:
        FocusTraceRequirementDateSelectionPresentation = .graphicalCalendarPopover
    public static let calendarPopoverAnimationsEnabled = false
    public static let calendarRefreshGranularity = Calendar.Component.day
    public static let calendarPrewarmMonthOffsets = [-1, 0, 1]
    public static let menuBarWidth = 304.0
    public static let workflowNameInputIdentifier = "workflowName"
    public static let onboardingRequiredInputs = [workflowNameInputIdentifier]
    public static let primaryDailyActionCount = 1
    public static let sidebarIconCanvasSize = 18.0
    public static let sidebarTimelineIcon = "clock.arrow.circlepath"
    public static let timelinePaletteName = "radix-cool-v4"
    public static let timelineCurrentWorkflowOutlineEnabled = false
}

/// Geometry shared by every row in the timeline chart.
///
/// Row titles need enough fixed space for four Chinese characters, while hour
/// labels are centered inside the plot instead of on its outer edges. Keeping
/// these values in the core contract makes narrow-window regressions testable
/// without rendering SwiftUI.
public enum FocusTraceTimelineLayout {
    public static let rowLabelWidth = 76.0
    public static let rowSpacing = 10.0
    public static let endpointHourLabelInset = 22.0
    public static let hourLabelCount = 5

    public static func hourLabelCenterX(
        index: Int,
        availableWidth: Double
    ) -> Double {
        guard availableWidth > 0 else { return 0 }
        let finalIndex = max(1, hourLabelCount - 1)
        let clampedIndex = min(max(0, index), finalIndex)
        let inset = min(endpointHourLabelInset, availableWidth / 2)
        let usableWidth = max(0, availableWidth - inset * 2)
        return inset + usableWidth * Double(clampedIndex) / Double(finalIndex)
    }
}

/// Keeps trend strokes and point markers inside their Canvas instead of
/// letting the first or final marker be clipped at a neighboring text column.
public enum FocusTraceAttentionTrendLayout {
    public static let plotInset = 5.0
    public static let pointRadius = 3.5

    public static func shouldPlot(isPartial: Bool) -> Bool {
        !isPartial
    }

    public static func pointX(
        index: Int,
        pointCount: Int,
        availableWidth: Double
    ) -> Double {
        guard availableWidth > 0 else { return 0 }
        guard pointCount > 1 else { return availableWidth / 2 }
        let finalIndex = pointCount - 1
        let clampedIndex = min(max(0, index), finalIndex)
        let inset = min(plotInset, availableWidth / 2)
        let usableWidth = max(0, availableWidth - inset * 2)
        return inset
            + usableWidth * Double(clampedIndex) / Double(finalIndex)
    }
}

/// The app has one durable work context, so every entry point must reuse the
/// same main window instead of creating visual copies of that context.
public enum FocusTraceWindowContract {
    public static let mainWindowID = "main"
    public static let allowsMultipleMainWindows = false
    public static let exposesDedicatedSettingsWindow = false
}

public enum FocusTraceDataSettingsRow: String, CaseIterable, Sendable {
    case retention
    case export
    case deletion
}

public enum FocusTraceDataSettingsContract {
    public static let rows = FocusTraceDataSettingsRow.allCases
    public static let visibleDeletionEntryCount = 1
    public static let deletionScopeCount = 2
    public static let destructiveActionsRequireConfirmation = true
}

public enum FocusTraceGettingStartedPhase: String, CaseIterable, Sendable {
    case createWorkflow
    case bindDesktop
    case workNormally
    case reviewEvidence
}

public struct FocusTraceGettingStartedStep: Equatable, Identifiable, Sendable {
    public let id: FocusTraceGettingStartedPhase
    public let title: String
    public let detail: String

    public init(
        id: FocusTraceGettingStartedPhase,
        title: String,
        detail: String
    ) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public enum FocusTraceGettingStartedContract {
    public static let steps = [
        FocusTraceGettingStartedStep(
            id: .createWorkflow,
            title: "创建一个工作流",
            detail: "只写正在推进的事情，例如“排查登录问题”；目标和允许应用都可以稍后补。"
        ),
        FocusTraceGettingStartedStep(
            id: .bindDesktop,
            title: "在真正工作的桌面绑定",
            detail: "切回普通或全屏工作桌面，点击屏幕顶部的 FocusTrace，再选择刚创建的工作流。"
        ),
        FocusTraceGettingStartedStep(
            id: .workNormally,
            title: "正常工作，不用盯着 FocusTrace",
            detail: "工作时段会自动形成轨迹；应用切换只是事实，不会因为一次切屏就被判定为分心。"
        ),
        FocusTraceGettingStartedStep(
            id: .reviewEvidence,
            title: "下班后看回顾，只改一件事",
            detail: "先用时间轴解释高切换区间，再根据可靠趋势选择一个可以验证的调整。"
        )
    ]

    public static func phase(
        hasOpenWorkflow: Bool,
        requiresDesktopBinding: Bool,
        hasVerifiedDesktopBinding: Bool,
        hasRecordedActivity: Bool
    ) -> FocusTraceGettingStartedPhase {
        guard hasOpenWorkflow else { return .createWorkflow }
        if requiresDesktopBinding && !hasVerifiedDesktopBinding {
            return .bindDesktop
        }
        guard hasRecordedActivity else { return .workNormally }
        return .reviewEvidence
    }
}

public struct FocusTraceRGBColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xff) / 255
        green = Double((hex >> 8) & 0xff) / 255
        blue = Double(hex & 0xff) / 255
    }

    public var hexadecimalRGB: UInt32 {
        let redValue = UInt32((red * 255).rounded())
        let greenValue = UInt32((green * 255).rounded())
        let blueValue = UInt32((blue * 255).rounded())
        return (redValue << 16) | (greenValue << 8) | blueValue
    }

}

/// Exact sRGB tokens from Radix Colors 3.0.0.
///
/// Workflows use solid step 9 colors; applications use the corresponding
/// softer step 8 colors. The sequence stays inside FocusTrace's jade-to-iris
/// brand family. Amber and tomato are reserved for switching severity.
public enum FocusTraceTimelinePalette {
    public static let workflows = [
        FocusTraceRGBColor(hex: 0x29A383), // Jade 9
        FocusTraceRGBColor(hex: 0x00A2C7), // Cyan 9
        FocusTraceRGBColor(hex: 0x0090FF), // Blue 9
        FocusTraceRGBColor(hex: 0x3E63DD), // Indigo 9
        FocusTraceRGBColor(hex: 0x5B5BD6)  // Iris 9
    ]

    public static let applications = [
        FocusTraceRGBColor(hex: 0x56BA9F), // Jade 8
        FocusTraceRGBColor(hex: 0x3DB9CF), // Cyan 8
        FocusTraceRGBColor(hex: 0x5EB1EF), // Blue 8
        FocusTraceRGBColor(hex: 0x8DA4EF), // Indigo 8
        FocusTraceRGBColor(hex: 0x9B9EF0)  // Iris 8
    ]

    public static let workflowOther = FocusTraceRGBColor(hex: 0x8B8D98) // Slate 9
    public static let applicationOther = FocusTraceRGBColor(hex: 0xB9BBC6) // Slate 8

    public static let quiet = FocusTraceRGBColor(hex: 0x29A383) // Jade 9
    public static let steady = FocusTraceRGBColor(hex: 0x00A2C7) // Cyan 9
    public static let fragmented = FocusTraceRGBColor(hex: 0xFFC53D) // Amber 9
    public static let intense = FocusTraceRGBColor(hex: 0xE54D2E) // Tomato 9

    public static var densityScale: [FocusTraceRGBColor] {
        [quiet, steady, fragmented, intense]
    }

}

public enum TimelineCategoryPaletteAssignment {
    public static let maximumColoredCategories = 5

    public static func index(
        for id: String,
        rankedIDs: [String]
    ) -> Int? {
        guard let index = rankedIDs.prefix(maximumColoredCategories)
            .firstIndex(of: id)
        else {
            return nil
        }
        return rankedIDs.distance(from: rankedIDs.startIndex, to: index)
    }
}

/// Stable workloads and upper bounds for performance-sensitive daily paths.
///
/// These are regression budgets, not benchmark claims. Change them only with
/// measured evidence and an explicit update to Docs/QUALITY_GATES.md.
public enum FocusTracePerformanceBudget {
    public static let calendarMonthOffsets = Array(-18...18)
    public static let calendarLayoutMaximumSeconds = 1.0
    public static let timelineActivityCount = 2_000
    public static let timelineMarkerCount = 300
    public static let timelinePresentationMaximumSeconds = 1.0
    public static let requirementQueueCount = 1_000
    public static let requirementQueueMaximumSeconds = 0.1
    public static let reviewDashboardActivityCount = 2_000
    public static let reviewDashboardTransitionCount = 1_000
    public static let reviewDashboardParkingCount = 1_000
    public static let reviewDashboardMaximumSeconds = 1.0
    public static let attentionExperimentWorkflowIntervalCount = 2_000
    public static let attentionExperimentTrainingCount = 1_000
    public static let attentionExperimentMaximumSeconds = 0.1
}

/// Product-level visual semantics. The implementation may adopt newer system
/// rendering, but these roles must not drift between OS versions.
public enum FocusTraceFunctionalLayerContract {
    public static let minimumGlassOSMajorVersion = 26
    public static let usesSingleSystemPageTitle = true
    public static let glassIsLimitedToFunctionalSurfaces = true
    public static let contentCardsRemainStableSurfaces = true
    public static let reduceTransparencyHasOpaqueFallback = true
}

public struct FocusTraceCalendarDayLayout: Equatable, Identifiable, Sendable {
    public let id: Int
    public let date: Date?
    public let dayText: String
    public let accessibilityLabel: String

    public init(
        id: Int,
        date: Date?,
        dayText: String,
        accessibilityLabel: String
    ) {
        self.id = id
        self.date = date
        self.dayText = dayText
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct FocusTraceCalendarMonthLayout: Equatable, Sendable {
    public let month: Date
    public let title: String
    public let weekdaySymbols: [String]
    public let cells: [FocusTraceCalendarDayLayout]

    public init(
        month: Date,
        title: String,
        weekdaySymbols: [String],
        cells: [FocusTraceCalendarDayLayout]
    ) {
        self.month = month
        self.title = title
        self.weekdaySymbols = weekdaySymbols
        self.cells = cells
    }
}

public enum FocusTraceCalendarLayoutEngine {
    public static func layout(
        containing date: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> FocusTraceCalendarMonthLayout {
        let month = startOfMonth(containing: date, calendar: calendar)
        let weekdaySymbols = rotatedWeekdaySymbols(
            calendar: calendar,
            locale: locale
        )
        let monthTitleFormatter = DateFormatter()
        monthTitleFormatter.calendar = calendar
        monthTitleFormatter.locale = locale
        monthTitleFormatter.timeZone = calendar.timeZone
        monthTitleFormatter.setLocalizedDateFormatFromTemplate("yMMMM")

        let accessibilityFormatter = DateFormatter()
        accessibilityFormatter.calendar = calendar
        accessibilityFormatter.locale = locale
        accessibilityFormatter.timeZone = calendar.timeZone
        accessibilityFormatter.dateStyle = .long
        accessibilityFormatter.timeStyle = .none

        guard let dayRange = calendar.range(of: .day, in: .month, for: month),
              let weekday = calendar.dateComponents([.weekday], from: month).weekday
        else {
            return FocusTraceCalendarMonthLayout(
                month: month,
                title: monthTitleFormatter.string(from: month),
                weekdaySymbols: weekdaySymbols,
                cells: []
            )
        }

        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var dates = Array<Date?>(repeating: nil, count: leading)
        dates.append(contentsOf: dayRange.map { day in
            calendar.date(byAdding: .day, value: day - 1, to: month)
        })
        let trailing = (7 - dates.count % 7) % 7
        dates.append(contentsOf: Array(repeating: nil, count: trailing))

        let cells = dates.enumerated().map { index, day -> FocusTraceCalendarDayLayout in
            guard let day else {
                return FocusTraceCalendarDayLayout(
                    id: index,
                    date: nil,
                    dayText: "",
                    accessibilityLabel: ""
                )
            }
            return FocusTraceCalendarDayLayout(
                id: index,
                date: day,
                dayText: String(calendar.component(.day, from: day)),
                accessibilityLabel: accessibilityFormatter.string(from: day)
            )
        }
        return FocusTraceCalendarMonthLayout(
            month: month,
            title: monthTitleFormatter.string(from: month),
            weekdaySymbols: weekdaySymbols,
            cells: cells
        )
    }

    public static func movedMonth(
        from month: Date,
        by offset: Int,
        latestDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        let currentMonth = startOfMonth(containing: month, calendar: calendar)
        let latestMonth = startOfMonth(containing: latestDate, calendar: calendar)
        guard let moved = calendar.date(
            byAdding: .month,
            value: offset,
            to: currentMonth
        ) else {
            return min(currentMonth, latestMonth)
        }
        return min(startOfMonth(containing: moved, calendar: calendar), latestMonth)
    }

    public static func startOfMonth(
        containing date: Date,
        calendar: Calendar = .current
    ) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private static func rotatedWeekdaySymbols(
        calendar: Calendar,
        locale: Locale
    ) -> [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        let symbols = formatter.veryShortStandaloneWeekdaySymbols
            ?? calendar.veryShortStandaloneWeekdaySymbols
        guard !symbols.isEmpty else { return [] }
        let offset = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        return Array(symbols[offset...] + symbols[..<offset])
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
