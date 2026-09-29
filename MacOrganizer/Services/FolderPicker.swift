import AppKit

/// Native folder selection (NSOpenPanel). Never a typed path — a typed path
/// wouldn't carry a security-scoped bookmark under App Sandbox.
enum FolderPicker {
    @MainActor
    static func pickFolder(startingAt url: URL? = nil, prompt: String = "Choose") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.directoryURL = url
        return panel.runModal() == .OK ? panel.url : nil
    }
}
