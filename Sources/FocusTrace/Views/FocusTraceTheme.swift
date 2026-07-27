import AppKit
import SwiftUI
import FocusTraceCore
import FocusTraceMacSupport

enum FocusTraceTheme {
    static let pageMaxWidth: CGFloat = 1040
    static let mint = Color(red: 0.34, green: 0.88, blue: 0.77)
    static let sky = Color(red: 0.35, green: 0.72, blue: 0.98)
    static let coral = Color(red: 1.0, green: 0.48, blue: 0.39)
    static let amber = Color(red: 0.98, green: 0.68, blue: 0.31)
    static let navy = Color(red: 0.045, green: 0.075, blue: 0.13)

    static let accentGradient = LinearGradient(
        colors: [mint, sky],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func screenBackground(_ scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    navy,
                    Color(red: 0.055, green: 0.10, blue: 0.16),
                    Color(red: 0.035, green: 0.065, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.965, green: 0.985, blue: 0.99),
                Color(red: 0.94, green: 0.97, blue: 0.985),
                Color(red: 0.975, green: 0.98, blue: 0.99)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.72)
    }

    static func cardBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.white.opacity(0.9)
    }

    static func elevatedFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.88)
    }
}

struct FocusTraceBrandMark: View {
    var size: CGFloat = 32
    var showsTile = true

    var body: some View {
        ZStack {
            if showsTile {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                FocusTraceTheme.navy,
                                Color(red: 0.06, green: 0.15, blue: 0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    }
            }

            HStack(spacing: -size * 0.055) {
                focusPanel(
                    color: FocusTraceTheme.sky.opacity(0.42),
                    width: size * 0.225,
                    height: size * 0.43
                )
                focusPanel(
                    color: FocusTraceTheme.mint,
                    width: size * 0.235,
                    height: size * 0.54,
                    isFocused: true
                )
                .zIndex(1)
                focusPanel(
                    color: FocusTraceTheme.sky.opacity(0.42),
                    width: size * 0.225,
                    height: size * 0.43
                )
            }
        }
        .frame(width: size, height: size)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private func focusPanel(
        color: Color,
        width: CGFloat,
        height: CGFloat,
        isFocused: Bool = false
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(
                    isFocused
                        ? AnyShapeStyle(FocusTraceTheme.accentGradient)
                        : AnyShapeStyle(color)
                )
            Capsule()
                .fill(Color.white.opacity(isFocused ? 0.9 : 0.34))
                .frame(width: width * 0.56, height: max(1, size * 0.025))
        }
        .frame(width: width, height: height)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.16 : 0.08), lineWidth: 0.7)
        }
    }
}

/// Monochrome menu-bar rendering of the same three-panel FocusTrace mark.
/// macOS owns the menu-bar tint, so this deliberately avoids the app tile and
/// gradient while preserving the brand silhouette.
struct FocusTraceStatusMark: View {
    var isFocusing = false

    var body: some View {
        Image(nsImage: FocusTraceMenuBarIcon.image(isFocusing: isFocusing))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: 18, height: 16)
            .accessibilityHidden(true)
    }
}

struct FocusTraceBrandLockup: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 9 : 12) {
            FocusTraceBrandMark(size: compact ? 32 : 40)
            Text("FocusTrace")
                .font(.system(
                    size: compact ? 16 : 20,
                    weight: .bold,
                    design: .rounded
                ))
        }
    }
}

struct FocusTraceDateNavigator: View, Equatable {
    @Binding var selection: Date
    let latestDate: Date

    @Environment(\.colorScheme) private var colorScheme
    @State private var showingCalendar = false
    private let calendar = Calendar.current
    private let selectedDayIdentity: Date
    private let latestDayIdentity: Date
    private let initialCalendarLayout: FocusTraceCalendarMonthLayout

    init(
        selection: Binding<Date>,
        latestDate: Date = Date()
    ) {
        _selection = selection
        self.latestDate = latestDate
        let calendar = Calendar.current
        selectedDayIdentity = calendar.dateInterval(
            of: FocusTraceUXContract.calendarRefreshGranularity,
            for: selection.wrappedValue
        )?.start ?? calendar.startOfDay(for: selection.wrappedValue)
        latestDayIdentity = calendar.dateInterval(
            of: FocusTraceUXContract.calendarRefreshGranularity,
            for: latestDate
        )?.start ?? calendar.startOfDay(for: latestDate)
        initialCalendarLayout = FocusTraceCalendarLayoutCache.preparedLayout(
            containing: selectedDayIdentity,
            calendar: calendar
        )
    }

    nonisolated static func == (
        left: FocusTraceDateNavigator,
        right: FocusTraceDateNavigator
    ) -> Bool {
        left.selectedDayIdentity == right.selectedDayIdentity
            && left.latestDayIdentity == right.latestDayIdentity
    }

    var body: some View {
        HStack(spacing: 0) {
            dateButton(systemImage: "chevron.left", accessibilityLabel: "前一天") {
                moveSelection(by: -1)
            }

            Divider()
                .frame(height: 18)

            Button {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations =
                    !FocusTraceUXContract.calendarPopoverAnimationsEnabled
                withTransaction(transaction) {
                    showingCalendar = FocusTraceCalendarPopoverState.next(
                        isPresented: showingCalendar,
                        event: .anchorPressed
                    )
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                    Text(dateLabel)
                        .monospacedDigit()
                }
                .font(.callout.weight(.medium))
                .frame(minWidth: 142)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选择日期")
            .accessibilityValue(dateLabel)
            .accessibilityIdentifier(FocusTraceUXContract.dateSelectionPresentation.rawValue)
            .background {
                FocusTraceInstantPopover(isPresented: $showingCalendar) {
                    FocusTraceCalendarPopover(
                        selection: $selection,
                        maximumDate: latestDay,
                        quickSelectionDate: latestDay,
                        initialLayout: initialCalendarLayout
                    ) {
                        showingCalendar = false
                    }
                }
            }

            Divider()
                .frame(height: 18)

            dateButton(systemImage: "chevron.right", accessibilityLabel: "后一天") {
                moveSelection(by: 1)
            }
            .disabled(!canMoveForward)
        }
        .background(
            FocusTraceTheme.elevatedFill(colorScheme),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(FocusTraceTheme.cardBorder(colorScheme), lineWidth: 1)
        }
    }

    private var latestDay: Date {
        calendar.startOfDay(for: latestDate)
    }

    private var selectedDay: Date {
        calendar.startOfDay(for: selection)
    }

    private var canMoveForward: Bool {
        FocusTraceDateNavigation.canMoveForward(
            selection: selection,
            latestDate: latestDate,
            calendar: calendar
        )
    }

    private var dateLabel: String {
        if calendar.isDate(selection, inSameDayAs: latestDay) {
            return "今天 · \(selection.formatted(.dateTime.month().day()))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: latestDay),
           calendar.isDate(selection, inSameDayAs: yesterday) {
            return "昨天 · \(selection.formatted(.dateTime.month().day()))"
        }
        return selection.formatted(date: .abbreviated, time: .omitted)
    }

    private func moveSelection(by dayOffset: Int) {
        selection = FocusTraceDateNavigation.movedSelection(
            selection,
            byDays: dayOffset,
            latestDate: latestDate,
            calendar: calendar
        )
    }

    private func dateButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct FocusTraceCompactDatePicker: View {
    @Binding var selection: Date

    @Environment(\.colorScheme) private var colorScheme
    @State private var showingCalendar = false

    private let label: String
    private let minimumDate: Date?
    private let maximumDate: Date?
    private let quickSelectionDate: Date
    private let initialCalendarLayout: FocusTraceCalendarMonthLayout
    private let calendar = Calendar.current

    init(
        _ label: String,
        selection: Binding<Date>,
        minimumDate: Date? = nil,
        maximumDate: Date? = nil
    ) {
        self.label = label
        _selection = selection
        let calendar = Calendar.current
        self.minimumDate = minimumDate.map(calendar.startOfDay(for:))
        self.maximumDate = maximumDate.map(calendar.startOfDay(for:))
        quickSelectionDate = calendar.startOfDay(for: Date())
        initialCalendarLayout = FocusTraceCalendarLayoutCache.preparedLayout(
            containing: selection.wrappedValue,
            calendar: calendar
        )
    }

    var body: some View {
        Button {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations =
                !FocusTraceUXContract.calendarPopoverAnimationsEnabled
            withTransaction(transaction) {
                showingCalendar = FocusTraceCalendarPopoverState.next(
                    isPresented: showingCalendar,
                    event: .anchorPressed
                )
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(FocusTraceTheme.mint)
                    .frame(width: 28, height: 28)
                    .background(
                        FocusTraceTheme.mint.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(selection.formatted(date: .long, time: .omitted))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                }

                Spacer(minLength: 12)

                Image(systemName: showingCalendar ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 264, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(selection.formatted(date: .long, time: .omitted))
        .accessibilityIdentifier(
            FocusTraceUXContract.requirementDateSelectionPresentation.rawValue
        )
        .background(
            FocusTraceTheme.elevatedFill(colorScheme),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(FocusTraceTheme.cardBorder(colorScheme), lineWidth: 1)
        }
        .background {
            FocusTraceInstantPopover(isPresented: $showingCalendar) {
                FocusTraceCalendarPopover(
                    selection: $selection,
                    minimumDate: minimumDate,
                    maximumDate: maximumDate,
                    quickSelectionDate: quickSelectionDate,
                    initialLayout: initialCalendarLayout
                ) {
                    showingCalendar = false
                }
            }
        }
    }
}

struct FocusTraceCalendarPopover: View {
    @Binding var selection: Date

    @Environment(\.colorScheme) private var colorScheme
    @State private var layout: FocusTraceCalendarMonthLayout

    private let minimumDay: Date?
    private let maximumDay: Date?
    private let quickSelectionDay: Date?
    private let today: Date
    private let dismiss: () -> Void
    private let calendar = Calendar.current
    private let columns = Array(
        repeating: GridItem(.fixed(24), spacing: 5),
        count: 7
    )

    init(
        selection: Binding<Date>,
        minimumDate: Date? = nil,
        maximumDate: Date? = nil,
        quickSelectionDate: Date? = nil,
        initialLayout: FocusTraceCalendarMonthLayout,
        dismiss: @escaping () -> Void
    ) {
        _selection = selection
        let calendar = Calendar.current
        minimumDay = minimumDate.map(calendar.startOfDay(for:))
        maximumDay = maximumDate.map(calendar.startOfDay(for:))
        quickSelectionDay = quickSelectionDate.map(calendar.startOfDay(for:))
        today = calendar.startOfDay(for: Date())
        self.dismiss = dismiss
        _layout = State(initialValue: initialLayout)
    }

    var body: some View {
        VStack(spacing: 9) {
            monthHeader
            weekdayHeader
            dayGrid
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 238)
        .background(
            FocusTraceTheme.cardFill(colorScheme),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .transaction { transaction in
            transaction.disablesAnimations =
                !FocusTraceUXContract.calendarPopoverAnimationsEnabled
        }
    }

    private var monthHeader: some View {
        HStack {
            monthButton(
                systemImage: "chevron.left",
                accessibilityLabel: "上个月"
            ) {
                moveMonth(by: -1)
            }
            .disabled(!canMoveMonth(by: -1))

            Spacer()
            Text(layout.title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Spacer()

            monthButton(
                systemImage: "chevron.right",
                accessibilityLabel: "下个月"
            ) {
                moveMonth(by: 1)
            }
            .disabled(!canMoveMonth(by: 1))
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 5) {
            ForEach(Array(layout.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 16)
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(layout.cells) { cell in
                if let date = cell.date {
                    dayButton(cell, date: date)
                } else {
                    Color.clear
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(selection.formatted(date: .long, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            if let quickSelectionDay,
               FocusTraceCalendarBounds.isSelectable(
                   quickSelectionDay,
                   minimumDate: minimumDay,
                   maximumDate: maximumDay,
                   calendar: calendar
               ) {
                Button("今天") {
                    selection = quickSelectionDay
                    dismiss()
                }
                .buttonStyle(.borderless)
                .disabled(calendar.isDate(selection, inSameDayAs: quickSelectionDay))
            }
        }
    }

    private func canMoveMonth(by offset: Int) -> Bool {
        let target = FocusTraceCalendarBounds.movedMonth(
            from: layout.month,
            by: offset,
            minimumDate: minimumDay,
            maximumDate: maximumDay,
            calendar: calendar
        )
        return target != layout.month
    }

    private func dayButton(
        _ cell: FocusTraceCalendarDayLayout,
        date: Date
    ) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selection)
        let isToday = calendar.isDate(date, inSameDayAs: today)
        let isUnavailable = !FocusTraceCalendarBounds.isSelectable(
            date,
            minimumDate: minimumDay,
            maximumDate: maximumDay,
            calendar: calendar
        )

        return Button {
            selection = calendar.startOfDay(for: date)
            dismiss()
        } label: {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(FocusTraceTheme.accentGradient)
                }

                if isToday && !isSelected {
                    Circle()
                        .stroke(FocusTraceTheme.mint.opacity(0.85), lineWidth: 1.5)
                }

                Text(cell.dayText)
                    .font(.caption.weight(isSelected || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(
                        isUnavailable
                            ? Color.secondary.opacity(0.35)
                            : (isSelected ? FocusTraceTheme.navy : Color.primary)
                    )
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable)
        .accessibilityLabel(cell.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func monthButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 24, height: 24)
                .background(
                    Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func moveMonth(by offset: Int) {
        let target = FocusTraceCalendarBounds.movedMonth(
            from: layout.month,
            by: offset,
            minimumDate: minimumDay,
            maximumDate: maximumDay,
            calendar: calendar
        )
        layout = FocusTraceCalendarLayoutCache.preparedLayout(
            containing: target,
            calendar: calendar
        )
    }
}

@MainActor
private enum FocusTraceCalendarLayoutCache {
    private struct Key: Hashable {
        let era: Int
        let year: Int
        let month: Int
        let calendarIdentifier: String
        let timeZoneIdentifier: String
        let localeIdentifier: String
        let firstWeekday: Int
    }

    private static var layouts: [Key: FocusTraceCalendarMonthLayout] = [:]
    private static let maximumCachedMonths = 36

    static func preparedLayout(
        containing date: Date,
        calendar: Calendar
    ) -> FocusTraceCalendarMonthLayout {
        let locale = Locale.current
        var requested: FocusTraceCalendarMonthLayout?
        for offset in FocusTraceUXContract.calendarPrewarmMonthOffsets {
            guard let nearbyDate = calendar.date(
                byAdding: .month,
                value: offset,
                to: date
            ) else {
                continue
            }
            let key = key(for: nearbyDate, calendar: calendar, locale: locale)
            let layout: FocusTraceCalendarMonthLayout
            if let cached = layouts[key] {
                layout = cached
            } else {
                layout = FocusTraceCalendarLayoutEngine.layout(
                    containing: nearbyDate,
                    calendar: calendar,
                    locale: locale
                )
                layouts[key] = layout
                trimIfNeeded()
            }
            if offset == 0 {
                requested = layout
            }
        }
        return requested ?? FocusTraceCalendarLayoutEngine.layout(
            containing: date,
            calendar: calendar,
            locale: locale
        )
    }

    private static func key(
        for date: Date,
        calendar: Calendar,
        locale: Locale
    ) -> Key {
        let components = calendar.dateComponents([.era, .year, .month], from: date)
        return Key(
            era: components.era ?? 0,
            year: components.year ?? 0,
            month: components.month ?? 0,
            calendarIdentifier: String(describing: calendar.identifier),
            timeZoneIdentifier: calendar.timeZone.identifier,
            localeIdentifier: locale.identifier,
            firstWeekday: calendar.firstWeekday
        )
    }

    private static func trimIfNeeded() {
        while layouts.count > maximumCachedMonths,
              let firstKey = layouts.keys.first {
            layouts.removeValue(forKey: firstKey)
        }
    }
}

@MainActor
private struct FocusTraceInstantPopover<PopoverContent: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> PopoverContent

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.anchorView = nsView
        context.coordinator.update(content: AnyView(content()))

        if isPresented {
            guard !context.coordinator.popover.isShown else { return }
            DispatchQueue.main.async {
                guard isPresented, nsView.window != nil,
                      !context.coordinator.popover.isShown else {
                    return
                }
                context.coordinator.show(relativeTo: nsView)
            }
        } else if context.coordinator.popover.isShown {
            context.coordinator.close()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.close()
        coordinator.stopMonitoring()
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        let popover = NSPopover()
        var isPresented: Binding<Bool>
        weak var anchorView: NSView?
        private var eventMonitor: Any?
        private var resignActiveObserver: NSObjectProtocol?

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
            super.init()
            // The anchor button owns toggling. A transient popover can close on
            // mouse-down before the button sees the second click, which races
            // the binding and immediately reopens it.
            popover.behavior = .applicationDefined
            popover.animates = FocusTraceUXContract.calendarPopoverAnimationsEnabled
            popover.delegate = self
        }

        func update(content: AnyView) {
            if let hostingController =
                popover.contentViewController as? NSHostingController<AnyView> {
                hostingController.rootView = content
            } else {
                popover.contentViewController = NSHostingController(rootView: content)
            }
        }

        func show(relativeTo anchorView: NSView) {
            self.anchorView = anchorView
            popover.show(
                relativeTo: anchorView.bounds,
                of: anchorView,
                preferredEdge: .maxY
            )
            startMonitoring()
        }

        func close() {
            stopMonitoring()
            if popover.isShown {
                popover.performClose(nil)
            }
        }

        private func startMonitoring() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .keyDown]
            ) { [weak self] event in
                guard let self, self.popover.isShown else { return event }
                if event.type == .keyDown, event.keyCode == 53 {
                    self.requestClose()
                    return nil
                }
                guard event.type == .leftMouseDown || event.type == .rightMouseDown else {
                    return event
                }
                if event.window === self.popover.contentViewController?.view.window {
                    return event
                }
                if let anchorView = self.anchorView,
                   event.window === anchorView.window {
                    let location = anchorView.convert(event.locationInWindow, from: nil)
                    if anchorView.bounds.contains(location) {
                        return event
                    }
                }
                self.requestClose()
                return event
            }
            resignActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.requestClose()
                }
            }
        }

        func stopMonitoring() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            if let resignActiveObserver {
                NotificationCenter.default.removeObserver(resignActiveObserver)
                self.resignActiveObserver = nil
            }
        }

        private func requestClose() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let next = FocusTraceCalendarPopoverState.next(
                    isPresented: self.isPresented.wrappedValue,
                    event: .dismissRequested
                )
                if self.isPresented.wrappedValue != next {
                    self.isPresented.wrappedValue = next
                } else {
                    self.close()
                }
            }
        }

        func popoverDidClose(_ notification: Notification) {
            stopMonitoring()
            guard isPresented.wrappedValue else { return }
            DispatchQueue.main.async { [isPresented] in
                isPresented.wrappedValue = FocusTraceCalendarPopoverState.next(
                    isPresented: isPresented.wrappedValue,
                    event: .dismissRequested
                )
            }
        }
    }
}

struct FocusTraceGroupBoxStyle: GroupBoxStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            configuration.label
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            FocusTraceTheme.cardFill(colorScheme),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FocusTraceTheme.cardBorder(colorScheme), lineWidth: 1)
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.13 : 0.055),
            radius: 16,
            x: 0,
            y: 7
        )
    }
}

struct FocusTracePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(FocusTraceTheme.navy)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                FocusTraceTheme.accentGradient,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
            }
            .shadow(
                color: FocusTraceTheme.mint.opacity(configuration.isPressed ? 0.08 : 0.2),
                radius: configuration.isPressed ? 3 : 9,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FocusTraceScreenModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        ZStack {
            FocusTraceTheme.screenBackground(colorScheme)
                .ignoresSafeArea()
            content
        }
    }
}

struct FocusTracePageContentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: FocusTraceTheme.pageMaxWidth, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct FocusTraceVisualSystemModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(FocusTraceTheme.mint)
            .groupBoxStyle(FocusTraceGroupBoxStyle())
    }
}

extension View {
    func focusTraceScreen() -> some View {
        modifier(FocusTraceScreenModifier())
    }

    func focusTracePageContent() -> some View {
        modifier(FocusTracePageContentModifier())
    }

    func focusTraceVisualSystem() -> some View {
        modifier(FocusTraceVisualSystemModifier())
    }
}
