import Foundation

enum NavigationDestination: String, Identifiable, CaseIterable, Hashable {
    case overview = "Overview"
    case organize = "Organize"
    case report = "Report"
    case cleanup = "Cleanup"
    case history = "History"
    case settings = "Settings"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .organize: return "folder.badge.gearshape"
        case .report: return "chart.pie"
        case .cleanup: return "sparkles"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }

    static let primary: [NavigationDestination] = [.overview, .organize, .report, .cleanup]
    static let secondary: [NavigationDestination] = [.history, .settings]
}
