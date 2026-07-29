import AppKit
import Darwin
import Foundation
import FocusTraceCore

private enum UpdaterError: LocalizedError {
    case invalidArguments
    case invalidBundle
    case parentDirectoryMissing
    case signatureVerificationFailed
    case relaunchFailed

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return """
            Usage: FocusTraceUpdater SOURCE_APP TARGET_APP PARENT_PID \
            [--no-launch] [--launch-probe] [--result PATH]
            """
        case .invalidBundle:
            return "The update bundle is not a valid FocusTrace.app."
        case .parentDirectoryMissing:
            return "The target application directory does not exist."
        case .signatureVerificationFailed:
            return "The update bundle signature is invalid."
        case .relaunchFailed:
            return "FocusTrace did not remain running after the update."
        }
    }

    var failureCode: FocusTraceUpdateFailureCode {
        switch self {
        case .invalidArguments:
            return .unknown
        case .invalidBundle:
            return .bundleMismatch
        case .parentDirectoryMissing:
            return .parentDirectoryMissing
        case .signatureVerificationFailed:
            return .signatureVerificationFailed
        case .relaunchFailed:
            return .relaunchFailed
        }
    }
}

private struct UpdaterOptions {
    let sourceApp: URL
    let targetApp: URL
    let parentPID: pid_t
    let shouldLaunch: Bool
    let launchProbe: Bool
    let resultURL: URL?

    static func parse(_ arguments: [String]) throws -> UpdaterOptions {
        guard arguments.count >= 4 else {
            throw UpdaterError.invalidArguments
        }

        var shouldLaunch = true
        var launchProbe = false
        var resultURL: URL?
        var index = 4
        while index < arguments.count {
            switch arguments[index] {
            case "--no-launch":
                shouldLaunch = false
                index += 1
            case "--result":
                guard index + 1 < arguments.count else {
                    throw UpdaterError.invalidArguments
                }
                resultURL = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--launch-probe":
                launchProbe = true
                index += 1
            default:
                throw UpdaterError.invalidArguments
            }
        }

        return UpdaterOptions(
            sourceApp: URL(fileURLWithPath: arguments[1], isDirectory: true),
            targetApp: URL(fileURLWithPath: arguments[2], isDirectory: true),
            parentPID: pid_t(arguments[3]) ?? 0,
            shouldLaunch: shouldLaunch,
            launchProbe: launchProbe,
            resultURL: resultURL
        )
    }
}

private final class FocusTraceUpdater {
    let options: UpdaterOptions
    private let fileManager = FileManager.default
    private(set) var stage = FocusTraceUpdateStage.verifyingPackage
    private(set) var targetVersion: String?
    private(set) var targetBuild: String?

    init(options: UpdaterOptions) {
        self.options = options
    }

    func install() throws {
        let metadata = try validateBundle(at: options.sourceApp)
        targetVersion = metadata.version
        targetBuild = metadata.build
        waitForParentToExit()

        stage = .preparingInstall
        let installRoot = options.targetApp.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: installRoot.path) else {
            throw UpdaterError.parentDirectoryMissing
        }

        let nonce = UUID().uuidString
        let stagingRoot = installRoot.appendingPathComponent(
            ".focustrace-update-\(nonce)",
            isDirectory: true
        )
        let stagedApp = stagingRoot.appendingPathComponent(
            "FocusTrace.app",
            isDirectory: true
        )
        let backupApp = installRoot.appendingPathComponent(
            ".FocusTrace.update-backup-\(nonce).app",
            isDirectory: true
        )
        let hadExistingApp = fileManager.fileExists(
            atPath: options.targetApp.path
        )
        var movedExistingApp = false

        defer {
            try? fileManager.removeItem(at: stagingRoot)
            try? fileManager.removeItem(at: backupApp)
        }

        try fileManager.createDirectory(
            at: stagingRoot,
            withIntermediateDirectories: false
        )
        try fileManager.copyItem(at: options.sourceApp, to: stagedApp)
        _ = try validateBundle(at: stagedApp)

        stage = .replacingApplication
        do {
            if hadExistingApp {
                try fileManager.moveItem(at: options.targetApp, to: backupApp)
                movedExistingApp = true
            }
            try fileManager.moveItem(at: stagedApp, to: options.targetApp)
            stage = .validatingInstalledApplication
            _ = try validateBundle(at: options.targetApp)
            stage = .completed
            writeResult(
                FocusTraceUpdateResult(
                    outcome: .succeeded,
                    stage: .completed,
                    targetVersion: targetVersion,
                    targetBuild: targetBuild
                ),
                to: options.resultURL
            )
            if options.shouldLaunch {
                try launchTarget()
            }
        } catch {
            if movedExistingApp || !hadExistingApp {
                try? fileManager.removeItem(at: options.targetApp)
            }
            if movedExistingApp {
                try? fileManager.moveItem(at: backupApp, to: options.targetApp)
            }
            throw error
        }

        stage = .completed
    }

    func launchTarget() throws {
        stage = .relaunching
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", options.targetApp.path]
        if options.launchProbe {
            process.arguments?.append(contentsOf: [
                "--args",
                "--update-launch-probe"
            ])
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdaterError.relaunchFailed
        }

        let executable = options.targetApp.appendingPathComponent(
            "Contents/MacOS/FocusTrace"
        ).path
        var stayedRunning = false
        for _ in 0..<20 {
            if isRunning(executable: executable) {
                stayedRunning = true
                break
            }
            usleep(250_000)
        }
        if stayedRunning {
            sleep(2)
            stayedRunning = isRunning(executable: executable)
        }
        guard stayedRunning else {
            throw UpdaterError.relaunchFailed
        }
        stage = .completed
    }

    func failureCode(for error: Error) -> FocusTraceUpdateFailureCode {
        if let updaterError = error as? UpdaterError {
            return updaterError.failureCode
        }
        if stage == .relaunching {
            return .relaunchFailed
        }
        if let cocoaError = error as? CocoaError,
           cocoaError.code == .fileWriteNoPermission {
            return .installLocationNotWritable
        }
        return .replacementFailed
    }

    private func isRunning(executable: String) -> Bool {
        let expectedExecutable = URL(fileURLWithPath: executable)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        return NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.local.FocusTrace"
        ).contains {
            $0.executableURL?
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path == expectedExecutable
                && !$0.isTerminated
        }
    }

    private func waitForParentToExit() {
        guard options.parentPID > 1 else { return }
        for _ in 0..<120 {
            if kill(options.parentPID, 0) != 0 {
                return
            }
            usleep(250_000)
        }
    }

    private func validateBundle(
        at url: URL
    ) throws -> (version: String, build: String) {
        guard url.lastPathComponent == "FocusTrace.app",
              let bundle = Bundle(url: url),
              bundle.bundleIdentifier == "com.local.FocusTrace",
              let version = bundle.object(
                  forInfoDictionaryKey: "CFBundleShortVersionString"
              ) as? String,
              let build = bundle.object(
                  forInfoDictionaryKey: "CFBundleVersion"
              ) as? String,
              fileManager.isExecutableFile(
                  atPath: url.appendingPathComponent(
                      "Contents/MacOS/FocusTrace"
                  ).path
              ) else {
            throw UpdaterError.invalidBundle
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", url.path]
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdaterError.signatureVerificationFailed
        }
        return (version, build)
    }
}

private func writeResult(
    _ result: FocusTraceUpdateResult,
    to resultURL: URL?
) {
    guard let resultURL else { return }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(result) else { return }
    try? data.write(to: resultURL, options: .atomic)
}

do {
    let options = try UpdaterOptions.parse(CommandLine.arguments)
    let updater = FocusTraceUpdater(options: options)
    do {
        try updater.install()
    } catch {
        let failure = FocusTraceUpdateResult(
            outcome: .failed,
            stage: updater.stage,
            failureCode: updater.failureCode(for: error),
            targetVersion: updater.targetVersion,
            targetBuild: updater.targetBuild
        )
        writeResult(failure, to: options.resultURL)
        if options.shouldLaunch {
            try? updater.launchTarget()
        }
        FileHandle.standardError.write(
            Data("FocusTrace update failed: \(failure.userMessage)\n".utf8)
        )
        exit(1)
    }
} catch {
    FileHandle.standardError.write(
        Data("FocusTrace update failed: \(error.localizedDescription)\n".utf8)
    )
    exit(1)
}
