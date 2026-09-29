import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Reveals files in Finder using NSWorkspace — no shelling out to `open -R`.
@MainActor
public enum FinderService {
    public static func reveal(_ urls: [URL]) {
        #if canImport(AppKit)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        #endif
    }
}
