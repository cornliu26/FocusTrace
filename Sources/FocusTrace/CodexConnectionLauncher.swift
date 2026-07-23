import AppKit
import Foundation
import FocusTraceCore

@MainActor
final class CodexConnectionLauncher: ObservableObject {
    enum Status: Equatable {
        case idle
        case preparing
        case opened
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    func connect() {
        guard status != .preparing else { return }
        status = .preparing

        do {
            guard NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.openai.codex"
            ) != nil else {
                throw ConnectionError.codexNotInstalled
            }

            let workspaceURL = try CodexWorkspaceInstaller().prepare()
            guard let deepLink = CodexWorkspaceContract.deepLink(
                workspaceURL: workspaceURL
            ) else {
                throw ConnectionError.invalidDeepLink
            }
            guard NSWorkspace.shared.open(deepLink) else {
                throw ConnectionError.couldNotOpenCodex
            }
            status = .opened
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

private struct CodexWorkspaceInstaller {
    private let fileManager = FileManager.default

    func prepare() throws -> URL {
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let focusTraceURL = applicationSupportURL
            .appendingPathComponent("FocusTrace", isDirectory: true)
        let workspaceURL = focusTraceURL
            .appendingPathComponent(
                CodexWorkspaceContract.workspaceDirectoryName,
                isDirectory: true
            )
        let scriptsURL = workspaceURL
            .appendingPathComponent("Scripts", isDirectory: true)
        let toolsURL = workspaceURL
            .appendingPathComponent("Tools", isDirectory: true)
        let reportsURL = workspaceURL
            .appendingPathComponent(
                CodexWorkspaceContract.reportDirectoryName,
                isDirectory: true
            )

        for directory in [focusTraceURL, workspaceURL, scriptsURL, toolsURL, reportsURL] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        try write(
            CodexWorkspaceContract.agentsInstructions,
            to: workspaceURL.appendingPathComponent("AGENTS.md")
        )
        try write(
            CodexWorkspaceContract.workspaceReadme,
            to: workspaceURL.appendingPathComponent("README.md")
        )

        let generateScriptURL = scriptsURL
            .appendingPathComponent("generate-daily-report.sh")
        try write(CodexWorkspaceContract.reportScript, to: generateScriptURL)
        try makeExecutable(generateScriptURL)

        let reportToolURL = toolsURL.appendingPathComponent("FocusTraceReport")
        try installBundledFile(
            named: "FocusTraceReport",
            subdirectory: "CodexBridge",
            to: reportToolURL
        )
        try makeExecutable(reportToolURL)

        let reviewInstallerURL = scriptsURL
            .appendingPathComponent("install-codex-review.py")
        try installBundledFile(
            named: "install-codex-review",
            extension: "py",
            subdirectory: "CodexBridge",
            to: reviewInstallerURL
        )
        try makeExecutable(reviewInstallerURL)

        let storeURL = focusTraceURL.appendingPathComponent("store.json")
        try generateInitialAggregate(
            reportToolURL: reportToolURL,
            storeURL: storeURL,
            reportsURL: reportsURL
        )
        try registerBridge(
            reportsURL: reportsURL,
            focusTraceURL: focusTraceURL
        )
        return workspaceURL
    }

    private func write(_ text: String, to destination: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw ConnectionError.couldNotEncodeWorkspace
        }
        try data.write(to: destination, options: .atomic)
    }

    private func installBundledFile(
        named name: String,
        extension fileExtension: String? = nil,
        subdirectory: String,
        to destination: URL
    ) throws {
        let bundledURL = Bundle.main.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ) ?? developmentToolURL(named: name, extension: fileExtension)
        guard let bundledURL else {
            throw ConnectionError.missingBundledTool(
                fileExtension.map { "\(name).\($0)" } ?? name
            )
        }
        let data = try Data(contentsOf: bundledURL)
        try data.write(to: destination, options: .atomic)
    }

    private func developmentToolURL(
        named name: String,
        extension fileExtension: String?
    ) -> URL? {
        guard fileExtension == nil,
              let executableDirectory = Bundle.main.executableURL?
                .deletingLastPathComponent() else {
            return nil
        }
        let candidate = executableDirectory.appendingPathComponent(name)
        return fileManager.isExecutableFile(atPath: candidate.path)
            ? candidate
            : nil
    }

    private func makeExecutable(_ url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func generateInitialAggregate(
        reportToolURL: URL,
        storeURL: URL,
        reportsURL: URL
    ) throws {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            throw ConnectionError.missingFocusTraceData
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = reportToolURL
        process.arguments = [
            "--store", storeURL.path,
            "--output-dir", reportsURL.path
        ]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConnectionError.reportGenerationFailed(message)
        }
    }

    private func registerBridge(
        reportsURL: URL,
        focusTraceURL: URL
    ) throws {
        let bridgeURL = focusTraceURL
            .appendingPathComponent("CodexBridge", isDirectory: true)
        try fileManager.createDirectory(
            at: bridgeURL,
            withIntermediateDirectories: true
        )
        let registration = CodexBridgeRegistration(
            reportDirectory: reportsURL.standardizedFileURL.path,
            updatedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(registration).write(
            to: bridgeURL.appendingPathComponent("bridge.json"),
            options: .atomic
        )
    }
}

private enum ConnectionError: LocalizedError {
    case codexNotInstalled
    case invalidDeepLink
    case couldNotOpenCodex
    case couldNotEncodeWorkspace
    case missingBundledTool(String)
    case missingFocusTraceData
    case reportGenerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .codexNotInstalled:
            return "没有找到 ChatGPT / Codex 桌面端，请先安装后再接入"
        case .invalidDeepLink:
            return "无法生成 Codex 接入链接"
        case .couldNotOpenCodex:
            return "Codex 没有成功打开，请确认桌面端可以正常启动"
        case .couldNotEncodeWorkspace:
            return "无法生成 Codex 本地工作区"
        case let .missingBundledTool(name):
            return "安装包缺少 \(name)，请更新或重新安装 FocusTrace"
        case .missingFocusTraceData:
            return "FocusTrace 本地数据尚未准备好，请先完成工作流设置"
        case let .reportGenerationFailed(message):
            return message.isEmpty
                ? "首次聚合报告生成失败"
                : "首次聚合报告生成失败：\(message)"
        }
    }
}
