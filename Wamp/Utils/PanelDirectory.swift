import AppKit

/// Separate "last used folder" memory for open/save panels. Without it every
/// panel shares macOS's single last directory, so picking a skin sent the next
/// Open File into the skins folder.
enum PanelDirectory: String {
    /// Audio files, folders and playlists.
    case music
    case skins

    private var defaultsKey: String { "lastPanelDirectory.\(rawValue)" }

    /// Points `panel` at the folder last used for this purpose (music falls
    /// back to ~/Music; skins to the system's last directory).
    func apply(to panel: NSSavePanel) {
        if let path = UserDefaults.standard.string(forKey: defaultsKey),
           FileManager.default.fileExists(atPath: path) {
            panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        } else if self == .music {
            panel.directoryURL = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
        }
    }

    /// Records the folder containing `url`, so a picked album folder reopens
    /// next to its siblings rather than inside it.
    func remember(_ url: URL?) {
        guard let url else { return }
        UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: defaultsKey)
    }
}
