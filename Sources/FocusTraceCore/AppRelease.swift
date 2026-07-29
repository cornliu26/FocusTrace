import Foundation

public struct FocusTraceSemanticVersion: Comparable, Equatable, Sendable {
    public let components: [Int]

    public init?(_ value: String) {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        components = parts.map { Int($0) ?? 0 }
    }

    public static func < (
        lhs: FocusTraceSemanticVersion,
        rhs: FocusTraceSemanticVersion
    ) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

public struct FocusTraceReleaseManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let version: String
    public let build: String
    public let minimumSystemVersion: String
    public let bundleIdentifier: String
    public let assetURL: URL
    public let sha256: String
    public let size: Int

    public init(
        schemaVersion: Int = 1,
        version: String,
        build: String,
        minimumSystemVersion: String,
        bundleIdentifier: String,
        assetURL: URL,
        sha256: String,
        size: Int
    ) {
        self.schemaVersion = schemaVersion
        self.version = version
        self.build = build
        self.minimumSystemVersion = minimumSystemVersion
        self.bundleIdentifier = bundleIdentifier
        self.assetURL = assetURL
        self.sha256 = sha256
        self.size = size
    }

    public func isNewer(thanVersion currentVersion: String, build currentBuild: String) -> Bool {
        guard let releaseVersion = FocusTraceSemanticVersion(version),
              let installedVersion = FocusTraceSemanticVersion(currentVersion) else {
            return false
        }
        if releaseVersion != installedVersion {
            return releaseVersion > installedVersion
        }
        return (Int(build) ?? 0) > (Int(currentBuild) ?? 0)
    }

    public var hasValidChecksum: Bool {
        sha256.count == 64 && sha256.allSatisfy(\.isHexDigit)
    }
}

public enum FocusTraceUpdateOutcome: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
}

public enum FocusTraceUpdateStage: String, Codable, Equatable, Sendable {
    case checking
    case downloading
    case verifyingPackage
    case preparingInstall
    case replacingApplication
    case validatingInstalledApplication
    case relaunching
    case completed
}

public enum FocusTraceUpdateFailureCode: String, Codable, Equatable, Sendable {
    case networkUnavailable
    case requestTimedOut
    case invalidManifest
    case downloadFailed
    case sizeMismatch
    case checksumMismatch
    case bundleMismatch
    case unsupportedInstallLocation
    case installLocationNotWritable
    case missingUpdater
    case parentDirectoryMissing
    case signatureVerificationFailed
    case replacementFailed
    case relaunchFailed
    case unknown

    public var userMessage: String {
        switch self {
        case .networkUnavailable:
            "当前网络不可用，请联网后重试"
        case .requestTimedOut:
            "连接 GitHub 超时，请稍后重试"
        case .invalidManifest:
            "更新清单格式或来源无效"
        case .downloadFailed:
            "GitHub 没有返回可用的更新文件"
        case .sizeMismatch:
            "下载文件大小与发布清单不一致"
        case .checksumMismatch:
            "下载文件校验失败"
        case .bundleMismatch:
            "应用版本或 Bundle ID 与发布清单不一致"
        case .unsupportedInstallLocation:
            "当前应用不是标准的 FocusTrace.app"
        case .installLocationNotWritable:
            "FocusTrace 所在目录不可写；请把 App 移到“应用程序”或“个人应用程序”后重试"
        case .missingUpdater:
            "应用包中缺少更新助手"
        case .parentDirectoryMissing:
            "FocusTrace 所在目录已经不存在"
        case .signatureVerificationFailed:
            "新版本的代码签名校验失败"
        case .replacementFailed:
            "macOS 无法替换当前 FocusTrace.app，旧版本已保留"
        case .relaunchFailed:
            "更新已处理，但 macOS 无法重新打开 FocusTrace"
        case .unknown:
            "更新没有完成，旧版本已保留"
        }
    }
}

public struct FocusTraceUpdateResult: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let outcome: FocusTraceUpdateOutcome
    public let stage: FocusTraceUpdateStage
    public let failureCode: FocusTraceUpdateFailureCode?
    public let targetVersion: String?
    public let targetBuild: String?
    public let recordedAt: Date

    public init(
        schemaVersion: Int = 1,
        outcome: FocusTraceUpdateOutcome,
        stage: FocusTraceUpdateStage,
        failureCode: FocusTraceUpdateFailureCode? = nil,
        targetVersion: String? = nil,
        targetBuild: String? = nil,
        recordedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.outcome = outcome
        self.stage = stage
        self.failureCode = failureCode
        self.targetVersion = targetVersion
        self.targetBuild = targetBuild
        self.recordedAt = recordedAt
    }

    public var userMessage: String {
        if outcome == .succeeded {
            if let targetVersion, let targetBuild {
                return "已更新到 \(targetVersion)（\(targetBuild)）"
            }
            return "更新已完成"
        }
        return failureCode?.userMessage ?? FocusTraceUpdateFailureCode.unknown.userMessage
    }

    public func diagnosticText(
        installedVersion: String,
        installedBuild: String,
        systemVersion: String
    ) -> String {
        [
            "FocusTrace: \(installedVersion) (\(installedBuild))",
            "Target: \(targetVersion ?? "unknown") (\(targetBuild ?? "unknown"))",
            "macOS: \(systemVersion)",
            "Stage: \(stage.rawValue)",
            "Code: \(failureCode?.rawValue ?? "none")"
        ].joined(separator: "\n")
    }

    public func issueURL(
        installedVersion: String,
        installedBuild: String,
        systemVersion: String
    ) -> URL? {
        guard outcome == .failed else { return nil }
        var components = URLComponents(
            string: "https://github.com/cornliu26/FocusTrace/issues/new"
        )
        let code = failureCode?.rawValue ?? FocusTraceUpdateFailureCode.unknown.rawValue
        components?.queryItems = [
            URLQueryItem(name: "template", value: "update_failure.yml"),
            URLQueryItem(name: "title", value: "[Update] \(code)"),
            URLQueryItem(
                name: "version",
                value: "\(installedVersion) (\(installedBuild))"
            ),
            URLQueryItem(name: "system", value: systemVersion),
            URLQueryItem(
                name: "diagnostic",
                value: diagnosticText(
                    installedVersion: installedVersion,
                    installedBuild: installedBuild,
                    systemVersion: systemVersion
                )
            )
        ]
        return components?.url
    }
}
