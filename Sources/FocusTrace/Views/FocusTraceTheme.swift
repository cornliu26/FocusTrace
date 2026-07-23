import SwiftUI
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

struct FocusTraceDateNavigator: View {
    @Binding var selection: Date
    var latestDate = Date()

    @Environment(\.colorScheme) private var colorScheme
    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            dateButton(systemImage: "chevron.left", accessibilityLabel: "前一天") {
                moveSelection(by: -1)
            }

            Divider()
                .frame(height: 18)

            Menu {
                ForEach(quickDates, id: \.self) { date in
                    Button {
                        selection = date
                    } label: {
                        if calendar.isDate(date, inSameDayAs: selectedDay) {
                            Label(menuDateLabel(date), systemImage: "checkmark")
                        } else {
                            Text(menuDateLabel(date))
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                    Text(dateLabel)
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .font(.callout.weight(.medium))
                .frame(minWidth: 142)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("选择日期")
            .accessibilityValue(dateLabel)

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
        selectedDay < latestDay
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

    private var quickDates: [Date] {
        (0..<14).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: latestDay)
        }
    }

    private func menuDateLabel(_ date: Date) -> String {
        if calendar.isDate(date, inSameDayAs: latestDay) {
            return "今天 · \(date.formatted(.dateTime.month().day().weekday(.wide)))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: latestDay),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 · \(date.formatted(.dateTime.month().day().weekday(.wide)))"
        }
        return date.formatted(.dateTime.month().day().weekday(.wide))
    }

    private func moveSelection(by dayOffset: Int) {
        guard let date = calendar.date(byAdding: .day, value: dayOffset, to: selectedDay) else {
            return
        }
        selection = min(date, latestDay)
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
