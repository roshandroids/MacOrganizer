import AppKit

/// Subtle macOS system sounds for key moments — a completed organize/cleanup,
/// an error, a light tap. Never plays if the user turned sound effects off in
/// Settings. Uses the built-in named system sounds, not bundled audio.
@MainActor
final class SoundEffectPlayer {
    /// Every built-in macOS system sound, for the Settings picker.
    static let availableSoundNames = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
        "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    private func play(_ name: String) {
        guard settings.settings.soundEffectsEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    /// A batch of moves/cleanup finished with no errors. Uses the
    /// user-chosen notification sound from Settings.
    func success() { play(settings.settings.notificationSoundName) }
    /// Files moved to Trash.
    func trash() { play("Pop") }
    /// A protected path, a failed operation, a refused action.
    func error() { play("Basso") }
    /// A light acknowledgement (undo, a toggle, a stage transition).
    func tap() { play("Tink") }

    /// Always plays, ignoring the sound-effects-enabled setting — for the
    /// "preview this sound" action in Settings.
    func preview(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}
