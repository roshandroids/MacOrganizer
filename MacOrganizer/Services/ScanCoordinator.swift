import Foundation
import Observation
import OrganizerCore

/// Shared scan state so Overview, Report and Cleanup all read the same
/// in-memory report instead of re-scanning the folder on every screen switch.
@MainActor
@Observable
final class ScanCoordinator {
    enum State: Equatable {
        case idle
        case scanning(count: Int)
        case loaded
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var report: ScanReport?
    private(set) var scannedRoot: URL?

    private let analysisService: AnalysisService
    private let clock: Clock
    private let optionsProvider: () -> AnalysisOptions
    private var task: Task<Void, Never>?

    init(analysisService: AnalysisService, clock: Clock, optionsProvider: @escaping () -> AnalysisOptions) {
        self.analysisService = analysisService
        self.clock = clock
        self.optionsProvider = optionsProvider
    }

    /// Scans `root` unless it's already loaded for that same root (pass
    /// `force: true` after an organize/cleanup action changes the filesystem).
    func refresh(root: URL, force: Bool = false) {
        if !force, scannedRoot == root, report != nil, state == .loaded { return }
        task?.cancel()
        state = .scanning(count: 0)
        let options = optionsProvider()
        let service = analysisService
        let clock = clock
        task = Task { [weak self] in
            let result = await service.analyze(root: root, options: options, clock: clock) { count in
                Task { @MainActor in self?.state = .scanning(count: count) }
            }
            guard let self, !Task.isCancelled else { return }
            self.report = result
            self.scannedRoot = root
            self.state = .loaded
        }
    }

    func cancel() {
        task?.cancel()
        state = .idle
    }
}
