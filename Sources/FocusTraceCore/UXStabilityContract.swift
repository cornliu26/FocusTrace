import Foundation

/// Shipped interaction choices that should only change through an intentional
/// product decision accompanied by updated regression tests.
public enum FocusTraceDateSelectionPresentation: String, Codable, Sendable {
    case graphicalCalendarPopover = "focusTrace.dateSelector.graphicalCalendarPopover"
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

public enum FocusTraceUXContract {
    public static let dateSelectionPresentation: FocusTraceDateSelectionPresentation =
        .graphicalCalendarPopover
    public static let calendarPopoverAnimationsEnabled = false
    public static let calendarRefreshGranularity = Calendar.Component.day
    public static let calendarPrewarmMonthOffsets = [-1, 0, 1]
    public static let menuBarWidth = 304.0
    public static let workflowNameInputIdentifier = "workflowName"
    public static let onboardingRequiredInputs = [workflowNameInputIdentifier]
    public static let primaryDailyActionCount = 1
    public static let sidebarIconCanvasSize = 18.0
    public static let sidebarTimelineIcon = "clock.arrow.circlepath"
    public static let timelinePaletteName = "verdant-v1"
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
