import Foundation

private func makePreciseISO8601Formatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}

extension JSONEncoder {
    static let organizer: JSONEncoder = {
        let encoder = JSONEncoder()
        // Plain `.iso8601` truncates to whole seconds, which can make two
        // records/runs created moments apart compare equal after a round trip.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(makePreciseISO8601Formatter().string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let organizer: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = makePreciseISO8601Formatter().date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(string)")
            }
            return date
        }
        return decoder
    }()
}

public enum OperationJournalError: Error {
    case runNotFound(UUID)
}

/// Durable, crash-safe log of every move/trash this app performs, and the only
/// source of truth Undo reads from.
///
/// Unlike organize_mac.py — which only writes its log once, at the very end of
/// a run — every recorded operation is flushed to disk (atomic write-then-rename)
/// as soon as it happens. A crash mid-run leaves a journal describing exactly
/// what was actually done, not nothing.
public actor OperationJournal {
    private let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func beginRun(root: URL, label: String) throws -> UUID {
        let run = OperationRun(root: root, label: label)
        try write(run)
        return run.id
    }

    public func append(_ record: OperationRecord, toRun id: UUID) throws {
        var run = try load(id)
        run.records.append(record)
        try write(run)
    }

    public func appendError(_ message: String, toRun id: UUID) throws {
        var run = try load(id)
        run.errors.append(message)
        try write(run)
    }

    public func finish(runID id: UUID) throws {
        var run = try load(id)
        run.finishedAt = Date()
        try write(run)
    }

    public func markUndone(runID id: UUID, at date: Date = Date()) throws {
        var run = try load(id)
        run.undoneAt = date
        try write(run)
    }

    public func load(_ id: UUID) throws -> OperationRun {
        guard let data = try? Data(contentsOf: fileURL(for: id)) else {
            throw OperationJournalError.runNotFound(id)
        }
        return try JSONDecoder.organizer.decode(OperationRun.self, from: data)
    }

    public func listRuns() -> [OperationRun] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? JSONDecoder.organizer.decode(OperationRun.self, from: $0) } }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func write(_ run: OperationRun) throws {
        let data = try JSONEncoder.organizer.encode(run)
        try data.write(to: fileURL(for: run.id), options: .atomic)
    }
}
