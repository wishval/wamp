import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    let audioEngine = AudioEngine()
    let playlistManager = PlaylistManager()
    let stateManager = StateManager()
    var mainWindow: MainWindow!
    var statusItem: NSStatusItem!
    var hotKeyManager: HotKeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        playlistManager.setAudioEngine(audioEngine)

        // Restore state
        let appState = stateManager.loadAppState()
        audioEngine.volume = appState.volume
        audioEngine.balance = appState.balance
        audioEngine.repeatMode = RepeatMode(rawValue: appState.repeatMode) ?? .off
        audioEngine.eqEnabled = appState.eqEnabled
        playlistManager.isShuffled = appState.isShuffled

        let eqState = stateManager.loadEQState()
        audioEngine.setAllEQBands(eqState.bands)
        audioEngine.setPreamp(gain: eqState.preampGain)

        let savedTracks = stateManager.loadSavedPlaylist()
        if !savedTracks.isEmpty {
            playlistManager.addTracks(savedTracks)
            if appState.lastTrackIndex >= 0, appState.lastTrackIndex < savedTracks.count {
                playlistManager.currentIndex = appState.lastTrackIndex
            }
        }

        // Create window
        mainWindow = MainWindow()
        mainWindow.bindToModels(audioEngine: audioEngine, playlistManager: playlistManager)
        mainWindow.showEqualizer = appState.showEqualizer
        mainWindow.showPlaylist = appState.showPlaylist

        let windowOrigin = NSPoint(x: appState.windowX, y: appState.windowY)
        mainWindow.setFrameOrigin(windowOrigin)
        mainWindow.makeKeyAndOrderFront(nil)

        // Start observing for auto-save
        stateManager.observe(audioEngine: audioEngine, playlistManager: playlistManager)

        // Setup menu bar
        setupMainMenu()

        // Setup system tray
        setupStatusItem()

        // Setup media key handling and Now Playing info
        hotKeyManager = HotKeyManager(audioEngine: audioEngine, playlistManager: playlistManager)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        stateManager.saveWindowState(
            x: mainWindow.frame.origin.x,
            y: mainWindow.frame.origin.y,
            showEQ: mainWindow.showEqualizer,
            showPlaylist: mainWindow.showPlaylist,
            audioEngine: audioEngine,
            playlistManager: playlistManager
        )
        stateManager.saveEQState(audioEngine: audioEngine)
        stateManager.savePlaylist(playlistManager: playlistManager)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task {
            await playlistManager.addURLs(urls)
        }
    }

    // MARK: - Main Menu
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About WinampMac", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit WinampMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Controls menu
        let controlsMenu = NSMenu(title: "Controls")
        let playPause = NSMenuItem(title: "Play/Pause", action: #selector(togglePlayPause), keyEquivalent: " ")
        playPause.target = self
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
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Actions
    @objc private func openFileAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { await self?.playlistManager.addURLs(panel.urls) }
        }
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

    @objc private func togglePlayPause() { audioEngine.togglePlayPause() }
    @objc private func stopAction() { audioEngine.stop() }
    @objc private func nextAction() { playlistManager.playNext() }
    @objc private func prevAction() { playlistManager.playPrevious() }

    @objc private func toggleRepeat() {
        let next = RepeatMode(rawValue: (audioEngine.repeatMode.rawValue + 1) % 3) ?? .off
        audioEngine.repeatMode = next
    }

    @objc private func toggleShuffle() { playlistManager.toggleShuffle() }

    @objc private func showPlayerAction() {
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleEQ() { mainWindow.showEqualizer.toggle() }
    @objc private func togglePL() { mainWindow.showPlaylist.toggle() }

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
}
