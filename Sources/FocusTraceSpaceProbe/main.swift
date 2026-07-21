@preconcurrency import AppKit
import Foundation
import FocusTraceCore
import FocusTraceMacSupport

private struct SpaceProbeOutput: Codable {
    let capturedAt: Date
    let activeSpace: WorkflowSpaceIdentity?
    let displayCurrentSpaces: [WorkflowSpaceIdentity]
    let allSpaces: [WorkflowSpaceIdentity]
}

@main
@MainActor
private struct FocusTraceSpaceProbe {
    static func main() throws {
        _ = NSApplication.shared
        let provider = ManagedSpaceIdentityProvider()
        guard let snapshot = provider.snapshot() else {
            fputs("unable to read managed Space snapshot\n", stderr)
            Foundation.exit(1)
        }
        let output = SpaceProbeOutput(
            capturedAt: Date(),
            activeSpace: provider.activeIdentity(),
            displayCurrentSpaces: snapshot.currentSpaces,
            allSpaces: snapshot.allSpaces
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(output))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
