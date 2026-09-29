import Foundation
import Observation
import OrganizerCore

/// Wires together the OrganizerCore services the whole app shares. One
/// instance lives for the app's lifetime and is handed down via the
/// SwiftUI environment.
@MainActor
@Observable
final class AppEnvironment {
    let settings: SettingsStore
    let analysisService = AnalysisService()
    let organizationService = OrganizationService()
    let cleanupService: CleanupService
    let undoService = UndoService()
    let journal: OperationJournal
    let clock: Clock = SystemClock()
    let scanCoordinator: ScanCoordinator
    let soundPlayer: SoundEffectPlayer

    init(settings: SettingsStore) {
        self.settings = settings
        self.cleanupService = CleanupService(trashService: SystemTrashService(), policy: .system())
        self.soundPlayer = SoundEffectPlayer(settings: settings)

        let journalDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacOrganizer", isDirectory: true)
            .appendingPathComponent("Journal", isDirectory: true)
        self.journal = (try? OperationJournal(directory: journalDirectory))
            ?? (try! OperationJournal(directory: FileManager.default.temporaryDirectory.appendingPathComponent("MacOrganizerJournal")))

        let analysisService = self.analysisService
        let clock = self.clock
        self.scanCoordinator = ScanCoordinator(analysisService: analysisService, clock: clock) {
            AnalysisOptions(
                largeFileThresholdBytes: settings.settings.largeFileThresholdBytes,
                oldFileThresholdDays: settings.settings.oldFileThresholdDays,
                oldInstallerThresholdDays: settings.settings.oldInstallerThresholdDays,
                recentlyModifiedMinutes: settings.settings.recentlyModifiedMinutes,
                keepDirectories: settings.resolvedKeepDirectories
            )
        }
    }

    func analysisOptions() -> AnalysisOptions {
        AnalysisOptions(
            largeFileThresholdBytes: settings.settings.largeFileThresholdBytes,
            oldFileThresholdDays: settings.settings.oldFileThresholdDays,
            oldInstallerThresholdDays: settings.settings.oldInstallerThresholdDays,
            recentlyModifiedMinutes: settings.settings.recentlyModifiedMinutes,
            keepDirectories: settings.resolvedKeepDirectories
        )
    }
}
