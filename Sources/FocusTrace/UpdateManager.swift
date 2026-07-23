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

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
    }

    var currentVersionText: String {
        "\(currentVersion) (\(currentBuild))"
    }

    var isBusy: Bool {
        state == .checking || state == .downloading || state == .readyToRestart
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
                state = .available
                detail = "发现新版本 \(manifest.version)（\(manifest.build)）"
            } else {
                availableRelease = nil
                state = .upToDate
                detail = "当前已是最新版本"
            }
        } catch {
            state = .failed
            detail = userInitiated
                ? "检查更新失败：\(error.localizedDescription)"
                : "自动检查暂时失败，下次会重试"
        }
    }

    func installAvailableUpdate() async {
        guard let release = availableRelease, !isBusy else { return }
        state = .downloading
        detail = "正在下载 FocusTrace \(release.version)…"

        do {
            var request = URLRequest(url: release.assetURL)
            request.timeoutInterval = 120
            let (downloadURL, response) = try await session.download(for: request)
            try Self.validateHTTPResponse(response)

            let preparedApp = try await Task.detached(priority: .userInitiated) {
                try Self.prepareUpdate(downloadURL: downloadURL, release: release)
            }.value

            state = .readyToRestart
            detail = "更新已验证，正在重启…"
            try Self.launchUpdater(
                sourceApp: preparedApp,
                targetApp: Bundle.main.bundleURL,
                parentPID: ProcessInfo.processInfo.processIdentifier
            )
            NSApp.terminate(nil)
        } catch {
            state = .failed
            detail = "安装更新失败：\(error.localizedDescription)"
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
        parentPID: Int32
    ) throws {
        guard targetApp.lastPathComponent == "FocusTrace.app" else {
            throw UpdateError.unsupportedInstallLocation
        }
        let bundledHelper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/FocusTraceUpdater")
        guard FileManager.default.isExecutableFile(atPath: bundledHelper.path) else {
            throw UpdateError.missingUpdater
        }
        let helper = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusTraceUpdater-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: bundledHelper, to: helper)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helper.path
        )
        let process = Process()
        process.executableURL = helper
        process.arguments = [sourceApp.path, targetApp.path, String(parentPID)]
        try process.run()
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
    case missingUpdater
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest: "更新清单格式或来源无效"
        case .downloadFailed: "下载服务器没有返回成功状态"
        case .sizeMismatch: "下载文件大小与发布清单不一致"
        case .checksumMismatch: "下载文件校验失败"
        case .bundleMismatch: "应用版本或 Bundle ID 与发布清单不一致"
        case .unsupportedInstallLocation: "当前应用不在标准 FocusTrace.app 中"
        case .missingUpdater: "应用包中缺少更新助手"
        case let .commandFailed(message): "系统校验失败：\(message)"
        }
    }
}
