import Foundation
import Observation
import OrganizerCore

enum CleanupStage: Int, CaseIterable, Identifiable {
    case duplicates, installers, oldFiles, emptyFolders, review, done
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .duplicates: return "Duplicates"
        case .installers: return "Installers"
        case .oldFiles: return "Old Files"
        case .emptyFolders: return "Empty Folders"
        case .review: return "Final Review"
        case .done: return "Done"
        }
    }
}

@MainActor
@Observable
final class CleanupViewModel {
    private(set) var report: ScanReport?
    var stage: CleanupStage = .duplicates
    private(set) var isLoadingReport = false
    private(set) var isExecuting = false
    private(set) var finalErrors: [String] = []
    private(set) var finalRecordCounts: (moved: Int, trashed: Int) = (0, 0)

    var duplicateKeep: [String: Set<URL>] = [:]
    var selectedInstallers: Set<URL> = []
    var selectedOldFiles: Set<URL> = []
    var selectedEmptyFolders: Set<URL> = []
    private(set) var freshEmptyFolders: [EmptyFolderCandidate] = []

    let root: URL
    private let environment: AppEnvironment

    init(environment: AppEnvironment, root: URL) {
        self.environment = environment
        self.root = root
    }

    func loadIfNeeded() async {
        guard report == nil else { return }
        isLoadingReport = true
        let options = environment.analysisOptions()
        let result = await environment.analysisService.analyze(root: root, options: options, clock: environment.clock)
        report = result
        let policy = PathPolicy.system()
        for group in result.duplicateGroups {
            duplicateKeep[group.id] = DuplicateSelection.defaultKeepers(group.items, keepDirectories: environment.settings.resolvedKeepDirectories, policy: policy)
        }
        selectedInstallers = Set(result.oldInstallers.map(\.path))
        selectedOldFiles = Set(result.oldFiles.map(\.path))
        selectedEmptyFolders = Set(result.emptyFolders.map(\.path))
        isLoadingReport = false
    }

    // MARK: - Derived

    var duplicateGroups: [DuplicateGroup] { report?.duplicateGroups ?? [] }
    var duplicateExtrasCount: Int {
        duplicateGroups.reduce(0) { total, group in
            let keep = duplicateKeep[group.id] ?? []
            return total + group.items.filter { !keep.contains($0.path) }.count
        }
    }
    var duplicateExtrasBytes: Int64 {
        duplicateGroups.reduce(Int64(0)) { total, group in
            let keep = duplicateKeep[group.id] ?? []
            let extras = group.items.filter { !keep.contains($0.path) }.count
            return total + Int64(extras) * group.sizeEachBytes
        }
    }
    var selectedInstallersBytes: Int64 {
        (report?.oldInstallers ?? []).filter { selectedInstallers.contains($0.path) }.reduce(Int64(0)) { $0 + $1.size }
    }
    var selectedOldFilesBytes: Int64 {
        (report?.oldFiles ?? []).filter { selectedOldFiles.contains($0.path) }.reduce(Int64(0)) { $0 + $1.size }
    }
    var totalTrashCount: Int { duplicateExtrasCount + selectedInstallers.count + selectedEmptyFolders.count }
    var totalTrashBytes: Int64 { duplicateExtrasBytes + selectedInstallersBytes }
    var totalArchiveCount: Int { selectedOldFiles.count }
    var totalArchiveBytes: Int64 { selectedOldFilesBytes }

    // MARK: - Navigation

    func advance() {
        if stage == .oldFiles {
            // Empty folders can only be judged accurately after archiving would
            // remove files — recompute right before showing that stage.
            freshEmptyFolders = AnalysisService.findEmptyFolders(root: root)
            selectedEmptyFolders = Set(freshEmptyFolders.map(\.path))
        }
        if let next = CleanupStage(rawValue: stage.rawValue + 1) { stage = next }
    }

    func back() {
        if let previous = CleanupStage(rawValue: stage.rawValue - 1) { stage = previous }
    }

    // MARK: - Execution

    func execute() async {
        guard let report else { return }
        isExecuting = true
        let runID = try? await environment.journal.beginRun(root: root, label: "Cleanup \(root.lastPathComponent)")
        var errors: [String] = []
        var movedCount = 0
        var trashedCount = 0

        let decisions = duplicateKeep.map { DuplicateDecision(groupID: $0.key, keepPaths: $0.value) }
        let dupResult = await environment.cleanupService.trashDuplicates(decisions: decisions, groups: report.duplicateGroups)
        await append(dupResult, runID: runID)
        errors += dupResult.errors
        trashedCount += dupResult.trashed.count

        let installerItems = report.oldInstallers.filter { selectedInstallers.contains($0.path) }
        let instResult = await environment.cleanupService.trashOldInstallers(installerItems)
        await append(instResult, runID: runID)
        errors += instResult.errors
        trashedCount += instResult.trashed.count

        let oldItems = report.oldFiles.filter { selectedOldFiles.contains($0.path) }
        let archiveResult = await environment.cleanupService.archiveOldFiles(oldItems, root: root)
        await append(archiveResult, runID: runID)
        errors += archiveResult.errors
        movedCount += archiveResult.records.count

        let emptyCandidates = freshEmptyFolders.filter { selectedEmptyFolders.contains($0.path) }
        let emptyResult = await environment.cleanupService.trashEmptyFolders(emptyCandidates, keepDirectories: environment.settings.resolvedKeepDirectories)
        await append(emptyResult, runID: runID)
        errors += emptyResult.errors
        trashedCount += emptyResult.trashed.count

        if let runID { try? await environment.journal.finish(runID: runID) }
        finalErrors = errors
        finalRecordCounts = (movedCount, trashedCount)
        isExecuting = false
        stage = .done
        if !errors.isEmpty {
            environment.soundPlayer.error()
        } else if trashedCount > 0 {
            environment.soundPlayer.trash()
        } else {
            environment.soundPlayer.success()
        }
        environment.scanCoordinator.refresh(root: root, force: true)
    }

    private func append(_ result: CleanupStageResult, runID: UUID?) async {
        guard let runID else { return }
        for record in result.records {
            try? await environment.journal.append(record, toRun: runID)
        }
        for error in result.errors {
            try? await environment.journal.appendError(error, toRun: runID)
        }
    }
}
