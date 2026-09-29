import Foundation

public enum OperationKind: String, Codable, Sendable {
    case organizeMove
    case archiveMove
    case trash
}

/// One completed, reversible-or-not filesystem action. The undo journal is built
/// entirely from these records, so every field needed to verify and reverse the
/// action safely is captured at the moment it happens (not reconstructed later).
public struct OperationRecord: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let kind: OperationKind
    public let source: URL
    /// Move destination (organize/archive). Nil for trash.
    public let destination: URL?
    /// Where Trash actually put the item, when the API reports it. Nil for moves.
    public let trashResultURL: URL?
    public let sizeBytes: Int64
    public let identity: FileIdentity
    public let sourceModificationDate: Date
    public let timestamp: Date
    /// Directories created to make room for this move (deepest first), so undo can
    /// remove only folders this app made — never a folder that pre-existed.
    public let createdDirectories: [URL]

    public init(
        id: UUID = UUID(), kind: OperationKind, source: URL, destination: URL?,
        trashResultURL: URL?, sizeBytes: Int64, identity: FileIdentity,
        sourceModificationDate: Date, timestamp: Date = Date(), createdDirectories: [URL] = []
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.destination = destination
        self.trashResultURL = trashResultURL
        self.sizeBytes = sizeBytes
        self.identity = identity
        self.sourceModificationDate = sourceModificationDate
        self.timestamp = timestamp
        self.createdDirectories = createdDirectories
    }
}

/// A logged batch of operations, the unit shown in History and passed to Undo.
public struct OperationRun: Codable, Sendable, Identifiable {
    public let id: UUID
    public let root: URL
    public let startedAt: Date
    public var finishedAt: Date?
    public var label: String
    public var records: [OperationRecord]
    public var errors: [String]
    /// True once undo has fully or partially reversed this run.
    public var undoneAt: Date?

    public init(
        id: UUID = UUID(), root: URL, startedAt: Date = Date(), finishedAt: Date? = nil,
        label: String, records: [OperationRecord] = [], errors: [String] = [], undoneAt: Date? = nil
    ) {
        self.id = id
        self.root = root
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.label = label
        self.records = records
        self.errors = errors
        self.undoneAt = undoneAt
    }

    public var totalBytes: Int64 { records.reduce(0) { $0 + $1.sizeBytes } }
    public var movedCount: Int { records.filter { $0.kind != .trash }.count }
    public var trashedCount: Int { records.filter { $0.kind == .trash }.count }
}

public enum UndoOutcome: Sendable, Identifiable {
    case restored(OperationRecord)
    case skippedMissingDestination(OperationRecord)
    case skippedSourceOccupied(OperationRecord, occupant: URL)
    case skippedChanged(OperationRecord)
    case failed(OperationRecord, String)

    public var id: UUID { record.id }

    public var record: OperationRecord {
        switch self {
        case .restored(let r), .skippedMissingDestination(let r), .skippedChanged(let r),
             .failed(let r, _):
            return r
        case .skippedSourceOccupied(let r, _):
            return r
        }
    }

    public var isSuccess: Bool {
        if case .restored = self { return true }
        return false
    }
}
