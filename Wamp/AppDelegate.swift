import Cocoa
import UniformTypeIdentifiers

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var audioEngine: AudioEngine!
    var playlistManager: PlaylistManager!
    var stateManager: StateManager!
    var mainWindow: MainWindow!
    var statusItem: NSStatusItem!
    var hotKeyManager: HotKeyManager!
    private weak var alwaysOnTopMenuItem: NSMenuItem?
    private weak var doubleSizeMenuItem: NSMenuItem?
    private var jumpToFileWindow: JumpToFileWindow?
    private var jumpToFileMonitor: Any?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        audioEngine = AudioEngine()
        playlistManager = PlaylistManager()
        stateManager = StateManager()

        playlistManager.setAudioEngine(audioEngine)

        // Restore state
        let appState = stateManager.loadAppState()
        audioEngine.volume = appState.volume
        audioEngine.balance = appState.balance
        audioEngine.repeatMode = RepeatMode(rawValue: appState.repeatMode) ?? .off
        audioEngine.eqEnabled = appState.eqEnabled


        let eqState = stateManager.loadEQState()
        audioEngine.setAllEQBands(eqState.bands)
        audioEngine.setPreamp(gain: eqState.preampGain)

        let savedTracks = stateManager.loadSavedPlaylist()
        if !savedTracks.isEmpty {
            playlistManager.addTracks(savedTracks)
            if appState.lastTrackIndex >= 0, appState.lastTrackIndex < savedTracks.count {
                playlistManager.currentIndex = appState.lastTrackIndex
                audioEngine.load(url: savedTracks[appState.lastTrackIndex].url)
            }
        }

        // Restore saved skin (synchronous to avoid window flicker)
        if let path = appState.skinPath, FileManager.default.fileExists(atPath: path) {
            try? SkinManager.shared.loadSkinSync(from: URL(fileURLWithPath: path))
        }

        // Create window
        mainWindow = MainWindow()
        mainWindow.bindToModels(audioEngine: audioEngine, playlistManager: playlistManager)
        mainWindow.showEqualizer = appState.showEqualizer
        mainWindow.showPlaylist = appState.showPlaylist
        mainWindow.alwaysOnTop = appState.alwaysOnTop
        mainWindow.equalizerView.autoMode = eqState.autoMode

        let windowOrigin = NSPoint(x: appState.windowX, y: appState.windowY)
        mainWindow.setFrameOrigin(windowOrigin)

        // Ensure window is on a visible screen; center if not
        let isOnScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(mainWindow.frame) }
        if !isOnScreen {
            mainWindow.center()
        }

        mainWindow.makeKeyAndOrderFront(nil)
        mainWindow.applyRegionMaskFromCurrentSkin()

        // Start observing for auto-save
        stateManager.observe(audioEngine: audioEngine, playlistManager: playlistManager)

        // Setup menu bar
        setupMainMenu()

        // Setup system tray
        setupStatusItem()

        // Setup media key handling and Now Playing info
        hotKeyManager = HotKeyManager(audioEngine: audioEngine, playlistManager: playlistManager)

        installJumpToFileShortcut()

        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard mainWindow != nil else { return }
        stateManager.saveWindowState(
            x: mainWindow.frame.origin.x,
            y: mainWindow.frame.origin.y,
            showEQ: mainWindow.showEqualizer,
            showPlaylist: mainWindow.showPlaylist,
            alwaysOnTop: mainWindow.alwaysOnTop,
            audioEngine: audioEngine,
            playlistManager: playlistManager
        )
        stateManager.saveEQState(audioEngine: audioEngine, autoMode: mainWindow.equalizerView.autoMode)
        stateManager.savePlaylist(playlistManager: playlistManager)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { await handleOpenURLs(urls) }
    }

    /// Route incoming URLs. `.cue` files expand into virtual tracks via
    /// `PlaylistManager.addCueSheet`. `.m3u`/`.m3u8` playlists are appended
    /// via `PlaylistManager.addM3U`, with a summary alert if any referenced
    /// files are missing. Folders are recursively scanned. Everything else
    /// falls through to `addURLs`. This method is the single routing entry
    /// point — both `application(_:open:)` and drag-drop go through here.
    @MainActor
    func handleOpenURLs(_ urls: [URL]) async {
        var passthrough: [URL] = []
        var totalMissing = 0
        for url in urls {
            let ext = url.pathExtension.lowercased()
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if exists && isDir.boolValue {
                await playlistManager.addFolder(url)
                continue
            }
            switch ext {
            case "cue":
                do {
                    try await playlistManager.addCueSheet(url: url)
                } catch {
                    presentError(error, context: "Opening \(url.lastPathComponent)")
                }
            case "m3u", "m3u8":
                do {
                    let summary = try await playlistManager.addM3U(url: url)
                    totalMissing += summary.missing
                } catch {
                    presentError(error, context: "Opening \(url.lastPathComponent)")
                }
            default:
                passthrough.append(url)
            }
        }
        if !passthrough.isEmpty {
            await playlistManager.addURLs(passthrough)
        }
        if totalMissing > 0 {
            presentMissingFilesNotice(count: totalMissing)
        }
    }

    @MainActor
    private func presentMissingFilesNotice(count: Int) {
        let alert = NSAlert()
        alert.messageText = "Some tracks couldn't be found"
        alert.informativeText = count == 1
            ? "1 entry in the playlist points to a file that no longer exists on disk."
            : "\(count) entries in the playlist point to files that no longer exist on disk."
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentError(_ error: Error, context: String) {
        let alert = NSAlert()
        alert.messageText = context
        alert.informativeText = (error as NSError).localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Main Menu
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        let aboutItem = NSMenuItem(title: "About Wamp", action: #selector(showAboutPanel), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Wamp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        let openFile = NSMenuItem(title: "Open File...", action: #selector(openFileAction), keyEquivalent: "o")
        openFile.target = self
        fileMenu.addItem(openFile)
        let openFolder = NSMenuItem(title: "Open Folder...", action: #selector(openFolderAction), keyEquivalent: "O")
        openFolder.target = self
        openFolder.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(openFolder)
        fileMenu.addItem(.separator())
        let importMusic = NSMenuItem(title: "Import from Music Library…",
                                     action: #selector(importFromMusicLibraryAction),
                                     keyEquivalent: "")
        importMusic.target = self
        fileMenu.addItem(importMusic)
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Controls menu
        let controlsMenu = NSMenu(title: "Controls")
        let playPause = NSMenuItem(title: "Play/Pause", action: #selector(togglePlayPause), keyEquivalent: " ")
        playPause.target = self
        playPause.keyEquivalentModifierMask = []
        controlsMenu.addItem(playPause)
        let stop = NSMenuItem(title: "Stop", action: #selector(stopAction), keyEquivalent: ".")
        stop.target = self
        controlsMenu.addItem(stop)
        let next = NSMenuItem(title: "Next", action: #selector(nextAction), keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)))
        next.target = self
        next.keyEquivalentModifierMask = [.command]
        controlsMenu.addItem(next)
        let prev = NSMenuItem(title: "Previous", action: #selector(prevAction), keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        prev.target = self
        prev.keyEquivalentModifierMask = [.command]
        controlsMenu.addItem(prev)
        controlsMenu.addItem(.separator())
        let repeat_ = NSMenuItem(title: "Repeat", action: #selector(toggleRepeat), keyEquivalent: "r")
        repeat_.target = self
        controlsMenu.addItem(repeat_)
        let shuffle = NSMenuItem(title: "Shuffle", action: #selector(toggleShuffle), keyEquivalent: "s")
        shuffle.target = self
        controlsMenu.addItem(shuffle)
        controlsMenu.addItem(.separator())
        let jump = NSMenuItem(title: "Jump to File…", action: #selector(presentJumpToFileWindow), keyEquivalent: "j")
        jump.target = self
        jump.keyEquivalentModifierMask = [.command]
        controlsMenu.addItem(jump)
        let controlsMenuItem = NSMenuItem()
        controlsMenuItem.submenu = controlsMenu
        mainMenu.addItem(controlsMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        let showPlayer = NSMenuItem(title: "Show Player", action: #selector(showPlayerAction), keyEquivalent: "1")
        showPlayer.target = self
        viewMenu.addItem(showPlayer)
        let showEQ = NSMenuItem(title: "Show Equalizer", action: #selector(toggleEQ), keyEquivalent: "2")
        showEQ.target = self
        viewMenu.addItem(showEQ)
        let showPL = NSMenuItem(title: "Show Playlist", action: #selector(togglePL), keyEquivalent: "3")
        showPL.target = self
        viewMenu.addItem(showPL)

        viewMenu.addItem(.separator())

        // Always-on-top moved here from the (deleted) pin button in TitleBarView.
        let alwaysOnTop = NSMenuItem(title: "Always on Top", action: #selector(toggleAlwaysOnTop), keyEquivalent: "t")
        alwaysOnTop.keyEquivalentModifierMask = [.command, .shift]
        alwaysOnTop.target = self
        alwaysOnTop.state = mainWindow.alwaysOnTop ? .on : .off
        self.alwaysOnTopMenuItem = alwaysOnTop
        viewMenu.addItem(alwaysOnTop)

        let doubleSize = NSMenuItem(title: "Double Size", action: #selector(toggleDoubleSize), keyEquivalent: "d")
        doubleSize.keyEquivalentModifierMask = [.command, .shift]
        doubleSize.target = self
        doubleSize.state = WinampTheme.scale > WinampTheme.baseScale + 0.01 ? .on : .off
        self.doubleSizeMenuItem = doubleSize
        viewMenu.addItem(doubleSize)

        viewMenu.addItem(.separator())

        let loadSkin = NSMenuItem(title: "Load Skin...", action: #selector(loadSkinAction), keyEquivalent: "S")
        loadSkin.keyEquivalentModifierMask = [.command, .shift]
        loadSkin.target = self
        viewMenu.addItem(loadSkin)

        let unloadSkin = NSMenuItem(title: "Unload Skin", action: #selector(unloadSkinAction), keyEquivalent: "")
        unloadSkin.target = self
        viewMenu.addItem(unloadSkin)

        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Actions
    @objc func showAboutPanel() {
        let credits = NSMutableAttributedString()
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor
        ]
        credits.append(NSAttributedString(
            string: "A modern macOS media player inspired by the classic Winamp experience.\n\n",
            attributes: body
        ))
        credits.append(NSAttributedString(string: "Built with Swift\n\n", attributes: body))
        let linkAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .link: URL(string: "https://github.com/wishval/wamp") as Any,
            .foregroundColor: NSColor.linkColor
        ]
        credits.append(NSAttributedString(string: "GitHub: https://github.com/wishval/wamp",
                                          attributes: linkAttrs))

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Wamp",
            .applicationVersion: "1.1.0",
            .version: "",
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2026 Valerii Bakalenko."
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openFileAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { await self?.handleOpenURLs(panel.urls) }
        }
    }

    private var importMusicController: ImportMusicLibraryWindowController?

    @objc private func importFromMusicLibraryAction() {
        guard let mainWindow = mainWindow else { return }
        let controller = ImportMusicLibraryWindowController()
        importMusicController = controller
        controller.onCancel = { [weak self, weak mainWindow] in
            guard let self, let sheet = self.importMusicController?.window else { return }
            mainWindow?.endSheet(sheet)
            self.importMusicController = nil
        }
        controller.onImport = { [weak self, weak mainWindow] sources, destination in
            guard let self else { return }
            let replace = (destination == .newPlaylist)
            let summary = self.playlistManager.importMusicLibraryTracks(
                sources, replaceCurrent: replace
            )
            if let sheet = self.importMusicController?.window {
                mainWindow?.endSheet(sheet)
            }
            self.importMusicController = nil
            self.presentImportSummary(summary)
        }
        if let sheetWindow = controller.window {
            mainWindow.beginSheet(sheetWindow) { _ in }
        }
        controller.beginLoading()
    }

    @MainActor
    private func presentImportSummary(_ summary: PlaylistManager.LibraryImportSummary) {
        let alert = NSAlert()
        alert.messageText = summary.imported == 1
            ? "Imported 1 track."
            : "Imported \(summary.imported) tracks."
        var lines: [String] = []
        if summary.skippedStreamingOnly > 0 {
            lines.append("Skipped \(summary.skippedStreamingOnly) streaming-only \(summary.skippedStreamingOnly == 1 ? "track" : "tracks").")
        }
        if summary.skippedMissing > 0 {
            lines.append("Skipped \(summary.skippedMissing) \(summary.skippedMissing == 1 ? "track" : "tracks") whose file was missing.")
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func openFolderAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { await self?.playlistManager.addFolder(url) }
        }
    }

    @objc func togglePlayPause() {
        if !audioEngine.isPlaying && audioEngine.currentTime == 0 && audioEngine.duration == 0,
           let track = playlistManager.currentTrack {
            audioEngine.loadAndPlay(url: track.url)
        } else {
            audioEngine.togglePlayPause()
        }
    }
    @objc private func stopAction() { audioEngine.stop() }
    @objc private func nextAction() { playlistManager.playNext() }
    @objc private func prevAction() { playlistManager.playPrevious() }

    @objc private func toggleRepeat() {
        let next = RepeatMode(rawValue: (audioEngine.repeatMode.rawValue + 1) % 3) ?? .off
        audioEngine.repeatMode = next
    }

    @objc private func toggleShuffle() { playlistManager.shuffleTracks() }

    @objc private func showPlayerAction() {
        mainWindow.orderFrontRegardless()
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc private func toggleEQ() { mainWindow.showEqualizer.toggle() }
    @objc private func togglePL() { mainWindow.showPlaylist.toggle() }

    @objc private func toggleAlwaysOnTop() {
        mainWindow.alwaysOnTop.toggle()
        alwaysOnTopMenuItem?.state = mainWindow.alwaysOnTop ? .on : .off

        var state = stateManager.loadAppState()
        state.alwaysOnTop = mainWindow.alwaysOnTop
        stateManager.saveAppState(state)
    }

    @objc func toggleDoubleSize() {
        // Classic Winamp "Double Size" is literally 2× the native 275×116, not 2× the
        // current base scale. Toggle between baseScale (1.3) and 2.0.
        let isDouble = WinampTheme.scale > WinampTheme.baseScale + 0.01
        WinampTheme.scale = isDouble ? WinampTheme.baseScale : 2.0
        mainWindow.recalculateSize()

        // Clamp the window to the current screen's visible frame so Double Size
        // can't push it off the edge when it was close to one.
        if let screen = mainWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            var frame = mainWindow.frame
            if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
            if frame.minX < visible.minX { frame.origin.x = visible.minX }
            if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
            if frame.minY < visible.minY { frame.origin.y = visible.minY }
            if frame != mainWindow.frame {
                mainWindow.setFrameOrigin(frame.origin)
            }
        }

        doubleSizeMenuItem?.state = (WinampTheme.scale > WinampTheme.baseScale + 0.01) ? .on : .off
    }

    @objc private func loadSkinAction() {
        let panel = NSOpenPanel()
        if let wsz = UTType(filenameExtension: "wsz") {
            panel.allowedContentTypes = [wsz, .zip]
        } else {
            panel.allowedContentTypes = [.zip]
        }
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task { @MainActor [weak self] in
            do {
                try await SkinManager.shared.loadSkin(from: url)
                guard let self else { return }
                var state = self.stateManager.loadAppState()
                state.skinPath = url.path
                self.stateManager.saveAppState(state)
                self.mainWindow.recalculateSize()
                self.mainWindow.applyRegionMaskFromCurrentSkin()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Failed to load skin"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    @objc private func unloadSkinAction() {
        SkinManager.shared.unloadSkin()
        var state = stateManager.loadAppState()
        state.skinPath = nil
        stateManager.saveAppState(state)
        mainWindow.recalculateSize()
        mainWindow.applyRegionMaskFromCurrentSkin()
    }

    // MARK: - System Tray
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "♪"

        let menu = NSMenu()
        let show = NSMenuItem(title: "Show Player", action: #selector(showPlayerAction), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        let playPause = NSMenuItem(title: "Play/Pause", action: #selector(togglePlayPause), keyEquivalent: "")
        playPause.target = self
        menu.addItem(playPause)
        let next = NSMenuItem(title: "Next Track", action: #selector(nextAction), keyEquivalent: "")
        next.target = self
        menu.addItem(next)
        let prev = NSMenuItem(title: "Previous Track", action: #selector(prevAction), keyEquivalent: "")
        prev.target = self
        menu.addItem(prev)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))

        statusItem.menu = menu
    }

    // MARK: - Jump to File
    @objc func presentJumpToFileWindow() {
        if jumpToFileWindow == nil {
            let panel = JumpToFileWindow()
            panel.jumpDelegate = self
            jumpToFileWindow = panel
        }
        jumpToFileWindow?.present(over: mainWindow)
    }

    private func installJumpToFileShortcut() {
        // Ctrl+J — Cmd+J is handled by the menu key equivalent.
        jumpToFileMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCtrlJ = mods == .control && event.charactersIgnoringModifiers?.lowercased() == "j"
            if isCtrlJ {
                self?.presentJumpToFileWindow()
                return nil
            }
            return event
        }
    }
}

// MARK: - JumpToFileDelegate
extension AppDelegate: JumpToFileDelegate {
    var jumpCandidates: [JumpFilter.Candidate] {
        playlistManager.tracks.enumerated().map { idx, track in
            JumpFilter.Candidate(
                index: idx,
                displayTitle: track.displayTitle,
                filename: track.url.lastPathComponent
            )
        }
    }

    var currentTrackIndex: Int? {
        playlistManager.currentIndex >= 0 ? playlistManager.currentIndex : nil
    }

    func playTrack(atPlaylistIndex index: Int) {
        playlistManager.playTrack(at: index)
    }
}
