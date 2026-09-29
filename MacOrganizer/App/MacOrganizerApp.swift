import SwiftUI

@main
struct MacOrganizerApp: App {
    @State private var settingsStore: SettingsStore
    @State private var environment: AppEnvironment

    init() {
        let store = SettingsStore()
        _settingsStore = State(initialValue: store)
        _environment = State(initialValue: AppEnvironment(settings: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settingsStore)
                .environment(environment)
                .frame(minWidth: 880, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
