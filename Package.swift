// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FocusTrace",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FocusTraceCore", targets: ["FocusTraceCore"]),
        .library(name: "FocusTraceMacSupport", targets: ["FocusTraceMacSupport"]),
        .executable(name: "FocusTrace", targets: ["FocusTrace"]),
        .executable(name: "FocusTraceReport", targets: ["FocusTraceReport"]),
        .executable(name: "FocusTraceVerification", targets: ["FocusTraceVerification"]),
        .executable(name: "FocusTraceSpaceAcceptance", targets: ["FocusTraceSpaceAcceptance"]),
        .executable(name: "FocusTraceSpaceProbe", targets: ["FocusTraceSpaceProbe"])
    ],
    targets: [
        .target(name: "FocusTraceCore"),
        .target(
            name: "FocusTraceMacSupport",
            dependencies: ["FocusTraceCore"]
        ),
        .executableTarget(
            name: "FocusTrace",
            dependencies: ["FocusTraceCore", "FocusTraceMacSupport"]
        ),
        .executableTarget(
            name: "FocusTraceReport",
            dependencies: ["FocusTraceCore"]
        ),
        .executableTarget(
            name: "FocusTraceVerification",
            dependencies: ["FocusTraceCore"]
        ),
        .executableTarget(
            name: "FocusTraceSpaceAcceptance",
            dependencies: ["FocusTraceCore", "FocusTraceMacSupport"]
        ),
        .executableTarget(
            name: "FocusTraceSpaceProbe",
            dependencies: ["FocusTraceCore", "FocusTraceMacSupport"]
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
