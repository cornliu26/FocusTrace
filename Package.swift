// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FocusTrace",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FocusTraceCore", targets: ["FocusTraceCore"]),
        .executable(name: "FocusTrace", targets: ["FocusTrace"]),
        .executable(name: "FocusTraceReport", targets: ["FocusTraceReport"]),
        .executable(name: "FocusTraceVerification", targets: ["FocusTraceVerification"])
    ],
    targets: [
        .target(name: "FocusTraceCore"),
        .executableTarget(
            name: "FocusTrace",
            dependencies: ["FocusTraceCore"]
        ),
        .executableTarget(
            name: "FocusTraceReport",
            dependencies: ["FocusTraceCore"]
        ),
        .executableTarget(
            name: "FocusTraceVerification",
            dependencies: ["FocusTraceCore"]
        ),
        .testTarget(
            name: "FocusTraceCoreTests",
            dependencies: ["FocusTraceCore"],
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                    "-framework", "Testing"
                ])
            ]
        )
    ]
)
