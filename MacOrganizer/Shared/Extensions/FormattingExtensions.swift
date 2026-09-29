import Foundation
import OrganizerCore

extension Int64 {
    var humanSize: String { HumanSize.string(self) }
}

extension Date {
    var shortDateTime: String {
        formatted(date: .abbreviated, time: .shortened)
    }
    var shortDate: String {
        formatted(date: .abbreviated, time: .omitted)
    }
    var relativeDescription: String {
        formatted(.relative(presentation: .named))
    }
}

extension URL {
    /// Display path with `~` for the home directory, matching Finder-style paths.
    var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
