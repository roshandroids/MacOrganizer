import Foundation
import Observation
import OrganizerCore

@MainActor
@Observable
final class OrganizeViewModel {
    enum Phase: Equatable {
        case configuring
        case previewed
        case applying
        case done(movedCount: Int, skippedCount: Int, errorCount: Int)
    }

    var root: URL
    var byDate: Bool
    var phase: Phase = .configuring
    private(set) var plan: OrganizePlan?
    private(set) var protectedPathError: String?
    private(set) var applyErrors: [String] = []

    private let environment: AppEnvironment

    init(environment: AppEnvironment, initialRoot: URL, byDate: Bool) {
        self.environment = environment
        self.root = initialRoot
        self.byDate = byDate
    }

    var groupedByDestination: [(category: String, moves: [PlannedMove])] {
        guard let plan else { return [] }
        let grouped = Dictionary(grouping: plan.moves) { $0.category.rawValue }
        return grouped.keys.sorted().map { key in (key, grouped[key]!.sorted { $0.source.path.path < $1.source.path.path }) }
    }

    func chooseFolder() {
        guard let picked = FolderPicker.pickFolder(startingAt: root, prompt: "Organize") else { return }
        root = picked
        plan = nil
        phase = .configuring
    }

    func preview() async {
        protectedPathError = nil
        let policy = PathPolicy.system()
        guard !policy.isProtectedRoot(root) else {
            protectedPathError = "\(root.abbreviatedPath) is a protected system location and can't be organized."
            environment.soundPlayer.error()
            return
        }
        let settings = environment.settings.settings
        do {
            let result = try await environment.organizationService.plan(
                root: root, byDate: byDate, dateFormat: settings.dateFolderFormat,
                recentlyModifiedMinutes: settings.recentlyModifiedMinutes, clock: environment.clock
            )
            plan = result
            phase = .previewed
        } catch {
            protectedPathError = "Couldn't read \(root.abbreviatedPath): \(error.localizedDescription)"
        }
    }

    func apply() async {
        guard let plan, !plan.moves.isEmpty else { return }
        phase = .applying
        let runID = try? await environment.journal.beginRun(root: root, label: "Organized \(root.lastPathComponent)")
        let (records, errors) = await environment.organizationService.apply(moves: plan.moves)
        if let runID {
            for record in records {
                try? await environment.journal.append(record, toRun: runID)
            }
            for error in errors {
                try? await environment.journal.appendError(error, toRun: runID)
            }
            try? await environment.journal.finish(runID: runID)
        }
        applyErrors = errors
        phase = .done(movedCount: records.count, skippedCount: plan.skippedCount, errorCount: errors.count)
        errors.isEmpty ? environment.soundPlayer.success() : environment.soundPlayer.error()
        environment.scanCoordinator.refresh(root: root, force: true)
    }

    func reset() {
        plan = nil
        applyErrors = []
        phase = .configuring
    }
}
