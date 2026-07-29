import AppKit
import Combine
import CryptoKit
import Foundation
import FocusTraceCore

@MainActor
final class UpdateManager: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading
        case readyToRestart
        case failed
    }

    static let releaseFeedURL = URL(
        string: "https://github.com/cornliu26/FocusTrace/releases/latest/download/latest.json"
    )!

    @Published private(set) var state: State = .idle
    @Published private(set) var availableRelease: FocusTraceReleaseManifest?
    @Published private(set) var detail = ""

    private let defaults: UserDefaults
    private let session: URLSession
    private var checkInProgress = false
    private var lastUpdateResult: FocusTraceUpdateResult?

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        if let result = Self.consumePendingUpdateResult() {
            lastUpdateResult = result
            switch result.outcome {
            case .succeeded:
                state = .upToDate
                detail = result.userMessage
            case .failed:
                state = .failed
                detail = "上次更新失败：\(result.userMessage)"
            }
        }
    }

    var currentVersionText: String {
        "\(currentVersion) (\(currentBuild))"
    }

    var isBusy: Bool {
        state == .checking || state == .downloading || state == .readyToRestart
    }

    var feedbackURL: URL? {
        lastUpdateResult?.issueURL(
            installedVersion: currentVersion,
            installedBuild: currentBuild,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    var manualDownloadURL: URL {
        URL(string: "https://github.com/cornliu26/FocusTrace/releases/latest")!
    }

    func checkAutomatically(enabled: Bool) async {
        guard enabled else { return }
        let lastCheck = defaults.object(forKey: "lastAutomaticUpdateCheck") as? Date
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 24 * 60 * 60 {
            return
        }
        await checkForUpdates(userInitiated: false)
    }

    func checkForUpdates(userInitiated: Bool = true) async {
        guard !checkInProgress else { return }
        checkInProgress = true
        state = .checking
        detail = "正在检查 GitHub Release…"
        defer { checkInProgress = false }

        do {
            var request = URLRequest(url: Self.releaseFeedURL)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await session.data(for: request)
            try Self.validateHTTPResponse(response)
            let manifest = try JSONDecoder().decode(FocusTraceReleaseManifest.self, from: data)
            try Self.validate(manifest)
            defaults.set(Date(), forKey: "lastAutomaticUpdateCheck")

            if manifest.isNewer(thanVersion: currentVersion, build: currentBuild) {
                availableRelease = manifest
                lastUpdateResult = nil
                state = .available
                detail = "发现新版本 \(manifest.version)（\(manifest.build)）"
            } else {
                availableRelease = nil
                lastUpdateResult = nil
                state = .upToDate
                detail = "当前已是最新版本"
            }
        } catch {
            let result = Self.failureResult(
                stage: .checking,
                error: error
            )
            lastUpdateResult = result
            state = .failed
            detail = userInitiated
                ? "检查更新失败：\(result.userMessage)"
                : "自动检查暂时失败，下次会重试"
        }
    }

    func installAvailableUpdate() async {
        guard let release = availableRelease, !isBusy else { return }
        var stage = FocusTraceUpdateStage.downloading
        state = .downloading
        detail = "正在下载 FocusTrace \(release.version)…"

        do {
            var request = URLRequest(url: release.assetURL)
            request.timeoutInterval = 120
            let (downloadURL, response) = try await session.download(for: request)
            try Self.validateHTTPResponse(response)

            stage = .verifyingPackage
            let preparedApp = try await Task.detached(priority: .userInitiated) {
                try Self.prepareUpdate(downloadURL: downloadURL, release: release)
            }.value

            stage = .preparingInstall
            state = .readyToRestart
            detail = "更新已验证，正在重启…"
            try Self.launchUpdater(
                sourceApp: preparedApp,
                targetApp: Bundle.main.bundleURL,
                parentPID: ProcessInfo.processInfo.processIdentifier,
                resultURL: Self.updateResultURL()
            )
            NSApp.terminate(nil)
        } catch {
            let result = Self.failureResult(
                stage: stage,
                error: error,
                targetVersion: release.version,
                targetBuild: release.build
            )
            lastUpdateResult = result
            state = .failed
            detail = "安装更新失败：\(result.userMessage)"
        }
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    nonisolated private static func validate(_ manifest: FocusTraceReleaseManifest) throws {
        guard manifest.schemaVersion == 1,
              manifest.bundleIdentifier == "com.local.FocusTrace",
              FocusTraceSemanticVersion(manifest.version) != nil,
              FocusTraceSemanticVersion(manifest.minimumSystemVersion) != nil,
              manifest.hasValidChecksum,
              manifest.size > 0,
              manifest.assetURL.scheme == "https",
              manifest.assetURL.host == "github.com",
              manifest.assetURL.path.hasPrefix(
                "/cornliu26/FocusTrace/releases/download/"
              ),
              manifest.assetURL.lastPathComponent == "FocusTrace-macOS-arm64.zip" else {
            throw UpdateError.invalidManifest
        }
    }

    nonisolated private static func validateHTTPResponse(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw UpdateError.downloadFailed
        }
    }

    nonisolated private static func prepareUpdate(
        downloadURL: URL,
        release: FocusTraceReleaseManifest
    ) throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("FocusTraceUpdate-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)

        let archive = root.appendingPathComponent("FocusTrace.zip")
        try fileManager.copyItem(at: downloadURL, to: archive)
        let values = try archive.resourceValues(forKeys: [.fileSizeKey])
        guard values.fileSize == release.size else {
            throw UpdateError.sizeMismatch
        }
        guard try sha256(of: archive).caseInsensitiveCompare(release.sha256) == .orderedSame else {
            throw UpdateError.checksumMismatch
        }

        let extracted = root.appendingPathComponent("Extracted", isDirectory: true)
        try fileManager.createDirectory(at: extracted, withIntermediateDirectories: false)
        try run(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", archive.path, extracted.path]
        )
        let app = extracted.appendingPathComponent("FocusTrace.app", isDirectory: true)
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == release.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                == release.version,
              bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                == release.build else {
            throw UpdateError.bundleMismatch
        }
        try run(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", app.path]
        )
        return app
    }

    nonisolated private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func launchUpdater(
        sourceApp: URL,
        targetApp: URL,
        parentPID: Int32,
        resultURL: URL
    ) throws {
        guard targetApp.lastPathComponent == "FocusTrace.app" else {
            throw UpdateError.unsupportedInstallLocation
        }
        try verifyWritableInstallRoot(for: targetApp)
        let bundledHelper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/FocusTraceUpdater")
        guard FileManager.default.isExecutableFile(atPath: bundledHelper.path) else {
            throw UpdateError.missingUpdater
        }
        try? FileManager.default.removeItem(at: resultURL)
        let helper = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusTraceUpdater-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: bundledHelper, to: helper)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helper.path
        )
        let process = Process()
        process.executableURL = helper
        process.arguments = [
            sourceApp.path,
            targetApp.path,
            String(parentPID),
            "--result",
            resultURL.path
        ]
        try process.run()
    }

    nonisolated private static func verifyWritableInstallRoot(
        for targetApp: URL
    ) throws {
        let fileManager = FileManager.default
        let installRoot = targetApp.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: installRoot.path) else {
            throw UpdateError.installLocationNotWritable
        }
        let probe = installRoot.appendingPathComponent(
            ".focustrace-update-preflight-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: probe,
                withIntermediateDirectories: false
            )
            try fileManager.removeItem(at: probe)
        } catch {
            try? fileManager.removeItem(at: probe)
            throw UpdateError.installLocationNotWritable
        }
    }

    nonisolated private static func updateResultURL() throws -> URL {
        let fileManager = FileManager.default
        let supportRoot = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = supportRoot.appendingPathComponent(
            "FocusTrace",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let resultURL = directory.appendingPathComponent(
            "last-update-result.json"
        )
        return resultURL
    }

    nonisolated private static func consumePendingUpdateResult()
        -> FocusTraceUpdateResult? {
        guard let resultURL = try? updateResultURL(),
              let data = try? Data(contentsOf: resultURL),
              let result = try? JSONDecoder().decode(
                FocusTraceUpdateResult.self,
                from: data
              ),
              result.schemaVersion == 1 else {
            return nil
        }
        try? FileManager.default.removeItem(at: resultURL)
        return result
    }

    nonisolated private static func failureResult(
        stage: FocusTraceUpdateStage,
        error: Error,
        targetVersion: String? = nil,
        targetBuild: String? = nil
    ) -> FocusTraceUpdateResult {
        FocusTraceUpdateResult(
            outcome: .failed,
            stage: stage,
            failureCode: failureCode(for: error),
            targetVersion: targetVersion,
            targetBuild: targetBuild
        )
    }

    nonisolated private static func failureCode(
        for error: Error
    ) -> FocusTraceUpdateFailureCode {
        if let updateError = error as? UpdateError {
            return updateError.failureCode
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed:
                return .networkUnavailable
            case .timedOut:
                return .requestTimedOut
            default:
                return .downloadFailed
            }
        }
        return .unknown
    }

    nonisolated private static func run(executable: String, arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            throw UpdateError.commandFailed(message)
        }
    }
}

private enum UpdateError: LocalizedError {
    case invalidManifest
    case downloadFailed
    case sizeMismatch
    case checksumMismatch
    case bundleMismatch
    case unsupportedInstallLocation
    case installLocationNotWritable
    case missingUpdater
    case commandFailed(String)

    var failureCode: FocusTraceUpdateFailureCode {
        switch self {
        case .invalidManifest: .invalidManifest
        case .downloadFailed: .downloadFailed
        case .sizeMismatch: .sizeMismatch
        case .checksumMismatch: .checksumMismatch
        case .bundleMismatch: .bundleMismatch
        case .unsupportedInstallLocation: .unsupportedInstallLocation
        case .installLocationNotWritable: .installLocationNotWritable
        case .missingUpdater: .missingUpdater
        case .commandFailed: .signatureVerificationFailed
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidManifest: "更新清单格式或来源无效"
        case .downloadFailed: "下载服务器没有返回成功状态"
        case .sizeMismatch: "下载文件大小与发布清单不一致"
        case .checksumMismatch: "下载文件校验失败"
        case .bundleMismatch: "应用版本或 Bundle ID 与发布清单不一致"
        case .unsupportedInstallLocation: "当前应用不在标准 FocusTrace.app 中"
        case .installLocationNotWritable: "FocusTrace 所在目录不可写"
        case .missingUpdater: "应用包中缺少更新助手"
        case let .commandFailed(message): "系统校验失败：\(message)"
        }
    }
}
