import Foundation

public enum CodexWorkspaceRefreshPolicy {
    public static func shouldReplace(
        existingData: Data?,
        replacementData: Data
    ) -> Bool {
        existingData != replacementData
    }
}
