import Combine
import Foundation
import FocusTraceCore

@MainActor
final class CodexReviewBridge: ObservableObject {
    enum Status: Equatable {
        case notConnected
        case noAggregate
        case waiting(AutomationReportArtifact)
        case ready(AutomationReportArtifact, CodexReviewArtifact)
        case invalid(String)
    }

    @Published private(set) var status: Status = .notConnected

    private let fileManager: FileManager
    private let applicationSupportURL: URL
    private let calendar: Calendar

    init(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil,
        calendar: Calendar = .current
    ) {
        self.fileManager = fileManager
        self.applicationSupportURL = applicationSupportURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.calendar = calendar
    }

    func load(for date: Date) {
        let registrationURL = Self.registrationURL(
            applicationSupportURL: applicationSupportURL
        )
        guard fileManager.fileExists(atPath: registrationURL.path) else {
            updateStatus(.notConnected)
            return
        }
        do {
            let registration = try readRegistration(at: registrationURL)
            let reportDirectory = URL(
                fileURLWithPath: registration.reportDirectory,
                isDirectory: true
            ).standardizedFileURL
            let stamp = Self.dateStamp(date, calendar: calendar)
            let reportURL = reportDirectory.appendingPathComponent("\(stamp).json")
            guard fileManager.fileExists(atPath: reportURL.path) else {
                updateStatus(.noAggregate)
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let report = try decoder.decode(
                AutomationReportArtifact.self,
                from: Data(contentsOf: reportURL)
            )
            guard (2...5).contains(report.schemaVersion),
                  calendar.isDate(report.reportDate, inSameDayAs: date) else {
                updateStatus(.invalid("聚合报告协议或日期不匹配"))
                return
            }

            let reviewURL = reportDirectory.appendingPathComponent("codex-\(stamp).json")
            guard fileManager.fileExists(atPath: reviewURL.path) else {
                updateStatus(.waiting(report))
                return
            }
            let review = try decoder.decode(
                CodexReviewArtifact.self,
                from: Data(contentsOf: reviewURL)
            )
            guard review.hasValidShape,
                  review.isConsistentWithBehaviorReliability(
                      report.dataQuality.isReliableForBehavior
                  ),
                  review.isGrounded(in: report),
                  review.sourceReportID == report.reportID,
                  calendar.isDate(review.reportDate, inSameDayAs: report.reportDate) else {
                updateStatus(.invalid("Codex 解读不是基于当前聚合报告，已停止展示"))
                return
            }
            updateStatus(.ready(report, review))
        } catch {
            updateStatus(.invalid(error.localizedDescription))
        }
    }

    func observe(for date: Date) async {
        while !Task.isCancelled {
            load(for: date)
            try? await Task.sleep(for: .seconds(5))
        }
    }

    static func registrationURL(
        applicationSupportURL: URL
    ) -> URL {
        applicationSupportURL
            .appendingPathComponent("FocusTrace", isDirectory: true)
            .appendingPathComponent("CodexBridge", isDirectory: true)
            .appendingPathComponent("bridge.json")
    }

    private func readRegistration(at url: URL) throws -> CodexBridgeRegistration {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let registration = try decoder.decode(
            CodexBridgeRegistration.self,
            from: Data(contentsOf: url)
        )
        guard registration.schemaVersion == 1,
              !registration.reportDirectory.isEmpty else {
            throw BridgeError.invalidRegistration
        }
        return registration
    }

    private func updateStatus(_ nextStatus: Status) {
        guard status != nextStatus else { return }
        status = nextStatus
    }

    private static func dateStamp(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private enum BridgeError: LocalizedError {
    case invalidRegistration

    var errorDescription: String? {
        "Codex 文件桥配置无效"
    }
}
