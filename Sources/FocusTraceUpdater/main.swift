import Darwin
import Foundation

private enum UpdaterError: LocalizedError {
    case invalidArguments
    case invalidBundle(String)
    case parentDirectoryMissing
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Usage: FocusTraceUpdater SOURCE_APP TARGET_APP PARENT_PID [--no-launch]"
        case let .invalidBundle(reason):
            return "Invalid update bundle: \(reason)"
        case .parentDirectoryMissing:
            return "The target application directory does not exist."
        case let .processFailed(message):
            return message
        }
    }
}

private struct FocusTraceUpdater {
    let sourceApp: URL
    let targetApp: URL
    let parentPID: pid_t
    let shouldLaunch: Bool
    private let fileManager = FileManager.default

    func run() throws {
        try validateBundle(at: sourceApp)
        waitForParentToExit()

        let installRoot = targetApp.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: installRoot.path) else {
            throw UpdaterError.parentDirectoryMissing
        }

        let nonce = UUID().uuidString
        let stagingRoot = installRoot.appendingPathComponent(".focustrace-update-\(nonce)", isDirectory: true)
        let stagedApp = stagingRoot.appendingPathComponent("FocusTrace.app", isDirectory: true)
        let backupApp = installRoot.appendingPathComponent(".FocusTrace.update-backup-\(nonce).app", isDirectory: true)
        var movedExistingApp = false

        defer {
            try? fileManager.removeItem(at: stagingRoot)
            try? fileManager.removeItem(at: backupApp)
        }

        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: false)
        try fileManager.copyItem(at: sourceApp, to: stagedApp)
        try validateBundle(at: stagedApp)

        do {
            if fileManager.fileExists(atPath: targetApp.path) {
                try fileManager.moveItem(at: targetApp, to: backupApp)
                movedExistingApp = true
            }
            try fileManager.moveItem(at: stagedApp, to: targetApp)
            try validateBundle(at: targetApp)
        } catch {
            try? fileManager.removeItem(at: targetApp)
            if movedExistingApp {
                try? fileManager.moveItem(at: backupApp, to: targetApp)
            }
            throw error
        }

        if shouldLaunch {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [targetApp.path]
            try process.run()
        }
    }

    private func waitForParentToExit() {
        guard parentPID > 1 else { return }
        for _ in 0..<120 {
            if kill(parentPID, 0) != 0 {
                return
            }
            usleep(250_000)
        }
    }

    private func validateBundle(at url: URL) throws {
        guard url.lastPathComponent == "FocusTrace.app",
              let bundle = Bundle(url: url),
              bundle.bundleIdentifier == "com.local.FocusTrace",
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String != nil,
              fileManager.isExecutableFile(
                atPath: url.appendingPathComponent("Contents/MacOS/FocusTrace").path
              ) else {
            throw UpdaterError.invalidBundle(url.path)
        }

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", url.path]
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self)
            throw UpdaterError.processFailed("Signature verification failed: \(message)")
        }
    }
}

do {
    let arguments = CommandLine.arguments
    guard arguments.count == 4 || arguments.count == 5 else {
        throw UpdaterError.invalidArguments
    }
    let updater = FocusTraceUpdater(
        sourceApp: URL(fileURLWithPath: arguments[1], isDirectory: true),
        targetApp: URL(fileURLWithPath: arguments[2], isDirectory: true),
        parentPID: pid_t(arguments[3]) ?? 0,
        shouldLaunch: !arguments.contains("--no-launch")
    )
    try updater.run()
} catch {
    FileHandle.standardError.write(Data("FocusTrace update failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
