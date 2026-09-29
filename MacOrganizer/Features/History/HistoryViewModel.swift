import Foundation
import Observation
import OrganizerCore

@MainActor
@Observable
final class HistoryViewModel {
    private(set) var runs: [OperationRun] = []
    private(set) var isLoading = false
    var expandedRunID: UUID?
    var undoResult: UndoResult?
    var undoTargetRun: OperationRun?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func load() async {
        isLoading = true
        runs = await environment.journal.listRuns()
        isLoading = false
    }

    var groupedByDay: [(day: String, runs: [OperationRun])] {
        let grouped = Dictionary(grouping: runs) { run in
            Calendar.current.isDateInToday(run.startedAt) ? "Today" :
                Calendar.current.isDateInYesterday(run.startedAt) ? "Yesterday" : run.startedAt.shortDate
        }
        let order = runs.map { run -> String in
            Calendar.current.isDateInToday(run.startedAt) ? "Today" :
                Calendar.current.isDateInYesterday(run.startedAt) ? "Yesterday" : run.startedAt.shortDate
        }
        var seen = Set<String>()
        let orderedKeys = order.filter { seen.insert($0).inserted }
        return orderedKeys.map { ($0, grouped[$0] ?? []) }
    }

    func undo(_ run: OperationRun) async {
        let result = await environment.undoService.undo(run: run)
        undoResult = result
        undoTargetRun = run
        if result.outcomes.contains(where: \.isSuccess) {
            try? await environment.journal.markUndone(runID: run.id)
        }
        environment.soundPlayer.tap()
        await load()
        environment.scanCoordinator.refresh(root: environment.settings.settings.defaultFolder, force: true)
    }
}
