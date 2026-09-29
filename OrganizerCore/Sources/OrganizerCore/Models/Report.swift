import Foundation

/// Read-only result of scanning a folder tree. Building this never touches disk
/// beyond stat/read — it is always safe to compute.
public struct ScanReport: Sendable {
    public var files: [FileItem] = []
    public var duplicateGroups: [DuplicateGroup] = []
    public var largeFiles: [FileItem] = []
    public var oldFiles: [FileItem] = []
    public var oldInstallers: [FileItem] = []
    public var emptyFolders: [EmptyFolderCandidate] = []
    public var folderSizes: [String: Int64] = [:]
    public var errors: [String] = []
    public var scannedAt: Date = Date()

    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    public init() {}
}
