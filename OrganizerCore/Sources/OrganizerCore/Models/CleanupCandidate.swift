import Foundation

/// Why a file was selected for a cleanup stage. Shown in the UI ("Why they were selected").
public enum CleanupReason: Sendable, Hashable {
    case oldInstaller(daysOld: Int, threshold: Int)
    case oldFile(daysOld: Int, threshold: Int)
    case duplicateExtra
    case emptyFolder
}

public struct CleanupCandidate: Sendable, Identifiable {
    public let item: FileItem
    public let reason: CleanupReason

    public var id: String { item.path.path }

    public init(item: FileItem, reason: CleanupReason) {
        self.item = item
        self.reason = reason
    }
}

public struct EmptyFolderCandidate: Sendable, Identifiable {
    public let path: URL
    public var id: String { path.path }

    public init(path: URL) {
        self.path = path
    }
}
