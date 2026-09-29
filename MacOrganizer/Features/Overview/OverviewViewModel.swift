import Foundation
import Observation
import OrganizerCore

struct FolderCard: Identifiable {
    enum LoadState: Equatable {
        case loading
        case loaded
        case needsAccess
        case failed(String)
    }

    let id: String
    let entitledURL: URL
    let displayName: String
    let symbolName: String
    var state: LoadState = .loading
    var fileCount = 0
    var totalBytes: Int64 = 0
    var organizableCount = 0
    var oldCount = 0
    /// The URL actually scanned — the entitled path, or a bookmark-resolved
    /// fallback once the user has granted access via the picker.
    var accessibleURL: URL?

    var url: URL { accessibleURL ?? entitledURL }

    var suggestion: String {
        switch state {
        case .loading: return "Scanning…"
        case .needsAccess: return "Tap to allow access"
        case .failed: return "Couldn't scan this folder"
        case .loaded:
            if fileCount == 0 { return "Nothing here yet" }
            if organizableCount > 0 { return "\(organizableCount) file\(organizableCount == 1 ? "" : "s") could be organized" }
            if oldCount > 0 { return "\(oldCount) old file\(oldCount == 1 ? "" : "s") could be archived" }
            return "Already organized"
        }
    }

    var needsAttention: Bool {
        state == .loaded && (organizableCount > 0 || oldCount > 0)
    }
}

@MainActor
@Observable
final class OverviewViewModel {
    private(set) var cards: [FolderCard] = []
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        cards = Self.wellKnownFolders(settings: environment.settings)
    }

    private static func wellKnownFolders(settings: SettingsStore) -> [FolderCard] {
        let fm = FileManager.default
        var result: [FolderCard] = []
        if let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first {
            result.append(FolderCard(id: "desktop", entitledURL: desktop, displayName: "Desktop", symbolName: "menubar.dock.rectangle"))
        }
        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            result.append(FolderCard(id: "documents", entitledURL: documents, displayName: "Documents", symbolName: "folder"))
        }
        if let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            result.append(FolderCard(id: "downloads", entitledURL: downloads, displayName: "Downloads", symbolName: "arrow.down.circle"))
        }
        result.append(FolderCard(id: "applications", entitledURL: URL(fileURLWithPath: "/Applications"), displayName: "Applications", symbolName: "square.grid.3x3"))

        for index in result.indices {
            result[index].accessibleURL = settings.resolvedWellKnownFolders[result[index].id]
        }
        return result
    }

    func refreshAll() async {
        cards = Self.wellKnownFolders(settings: environment.settings)
        let bookmarkedIDs = Set(environment.settings.resolvedWellKnownFolders.keys)
        await withTaskGroup(of: (Int, FolderCard).self) { group in
            for (index, card) in cards.enumerated() {
                group.addTask { [environment] in
                    (index, await Self.load(card, hasBookmark: bookmarkedIDs.contains(card.id), environment: environment))
                }
            }
            for await (index, updated) in group {
                guard index < cards.count else { continue }
                cards[index] = updated
            }
        }
    }

    func grantAccess(for card: FolderCard) {
        guard let picked = FolderPicker.pickFolder(startingAt: card.entitledURL, prompt: "Allow Access") else { return }
        environment.settings.grantWellKnownFolderAccess(picked, folderID: card.id)
        Task { await refreshAll() }
    }

    private static func load(_ card: FolderCard, hasBookmark: Bool, environment: AppEnvironment) async -> FolderCard {
        var card = card
        let scanResult = await FileScanner().scan(root: card.url)
        guard scanResult.errors.isEmpty || !scanResult.files.isEmpty else {
            card.state = hasBookmark
                ? .failed(scanResult.errors.first ?? "Unknown error")
                : .needsAccess
            return card
        }
        card.fileCount = scanResult.files.count
        card.totalBytes = scanResult.files.reduce(Int64(0)) { $0 + $1.size }

        let settings = environment.settings.settings
        let oldCutoff = Date().addingTimeInterval(-Double(settings.oldFileThresholdDays) * 86400)
        card.oldCount = scanResult.files.filter { $0.modificationDate < oldCutoff }.count

        if let plan = try? await environment.organizationService.plan(
            root: card.url, byDate: false, dateFormat: settings.dateFolderFormat,
            recentlyModifiedMinutes: settings.recentlyModifiedMinutes, clock: environment.clock
        ) {
            card.organizableCount = plan.moves.count
        }
        card.state = .loaded
        return card
    }
}
