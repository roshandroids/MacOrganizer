import SwiftUI
import OrganizerCore

struct RootView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @State private var selection: NavigationDestination? = .overview

    private var colorScheme: ColorScheme? {
        switch settingsStore.settings.themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(NavigationDestination.primary) { destination in
                        Label(destination.rawValue, systemImage: destination.symbolName)
                            .tag(destination)
                    }
                }
                Section {
                    ForEach(NavigationDestination.secondary) { destination in
                        Label(destination.rawValue, systemImage: destination.symbolName)
                            .tag(destination)
                    }
                }
            }
            .navigationTitle("Mac Organizer")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            NavigationStack {
                destinationView(for: selection ?? .overview)
            }
        }
        .preferredColorScheme(colorScheme)
    }

    @ViewBuilder
    private func destinationView(for destination: NavigationDestination) -> some View {
        switch destination {
        case .overview: OverviewView(navigate: { selection = $0 })
        case .organize: OrganizeView()
        case .report: ReportView()
        case .cleanup: CleanupView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}
