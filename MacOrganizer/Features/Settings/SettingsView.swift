import SwiftUI
import OrganizerCore

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Default folder") {
                    HStack {
                        Text(settingsStore.settings.defaultFolder.abbreviatedPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Button("Choose…") {
                            if let url = FolderPicker.pickFolder(startingAt: settingsStore.settings.defaultFolder, prompt: "Set Default") {
                                settingsStore.setWorkingFolder(url)
                            }
                        }
                    }
                }
                Stepper(
                    "Recently modified threshold: \(settingsStore.settings.recentlyModifiedMinutes) min",
                    value: binding(\.recentlyModifiedMinutes), in: 1...120
                )
                Text("Files changed more recently than this are never touched — they might still be downloading.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Theme", selection: binding(\.themeMode)) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Transparency")
                        Spacer()
                        Text(transparencyLabel).foregroundStyle(.secondary)
                    }
                    Slider(value: binding(\.glassIntensity), in: 0...1)
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text(glassAvailable
                    ? "Controls how much Liquid Glass shows through panels and buttons. 0 is fully solid."
                    : "Controls panel translucency. Full Liquid Glass materials need macOS 26 or later — this Mac uses a translucent approximation instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Sound effects", isOn: binding(\.soundEffectsEnabled))
                Picker("Notification sound", selection: binding(\.notificationSoundName)) {
                    ForEach(SoundEffectPlayer.availableSoundNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .disabled(!settingsStore.settings.soundEffectsEnabled)
                HStack {
                    Spacer()
                    Button {
                        environment.soundPlayer.preview(settingsStore.settings.notificationSoundName)
                    } label: {
                        Label("Preview", systemImage: "speaker.wave.2.fill")
                    }
                }
            } header: {
                Text("Sound")
            } footer: {
                Text("Played when an organize or cleanup finishes successfully.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Organization") {
                Toggle("Organize by date (YYYY-MM subfolders)", isOn: binding(\.organizeByDate))
                Picker("Date folder format", selection: binding(\.dateFolderFormat)) {
                    Text("2026-09").tag(DateFolderFormat.yearMonth)
                    Text("2026").tag(DateFolderFormat.yearOnly)
                }
                Picker("On name collision", selection: binding(\.collisionStrategy)) {
                    Text("Add \"(1)\", \"(2)\"…").tag(CollisionStrategy.numberedParentheses)
                }
                .disabled(true)
                Text("Files are categorized by type — Images, Videos, Documents, Screenshots, and more. Categories aren't user-editable in this version.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Cleanup thresholds") {
                Stepper("Large file: \(settingsStore.settings.largeFileThresholdMB) MB", value: binding(\.largeFileThresholdMB), in: 1...5000, step: 10)
                Stepper("Old file: \(settingsStore.settings.oldFileThresholdDays) days", value: binding(\.oldFileThresholdDays), in: 1...1000, step: 10)
                Stepper("Old installer: \(settingsStore.settings.oldInstallerThresholdDays) days", value: binding(\.oldInstallerThresholdDays), in: 1...365)
            }

            Section {
                if settingsStore.resolvedKeepDirectories.isEmpty {
                    Text("No protected folders. Files inside them are never trashed or archived by cleanup.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(settingsStore.resolvedKeepDirectories.enumerated()), id: \.offset) { _, url in
                        Text(url.abbreviatedPath)
                    }
                    .onDelete { settingsStore.removeKeepDirectories(at: $0) }
                }
                Button("Add Protected Folder…") {
                    if let url = FolderPicker.pickFolder(prompt: "Protect") {
                        settingsStore.addKeepDirectory(url)
                    }
                }
            } header: {
                Text("Protected folders")
            } footer: {
                Text("e.g. ~/Projects, ~/Work — never touched by Organize or Cleanup.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(maxWidth: 640)
    }

    private var transparencyLabel: String {
        switch settingsStore.settings.glassIntensity {
        case ..<0.01: return "Off"
        case ..<0.34: return "Subtle"
        case ..<0.67: return "Standard"
        default: return "Maximum"
        }
    }

    private var glassAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in settingsStore.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
