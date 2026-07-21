import Combine
import Foundation

@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let workdayNumbers = "workdayNumbers"
        static let workStartMinutes = "workStartMinutes"
        static let workEndMinutes = "workEndMinutes"
        static let reminderThresholdSeconds = "reminderThresholdSeconds"
        static let retentionDays = "retentionDays"
        static let capturePaused = "capturePaused"
        static let launchAtLogin = "launchAtLogin"
        static let attentionCueEnabled = "attentionCueEnabled"
    }

    private let defaults: UserDefaults

    @Published var hasCompletedOnboarding: Bool { didSet { save() } }
    @Published var workdayNumbers: Set<Int> { didSet { save() } }
    @Published var workStartMinutes: Int { didSet { save() } }
    @Published var workEndMinutes: Int { didSet { save() } }
    @Published var reminderThresholdSeconds: Int { didSet { save() } }
    @Published var retentionDays: Int { didSet { save() } }
    @Published var capturePaused: Bool { didSet { save() } }
    @Published var launchAtLogin: Bool { didSet { save() } }
    @Published var attentionCueEnabled: Bool { didSet { save() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        let storedDays = defaults.array(forKey: Key.workdayNumbers) as? [Int]
        workdayNumbers = Set(storedDays ?? [2, 3, 4, 5, 6])
        workStartMinutes = defaults.object(forKey: Key.workStartMinutes) == nil
            ? 9 * 60 + 30
            : defaults.integer(forKey: Key.workStartMinutes)
        workEndMinutes = defaults.object(forKey: Key.workEndMinutes) == nil
            ? 18 * 60 + 30
            : defaults.integer(forKey: Key.workEndMinutes)
        reminderThresholdSeconds = defaults.object(forKey: Key.reminderThresholdSeconds) == nil
            ? 20
            : defaults.integer(forKey: Key.reminderThresholdSeconds)
        retentionDays = defaults.object(forKey: Key.retentionDays) == nil
            ? 90
            : defaults.integer(forKey: Key.retentionDays)
        capturePaused = defaults.bool(forKey: Key.capturePaused)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        attentionCueEnabled = defaults.object(forKey: Key.attentionCueEnabled) == nil
            ? true
            : defaults.bool(forKey: Key.attentionCueEnabled)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        capturePaused = false
    }

    func isWithinWorkSchedule(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        guard workdayNumbers.contains(weekday) else { return false }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if workStartMinutes <= workEndMinutes {
            return minute >= workStartMinutes && minute < workEndMinutes
        }
        return minute >= workStartMinutes || minute < workEndMinutes
    }

    func workRange(for date: Date, calendar: Calendar = .current) -> DateInterval {
        let day = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .minute, value: workStartMinutes, to: day) ?? day
        var end = calendar.date(byAdding: .minute, value: workEndMinutes, to: day) ?? day.addingTimeInterval(86_400)
        if workEndMinutes <= workStartMinutes {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end.addingTimeInterval(86_400)
        }
        return DateInterval(start: start, end: end)
    }

    private func save() {
        defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding)
        defaults.set(Array(workdayNumbers).sorted(), forKey: Key.workdayNumbers)
        defaults.set(workStartMinutes, forKey: Key.workStartMinutes)
        defaults.set(workEndMinutes, forKey: Key.workEndMinutes)
        defaults.set(reminderThresholdSeconds, forKey: Key.reminderThresholdSeconds)
        defaults.set(retentionDays, forKey: Key.retentionDays)
        defaults.set(capturePaused, forKey: Key.capturePaused)
        defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
        defaults.set(attentionCueEnabled, forKey: Key.attentionCueEnabled)
    }
}
