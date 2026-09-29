import Foundation

/// Device + inode pair. Two paths sharing one identity are the same file on disk
/// (hard links), not duplicates.
public struct FileIdentity: Sendable, Hashable, Codable {
    public let device: Int32
    public let inode: UInt64

    public init(device: Int32, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

/// Stat snapshot of one regular file at scan time.
public struct FileItem: Sendable, Hashable, Identifiable {
    public let path: URL
    public let size: Int64
    public let modificationDate: Date
    public let identity: FileIdentity

    public var id: String { path.path }

    public init(path: URL, size: Int64, modificationDate: Date, identity: FileIdentity) {
        self.path = path
        self.size = size
        self.modificationDate = modificationDate
        self.identity = identity
    }

    public static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.path == rhs.path
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}
