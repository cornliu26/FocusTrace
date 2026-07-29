import Foundation
import FocusTraceCore

private struct ReportOptions {
    var storeURL: URL
    var outputDirectory: URL
    var reportDate: Date
    var printReport = false

    init(arguments: [String], calendar: Calendar = .current) throws {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        storeURL = applicationSupport
            .appendingPathComponent("FocusTrace", isDirectory: true)
            .appendingPathComponent("store.json")
        outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".focustrace/reports", isDirectory: true)
        reportDate = Date()

        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--store":
                index += 1
                guard index < arguments.count else { throw OptionError.missingValue("--store") }
                storeURL = URL(fileURLWithPath: arguments[index])
            case "--output-dir":
                index += 1
                guard index < arguments.count else { throw OptionError.missingValue("--output-dir") }
                outputDirectory = URL(fileURLWithPath: arguments[index], isDirectory: true)
            case "--date":
                index += 1
                guard index < arguments.count else { throw OptionError.missingValue("--date") }
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = "yyyy-MM-dd"
                guard let parsed = formatter.date(from: arguments[index]) else {
                    throw OptionError.invalidDate(arguments[index])
                }
                reportDate = parsed
            case "--stdout":
                printReport = true
            case "--help", "-h":
                throw OptionError.help
            default:
                throw OptionError.unknown(arguments[index])
            }
            index += 1
        }
    }
}

private enum OptionError: Error, CustomStringConvertible {
    case help
    case missingValue(String)
    case invalidDate(String)
    case unknown(String)

    var description: String {
        switch self {
        case .help:
            return Self.usage
        case let .missingValue(option):
            return "\(option) 缺少参数\n\n\(Self.usage)"
        case let .invalidDate(value):
            return "无法解析日期 \(value)，应为 yyyy-MM-dd"
        case let .unknown(option):
            return "未知参数：\(option)\n\n\(Self.usage)"
        }
    }

    static let usage = """
    用法：FocusTraceReport [选项]

      --store PATH       FocusTrace store.json 路径
      --output-dir PATH  聚合报告目录（默认 .focustrace/reports）
      --date YYYY-MM-DD  报告日期（默认今天）
      --stdout           同时把聚合报告输出到标准输出
    """
}

private func previousIssuedReport(
    in directory: URL,
    before reportDate: Date,
    calendar: Calendar = .current
) -> AutomationReportArtifact? {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let cutoff = calendar.startOfDay(for: reportDate)
    guard let urls = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ) else { return nil }
    return urls
        .filter { $0.pathExtension == "json" && $0.lastPathComponent != "latest.json" }
        .compactMap { url -> AutomationReportArtifact? in
            guard let data = try? Data(contentsOf: url),
                  let report = try? decoder.decode(AutomationReportArtifact.self, from: data),
                  (2...7).contains(report.schemaVersion),
                  report.reportDate < cutoff else { return nil }
            return report
        }
        .max { $0.reportDate < $1.reportDate }
}

@main
private struct FocusTraceReportCommand {
    static func main() {
        do {
            let options = try ReportOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            let snapshot = try FocusTraceLocalSnapshot.load(from: options.storeURL)
            let previousReport = previousIssuedReport(
                in: options.outputDirectory,
                before: options.reportDate
            )
            let report = AutomationReportEngine.makeReport(
                snapshot: snapshot,
                reportDate: options.reportDate,
                previousIssuedReport: previousReport
            )
            let attentionTrend = AutomationReportEngine.makeAttentionDashboard(
                snapshot: snapshot,
                through: options.reportDate,
                generatedAt: report.generatedAt,
                currentReport: report
            )
            let markdown = AutomationReportEngine.markdown(
                for: report,
                attentionTrend: attentionTrend
            )
            let json = try AutomationReportEngine.jsonData(
                for: report,
                attentionTrend: attentionTrend
            )

            try FileManager.default.createDirectory(
                at: options.outputDirectory,
                withIntermediateDirectories: true
            )
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            let datedURL = options.outputDirectory
                .appendingPathComponent("\(formatter.string(from: report.reportDate)).md")
            let latestURL = options.outputDirectory.appendingPathComponent("latest.md")
            let datedJSONURL = options.outputDirectory
                .appendingPathComponent("\(formatter.string(from: report.reportDate)).json")
            let latestJSONURL = options.outputDirectory.appendingPathComponent("latest.json")
            try markdown.write(to: datedURL, atomically: true, encoding: .utf8)
            try markdown.write(to: latestURL, atomically: true, encoding: .utf8)
            try json.write(to: datedJSONURL, options: .atomic)
            try json.write(to: latestJSONURL, options: .atomic)

            if options.printReport {
                print(markdown, terminator: "")
            } else {
                print("FocusTrace 聚合日报已生成：\(latestURL.path)")
            }
        } catch OptionError.help {
            print(OptionError.usage)
        } catch let error as OptionError {
            let message = "FocusTraceReport 失败：\(error.description)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
        } catch {
            let message = "FocusTraceReport 失败：\(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
        }
    }
}
