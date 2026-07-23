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
