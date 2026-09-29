import Foundation

/// A set of byte-identical files (confirmed by cryptographic hash, distinct inodes).
public struct DuplicateGroup: Sendable, Identifiable {
    public let id: String   // sha256 hash of the group's content
    public let items: [FileItem]
    public let sizeEachBytes: Int64

    public init(hash: String, items: [FileItem]) {
        self.id = hash
        self.items = items
        self.sizeEachBytes = items.first?.size ?? 0
    }

    /// Total bytes that would be reclaimed if only one copy were kept.
    public var reclaimableBytes: Int64 {
        sizeEachBytes * Int64(max(items.count - 1, 0))
    }
}

/// User's keep/trash decision for one duplicate group, produced by the review UI.
public struct DuplicateDecision: Sendable {
    public let groupID: String
    public let keepPaths: Set<URL>

    public init(groupID: String, keepPaths: Set<URL>) {
        self.groupID = groupID
        self.keepPaths = keepPaths
    }
}
